# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Fetch the emoji stamp pictures into the app bundle.

  Coloring/Resources/Stamps/<code points>.png   Microsoft Fluent Emoji 3D, 256² RGBA
  Coloring/Resources/Stamps/LICENSE             its MIT license, shipped with the app

Pictures, not the system's Apple emoji: Apple emoji may not be embedded in an app or
used in sticker content (App Review Guidelines 4.5.6, 5.2.5), and a stamp is a sticker
that gets drawn into saved artwork and exported to Photos.

The emoji list is read from Coloring/Model/Stamps.swift, its one source of truth. A
file is named by the emoji's code points in hex, VS16 (FE0F) dropped, joined by "-":
the name `Stamp.pictureURL` looks up. Every picture is SIZE² (the app draws them into a
square): the odd one upstream (🪐 is 256×264) is fitted onto a transparent square. The
commit is pinned so a rerun fetches the same
pictures; bump FLUENT_COMMIT to take new artwork.

Usage: uv run tools/fetch_stamps.py
"""

from __future__ import annotations

import io
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
STAMPS_SWIFT = ROOT / "Coloring" / "Model" / "Stamps.swift"
OUT = ROOT / "Coloring" / "Resources" / "Stamps"
FLUENT_REPO = "https://github.com/microsoft/fluentui-emoji.git"
FLUENT_COMMIT = "1ffb34c752ecf5d402f04cfb4b392c77f57c54bc"
RAW = f"https://raw.githubusercontent.com/microsoft/fluentui-emoji/{FLUENT_COMMIT}/"
SIZE = 256


def stamp_emoji() -> list[str]:
    source = STAMPS_SWIFT.read_text(encoding="utf-8")
    block = source[source.index("static let emoji") : source.index("static let kaomoji")]
    return re.findall(r'"([^"]+)"', block)


def file_name(emoji: str) -> str:
    return "-".join(f"{ord(c):x}" for c in emoji if ord(c) != 0xFE0F)


def git(*args: str, cwd: Path) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def fluent_pictures(work: Path) -> dict[str, str]:
    """Code points → repo path of the 3D PNG, at the pinned commit."""
    # Blobless and sparse: of the repo's art, only the small metadata files come down.
    git("clone", "--quiet", "--filter=blob:none", "--no-checkout", FLUENT_REPO, str(work), cwd=work.parent)
    git("sparse-checkout", "set", "--no-cone", "/assets/*/metadata.json", cwd=work)
    git("checkout", "--quiet", FLUENT_COMMIT, cwd=work)
    # -z: otherwise git quotes the folder names with curly apostrophes and the like.
    listing = git("ls-tree", "-r", "-z", "--name-only", FLUENT_COMMIT, "assets", cwd=work).split("\0")
    pngs = sorted(p for p in listing if "/3D/" in p and p.endswith(".png"))
    pictures = {}
    for meta in (work / "assets").glob("*/metadata.json"):
        unicode = json.loads(meta.read_text(encoding="utf-8"))["unicode"]
        mine = [p for p in pngs if p.startswith(f"assets/{meta.parent.name}/")]
        # People come in skin tones; Default is the yellow one.
        default = [p for p in mine if "/Default/3D/" in p]
        if mine:
            pictures["-".join(c for c in unicode.split() if c != "fe0f")] = (default or mine)[0]
    return pictures


def fetch(path: str) -> bytes:
    with urllib.request.urlopen(RAW + urllib.parse.quote(path), timeout=60) as response:
        return response.read()


def squared(png: bytes) -> bytes:
    image = Image.open(io.BytesIO(png))
    if image.size == (SIZE, SIZE):
        return png
    image = image.convert("RGBA")
    image.thumbnail((SIZE, SIZE), Image.LANCZOS)
    square = Image.new("RGBA", (SIZE, SIZE))
    square.paste(image, ((SIZE - image.width) // 2, (SIZE - image.height) // 2))
    out = io.BytesIO()
    square.save(out, "PNG")
    return out.getvalue()


def main() -> int:
    emoji = stamp_emoji()
    with tempfile.TemporaryDirectory() as tmp:
        pictures = fluent_pictures(Path(tmp) / "fluent")
    missing = [e for e in emoji if file_name(e) not in pictures]
    if missing:
        print(f"no Fluent picture for: {' '.join(missing)}", file=sys.stderr)
        return 1
    with ThreadPoolExecutor(8) as pool:
        data = [squared(png) for png in pool.map(lambda e: fetch(pictures[file_name(e)]), emoji)]
    wrong = [e for e, png in zip(emoji, data)
             if png[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", png[16:24]) != (SIZE, SIZE)]
    if wrong:
        print(f"not a {SIZE}² PNG: {' '.join(wrong)}", file=sys.stderr)
        return 1
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    for e, png in zip(emoji, data):
        (OUT / f"{file_name(e)}.png").write_bytes(png)
    (OUT / "LICENSE").write_bytes(fetch("LICENSE"))
    print(f"{len(emoji)} stamps → {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
