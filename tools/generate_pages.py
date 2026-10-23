# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
"""Generate coloring page candidates, review them, and pick one per page.

LineArt/SOURCES.md is the input: its style lines (quoted, each led by the categories it
styles, or by single pages as category/page, which win over their category's) and its table of page | subject | model | seed | edit. Besides LineArt/sources,
everything written here is scratch under LineArt/candidates/ (not committed).

  generate   z-image-turbo (8-bit, or the row's model), seeds 1–3 → candidates/<page>/seed-N.png
  review     each candidate through the page pipeline → candidates/review-NN.png
  edit       qwen-image-edit on the picked seed, per the edit column → candidates/<page>/edit.png
             (steps joined by " → " run in turn; "[N] " before a step sets its seed, default 1)
  pick       the picked seed, or its edit           → LineArt/sources/<category>/<page>/<slug>.png

Review runs the same functions `make pages` does, so a region count on a sheet is the
count the app will get.

Usage: uv run tools/generate_pages.py {generate,review,edit,pick} [--only NN-slug ...]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_pages import ink_from_luminance, label_regions, rasterize, thicken  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCES_MD = ROOT / "LineArt" / "SOURCES.md"
SOURCES = ROOT / "LineArt" / "sources"
CANDIDATES = ROOT / "LineArt" / "candidates"
MODELS = Path.home() / "git" / "mlx-dir" / "models"
# The table's model column: blank is the 8-bit build most pages were made with.
GENERATORS = {
    "": MODELS / "AbstractFramework" / "z-image-turbo-8bit",
    "bf16": MODELS / "mlx-community" / "Z-Image-Turbo-bf16",
}
EDITOR = MODELS / "AbstractFramework" / "qwen-image-edit-2511-8bit"
SEEDS = (1, 2, 3)
EDIT_SUFFIX = "。其他地方都保持不變：黑色手繪線條、純白背景、不上色。"
# Spec §6: background plus at least two colorable regions, at most 30 in all.
MIN_REGIONS, MAX_REGIONS = 3, 30
MAX_SMALL = 3
# Ink deeper than SOLID_CORE from any edge is a filled shape, not a line. A little of
# it is dot eyes (a big pair measured ≤ 12.7k px on the 2048² canvas); filled tyres,
# a panda's patches or an open black mouth measured ≥ 25k.
SOLID_CORE = 25
MAX_SOLID = 20_000
# An outline with a gap lets the background run into the subject. Background with lines
# on all four sides of it is that leak; sound pages have only pockets of it (between
# legs, inside a crescent): ≤ 4.8% of the canvas, leaky ones 8.4–30%.
MAX_ENCLOSED = 0.06


@dataclass
class Row:
    category: str
    page: str
    subject: str
    model: str
    seed: int | None
    edit: str

    @property
    def candidates(self) -> Path:
        return CANDIDATES / self.page

    def style(self, styles: dict[str, str]) -> str:
        # A page can have its own style: a category's style is shared by pages that must
        # keep reproducing, so it can't change for one page that needs another look.
        return styles.get(f"{self.category}/{self.page}", styles[self.category])


def read_sources() -> tuple[dict[str, str], list[Row]]:
    """The style per category, and the table's rows."""
    lines = SOURCES_MD.read_text(encoding="utf-8").splitlines()
    styles, rows = {}, []
    for line in lines:
        if m := re.fullmatch(r"> ((?:\d\d-[a-z-]+(?:/\d\d-[a-z0-9-]+)? ?)+): (.+)", line):
            styles |= dict.fromkeys(m[1].split(), m[2].strip())
        elif m := re.fullmatch(r"\| (\d\d-[a-z-]+)/(\d\d-[a-z0-9-]+) \| (.+?) \| ([a-z0-9]*) *\| (\d*) *\| (.*?) *\|",
                               line):
            rows.append(Row(m[1], m[2], m[3], m[4], int(m[5]) if m[5] else None, m[6]))
    unstyled = sorted({row.category for row in rows} - styles.keys())
    if unstyled:
        sys.exit(f"no style line for: {' '.join(unstyled)}")
    unknown = sorted({row.model for row in rows} - GENERATORS.keys())
    if unknown:
        sys.exit(f"unknown model: {' '.join(unknown)}")
    return styles, rows


def mlxgen(args: list[str], log: Path) -> int:
    with log.open("w") as out:
        return subprocess.run(["mlxgen", "generate", *args, "--no-progress"], stdout=out,
                              stderr=subprocess.STDOUT).returncode


def generate(styles: dict[str, str], rows: list[Row]) -> int:
    failed = 0
    for i, row in enumerate(rows, 1):
        missing = [s for s in SEEDS if not (row.candidates / f"seed-{s}.png").exists()]
        if not missing:
            continue
        row.candidates.mkdir(parents=True, exist_ok=True)
        start = time.monotonic()
        code = mlxgen(["--model", str(GENERATORS[row.model]), "--prompt", row.style(styles) + row.subject, "--steps", "8",
                       "--guidance", "0", "--seed", *map(str, missing), "--width", "1024", "--height", "1024",
                       "--output", str(row.candidates / "seed.png")], row.candidates / "generate.log")
        # mlx-gen names a multi-seed run <stem>_seed_<n>.png, a single-seed run <stem>.png.
        for s in missing:
            made = row.candidates / (f"seed_seed_{s}.png" if len(missing) > 1 else "seed.png")
            if made.exists():
                made.rename(row.candidates / f"seed-{s}.png")
        got = sum((row.candidates / f"seed-{s}.png").exists() for s in missing)
        failed += code != 0 or got != len(missing)
        print(f"[{i}/{len(rows)}] {row.page}: {got}/{len(missing)} in {time.monotonic() - start:.0f}s"
              + ("" if code == 0 else f" (mlxgen exit {code})"), flush=True)
    return 1 if failed else 0


def boxed_in(lines: np.ndarray) -> np.ndarray:
    """Pixels with a line somewhere above, below, left and right of them."""
    seen = lambda a, axis: np.maximum.accumulate(a, axis=axis)
    seen_back = lambda a, axis: np.flip(seen(np.flip(a, axis), axis), axis)
    return seen(lines, 0) & seen(lines, 1) & seen_back(lines, 0) & seen_back(lines, 1)


def evaluate(png: Path) -> list[str]:
    """Why the page pipeline would reject it (empty if it wouldn't)."""
    with tempfile.TemporaryDirectory() as tmp:
        lum = rasterize(png, Path(tmp))
    ink, _, _ = thicken(ink_from_luminance(lum))
    labels, count, small, _ = label_regions(ink)
    problems = []
    if not MIN_REGIONS <= count <= MAX_REGIONS:
        problems.append(f"{count} regions")
    if small > MAX_SMALL:
        problems.append(f"{small} small")
    if (ndimage.distance_transform_edt(ink >= 0.5) > SOLID_CORE).sum() > MAX_SOLID:
        problems.append("solid black")
    # Region 1 is the background.
    if ((labels == 1) & (ink < 0.5) & boxed_in(ink >= 0.5)).mean() > MAX_ENCLOSED:
        problems.append("leak")
    return problems


def review(rows: list[Row]) -> int:
    """Sheets of six pages, a row each: every candidate, flagged in red with why it fails."""
    tile, label, per_sheet = 320, 26, 6
    font = ImageFont.load_default(size=18)
    sheets = [rows[i:i + per_sheet] for i in range(0, len(rows), per_sheet)]
    passed = 0
    for n, sheet_rows in enumerate(sheets, 1):
        sheet = Image.new("RGB", (tile * 4, (tile + label) * len(sheet_rows)), "white")
        draw = ImageDraw.Draw(sheet)
        for r, row in enumerate(sheet_rows):
            y = r * (tile + label)
            pngs = [row.candidates / f"seed-{s}.png" for s in SEEDS] + [row.candidates / "edit.png"]
            for c, png in enumerate(pngs):
                if not png.exists():
                    continue
                problems = evaluate(png)
                passed += not problems
                if problems:
                    print(f"{row.page} {png.stem}: {', '.join(problems)}")
                sheet.paste(Image.open(png).convert("RGB").resize((tile - 8, tile - 8)), (c * tile + 4, y + label))
                if problems:
                    draw.rectangle([c * tile + 2, y + label - 2, (c + 1) * tile - 3, y + label + tile - 7],
                                   outline="red", width=4)
                text = f"{row.page} {png.stem}" + (f": {', '.join(problems)}" if problems else "")
                draw.text((c * tile + 6, y + 4), text, fill="red" if problems else "black", font=font)
        out = CANDIDATES / f"review-{n:02}.png"
        sheet.save(out)
        print(out.relative_to(ROOT), flush=True)
    print(f"{passed} candidates pass the automatic checks")
    return 0


def edit(rows: list[Row]) -> int:
    failed = 0
    for row in rows:
        if not row.edit:
            continue
        if row.seed is None:
            print(f"{row.page}: an edit needs a picked seed", file=sys.stderr)
            failed += 1
            continue
        # Steps run in turn, each on the one before: Qwen does one kind of fix well per
        # pass, and asking for several at once left half of them undone.
        steps = row.edit.split(" → ")
        src = row.candidates / f"seed-{row.seed}.png"
        for n, step in enumerate(steps, 1):
            seed, text = m.groups() if (m := re.fullmatch(r"\[(\d+)\] (.+)", step)) else ("1", step)
            out = row.candidates / ("edit.png" if n == len(steps) else f"edit-{n}.png")
            start = time.monotonic()
            code = mlxgen(["--model", str(EDITOR), "--prompt", text + EDIT_SUFFIX, "--steps", "6", "--seed", seed,
                           "--width", "1024", "--height", "1024", "--image-path", str(src), "--output", str(out)],
                          row.candidates / f"edit-{n}.log")
            print(f"{row.page}: edit {n}/{len(steps)} exit {code} in {time.monotonic() - start:.0f}s", flush=True)
            if code != 0:
                failed += 1
                break
            src = out
    return 1 if failed else 0


def pick(rows: list[Row]) -> int:
    unpicked = [row.page for row in rows if row.seed is None]
    if unpicked:
        print(f"no seed picked for: {' '.join(unpicked)}", file=sys.stderr)
        return 1
    for row in rows:
        src = row.candidates / ("edit.png" if row.edit else f"seed-{row.seed}.png")
        dst = SOURCES / row.category / row.page
        dst.mkdir(parents=True, exist_ok=True)
        for old in dst.glob("*.*"):
            old.unlink()
        Image.open(src).convert("L").save(dst / f"{row.page[3:]}.png", optimize=True)
    print(f"{len(rows)} pages picked → {SOURCES.relative_to(ROOT)}; now `make pages`")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["generate", "review", "edit", "pick"])
    parser.add_argument("--only", nargs="*", help="page IDs (default: all)")
    args = parser.parse_args()
    styles, rows = read_sources()
    if args.only:
        rows = [row for row in rows if row.page in args.only]
    if args.command == "generate":
        return generate(styles, rows)
    if args.command == "review":
        return review(rows)
    if args.command == "edit":
        return edit(rows)
    return pick(rows)


if __name__ == "__main__":
    sys.exit(main())
