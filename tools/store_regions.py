# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "pillow"]
# ///
# For each page: every region's ID, area and the point deepest inside it (normalized),
# plus a labeled preview to assign colors by eye, for ColoringUITests/StoreScreenshots.swift.
# Usage: uv run tools/store_regions.py 02-farm/01-cow ... → build/store/regions.json, <page>.png
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
root, out = Path("Coloring/Resources/Pages"), Path("build/store")
out.mkdir(parents=True, exist_ok=True)
data = {}
for spec in sys.argv[1:]:
    page = root / spec
    labels = np.asarray(Image.open(page / "regions.png"))
    alpha = np.asarray(Image.open(page / "lineart.png").convert("RGBA"))[..., 3]
    n = labels.shape[0]
    regions = []
    for rid in range(1, int(labels.max()) + 1):
        mask = (labels == rid) & (alpha < 128)
        if not mask.any():
            continue
        dist = ndimage.distance_transform_edt(np.pad(mask, 1))[1:-1, 1:-1]
        y, x = np.unravel_index(np.argmax(dist), dist.shape)
        regions.append([rid, int(mask.sum()), round(x / n, 4), round(y / n, 4)])
    data[page.name] = regions
    rng = np.random.default_rng(1)
    pal = np.vstack([[255, 255, 255], rng.integers(150, 256, (256, 3))]).astype(np.uint8)
    img = pal[labels].copy()
    img[alpha >= 128] = 0
    im = Image.fromarray(img).resize((1024, 1024))
    d = ImageDraw.Draw(im); font = ImageFont.load_default(size=36)
    for rid, area, x, y in regions:
        d.text((x * 1024 - 10, y * 1024 - 16), str(rid), fill=(220, 0, 0), font=font)
    im.save(out / f"{page.name}.png")
(out / "regions.json").write_text(json.dumps(data, indent=0))
for k, v in data.items():
    print(k, len(v), "regions")
