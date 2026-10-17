# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Build coloring pages from LineArt/sources into the app bundle.

Each source dir LineArt/sources/NN-category/NN-slug/ holds one .svg or .png. For each:

  Coloring/Resources/Pages/NN-category/NN-slug/lineart.png   RGBA, black lines + alpha, CANVAS²
  Coloring/Resources/Pages/NN-category/NN-slug/regions.png   8-bit gray, pixel = region ID (1..254)
  Coloring/Resources/Pages/NN-category/NN-slug/thumb.png     THUMB², lines on white
  LineArt/debug/NN-slug.png                                  regions in random colors, for review

NN-slug is the page's ID in the app (its saved artwork is filed under it), so it must be
unique across categories, and moving a page to another category keeps its artwork.

Region IDs are computed here, once, rather than by a flood fill on device: a runtime
fill leaks through any gap and leaves halos at anti-aliased edges, and a leak can only
be caught by a human looking at the debug image — which needs to happen before ship.

Usage: uv run tools/build_pages.py [--only NN-slug ...] [--self-check]
"""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "LineArt" / "sources"
DEBUG = ROOT / "LineArt" / "debug"
OUT = ROOT / "Coloring" / "Resources" / "Pages"

CANVAS = 2048
MARGIN = 0.04
THUMB = 512
# Line width floor in canvas pixels. The canvas shows at ~1440 px on an iPad mini 4,
# so 18 px is ~6 pt — thin lines read as "scribble over it" to a small child.
MIN_LINE = 18.0
# Enclosed areas below this are specks (stamen loops, seed outlines): merged into the
# surrounding lines rather than offered as targets no finger can hit.
NOISE_AREA = 1000
# Reported, not removed: real regions a child will struggle to tap.
SMALL_AREA = 3000
MAX_REGIONS = 254  # 8-bit IDs, 0 reserved
WARN_REGIONS = 40


@dataclass
class Report:
    page: str
    thickness_in: float
    thickness_out: float
    regions: int
    small: int
    merged: int

    def warnings(self) -> list[str]:
        w = []
        if self.regions > WARN_REGIONS:
            w.append(f"{self.regions} regions > {WARN_REGIONS}")
        if self.small:
            w.append(f"{self.small} regions < {SMALL_AREA}px")
        return w


def rasterize(src: Path, tmp: Path) -> np.ndarray:
    """Luminance in [0, 1] on a white CANVAS² page, art centered with MARGIN."""
    box = round(CANVAS * (1 - 2 * MARGIN))
    if src.suffix.lower() == ".svg":
        png = tmp / (src.stem + ".png")
        subprocess.run(
            ["rsvg-convert", "--keep-aspect-ratio", "-w", str(box), "-h", str(box),
             "--background-color", "white", "-o", str(png), str(src)],
            check=True,
        )
        art = Image.open(png)
    else:
        art = Image.open(src)
        scale = box / max(art.size)
        art = art.resize((round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS)
    art = art.convert("RGBA")
    white = Image.new("RGBA", art.size, "white")
    art = Image.alpha_composite(white, art).convert("L")
    page = Image.new("L", (CANVAS, CANVAS), 255)
    page.paste(art, ((CANVAS - art.width) // 2, (CANVAS - art.height) // 2))
    return np.asarray(page, dtype=np.float32) / 255.0


def ink_from_luminance(lum: np.ndarray) -> np.ndarray:
    # Gray is either ink or paper, never a tint left over a child's colors: dark gray
    # (tyres) turns solid, light gray (window frames, shading) vanishes into fillable
    # white. The narrow ramp in between is only the lines' anti-aliased edge.
    return np.clip((0.55 - lum) / 0.2, 0.0, 1.0)


def line_thickness(ink: np.ndarray) -> float:
    """Typical stroke width: the median width along the strokes' center lines.

    Not a mean over the ink: solid black eyes and stamens count as very wide strokes
    there, and the thin lines around them never get thickened.
    """
    mask = ink >= 0.5
    dist = ndimage.distance_transform_edt(mask)
    center = mask & (dist >= ndimage.maximum_filter(dist, size=3))
    return float(np.median(2 * dist[center] - 1)) if center.any() else 0.0


def disk(radius: int) -> np.ndarray:
    y, x = np.ogrid[-radius:radius + 1, -radius:radius + 1]
    return x * x + y * y <= radius * radius


def thicken(ink: np.ndarray) -> tuple[np.ndarray, float, float]:
    before = line_thickness(ink)
    if before >= MIN_LINE:
        return ink, before, before
    radius = math.ceil((MIN_LINE - before) / 2)
    # Gray dilation keeps the anti-aliased edge, so thick lines stay smooth.
    ink = ndimage.grey_dilation(ink, footprint=disk(radius))
    return ink, before, line_thickness(ink)


def label_regions(ink: np.ndarray) -> tuple[np.ndarray, int, int, int]:
    """Region ID per pixel; line pixels take the ID of the nearest region.

    Returns (labels uint8, region count, small-region count, merged speck count).
    """
    lines = ink >= 0.5
    raw, n = ndimage.label(~lines)  # default structure = 4-connectivity
    sizes = np.bincount(raw.ravel(), minlength=n + 1)
    keep = [i for i in range(1, n + 1) if sizes[i] >= NOISE_AREA]
    # Largest first, so the page background is region 1 on every page.
    keep.sort(key=lambda i: -sizes[i])
    if len(keep) > MAX_REGIONS:
        raise ValueError(f"{len(keep)} regions exceed {MAX_REGIONS}")
    lut = np.zeros(n + 1, dtype=np.uint8)
    for new_id, old in enumerate(keep, start=1):
        lut[old] = new_id
    labels = lut[raw]
    # Fill under the lines (and over merged specks) from the nearest region, so a fill
    # runs beneath the anti-aliased edge with no white halo, and a tap that lands on a
    # line still fills something.
    _, (iy, ix) = ndimage.distance_transform_edt(labels == 0, return_indices=True)
    labels = labels[iy, ix]
    small = sum(1 for i in keep if sizes[i] < SMALL_AREA)
    return labels, len(keep), small, n - len(keep)


def debug_image(labels: np.ndarray, ink: np.ndarray, count: int) -> Image.Image:
    rng = np.random.default_rng(7)
    colors = np.zeros((count + 1, 3), dtype=np.float32)
    colors[1:] = rng.uniform(0.35, 1.0, size=(count, 3))
    rgb = colors[labels] * (1.0 - ink[..., None])
    return Image.fromarray((rgb * 255).astype(np.uint8)).resize((1024, 1024), Image.Resampling.LANCZOS)


def build_page(src_dir: Path, out_dir: Path, debug_path: Path | None) -> Report:
    sources = sorted(p for p in src_dir.iterdir() if p.suffix.lower() in (".svg", ".png"))
    if len(sources) != 1:
        raise ValueError(f"{src_dir.name}: expected exactly one .svg/.png, found {len(sources)}")
    with tempfile.TemporaryDirectory() as tmp:
        lum = rasterize(sources[0], Path(tmp))
    ink, before, after = thicken(ink_from_luminance(lum))
    labels, count, small, merged = label_regions(ink)

    out_dir.mkdir(parents=True, exist_ok=True)
    # Line art and thumbnail as 16 levels in 4-bit indexed PNGs, half the bytes (spec §6):
    # a line is ink or paper plus an anti-aliased edge, which loses nothing visible at
    # ±8/255. The region map stays 8-bit: its values are IDs, not tones.
    line = Image.fromarray(np.round(ink * 15).astype(np.uint8), "P")
    line.putpalette([0, 0, 0] * 16)
    line.save(out_dir / "lineart.png", optimize=True, bits=4, transparency=bytes(i * 17 for i in range(16)))
    Image.fromarray(labels, "L").save(out_dir / "regions.png", optimize=True)
    paper = Image.fromarray(((1 - ink) * 255).round().astype(np.uint8), "L").resize((THUMB, THUMB), Image.Resampling.LANCZOS)
    thumb = Image.fromarray(np.round(np.asarray(paper) / 17).astype(np.uint8), "P")
    thumb.putpalette([v for i in range(16) for v in (i * 17,) * 3])
    thumb.save(out_dir / "thumb.png", optimize=True, bits=4)
    if debug_path:
        debug_path.parent.mkdir(parents=True, exist_ok=True)
        debug_image(labels, ink, count).save(debug_path)
    return Report(src_dir.name, before, after, count, small, merged)


def self_check() -> None:
    """Synthetic page: thin square around a circle, plus a speck loop."""
    svg = """<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <rect x="20" y="20" width="160" height="160" fill="none" stroke="black" stroke-width="0.6"/>
  <circle cx="100" cy="100" r="40" fill="#e6e6e6" stroke="black" stroke-width="0.6"/>
  <circle cx="40" cy="40" r="1.2" fill="none" stroke="black" stroke-width="0.4"/>
</svg>"""
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "src" / "00-check"
        src.mkdir(parents=True)
        (src / "page.svg").write_text(svg)
        out = Path(tmp) / "out"
        report = build_page(src, out, None)
        labels = np.asarray(Image.open(out / "regions.png"))
        assert Image.open(out / "lineart.png").mode == "P", "line art must stay 4-bit indexed (spec §6)"
        line = np.asarray(Image.open(out / "lineart.png").convert("RGBA"))
        # outside, ring, disc — the speck is merged, the gray fill is ignored.
        assert report.regions == 3, report
        assert report.merged >= 1, report
        assert labels.dtype == np.uint8 and labels.shape == (CANVAS, CANVAS)
        assert labels.min() == 1 and labels.max() == 3, (labels.min(), labels.max())
        assert report.thickness_in < MIN_LINE <= report.thickness_out + 1.0, report
        assert line[..., 3].max() == 255 and line[..., :3].max() == 0
        # The disc's gray fill must not leave ink inside the circle.
        assert line[CANVAS // 2, CANVAS // 2, 3] == 0
        # Background is region 1 at a corner; the disc owns the center.
        assert labels[5, 5] == 1 and labels[CANVAS // 2, CANVAS // 2] != 1
    print("self-check ok")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", help="page dirs to rebuild (default: all)")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return 0
    if shutil.which("rsvg-convert") is None:
        print("rsvg-convert not found (brew install librsvg)", file=sys.stderr)
        return 1

    dirs = sorted(p for c in SOURCES.iterdir() if c.is_dir() for p in c.iterdir() if p.is_dir())
    names = [d.name for d in dirs]
    if len(set(names)) != len(names):
        print(f"page IDs used twice: {sorted({n for n in names if names.count(n) > 1})}", file=sys.stderr)
        return 1
    if args.only:
        dirs = [d for d in dirs if d.name in args.only]
    else:
        # A full build owns the output: pages whose source was removed must go too.
        if OUT.exists():
            shutil.rmtree(OUT)
    failed = 0
    print(f"{'page':18} {'line in→out':>12} {'regions':>8} {'merged':>7}  warnings")
    for d in dirs:
        try:
            r = build_page(d, OUT / d.parent.name / d.name, DEBUG / f"{d.name}.png")
        except Exception as e:  # report every page, then fail the run
            failed += 1
            print(f"{d.name:18} FAILED: {e}")
            continue
        print(f"{r.page:18} {r.thickness_in:5.1f}→{r.thickness_out:5.1f} {r.regions:8} {r.merged:7}  "
              f"{'; '.join(r.warnings())}")
    print(f"{len(dirs) - failed}/{len(dirs)} pages built → {OUT.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
