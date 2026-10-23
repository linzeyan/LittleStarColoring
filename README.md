# 小星星塗色 · Little Star Coloring

An offline coloring book for children 5 and under, on iPad.

給 5 歲以下孩子的 iPad 著色本：不連網、沒有廣告、沒有內購。

## What it does

- **Tap to fill.** Pick a color and tap a shape with the paint bucket, and the whole shape fills. The black lines always stay on top.
- **Textured brushes,** drawn with Metal: crayon, colored pencil, chalk, marker, watercolor, oil, ink, airbrush, rainbow, glitter, stars and puffy paint. The eraser removes brush strokes and leaves fills alone.
- **Stamps:** picture stamps and kaomoji. Drag a finger to lay down a row.
- **Autosave.** Every page is saved as the child colors, and the category screen shows the saved pages as a gallery. The camera button adds the current picture to Photos.
- **Made for small hands.** The tools are pictures, not words (the only text is each page's name, for the grown-up playing along), the buttons are large, only one finger paints at a time, and a resting palm draws nothing. Undo is one tap away. Clearing a page asks first.
- **Grown-ups' setting.** Press and hold the gear on the home screen for 1 second to open it. Its one switch is "paint runs out": oil, watercolor and ink thin out over a long stroke.

The app runs on iPadOS 15 and later in landscape, because hand-me-down iPads are what small children usually get. It is tested on an iPad mini 4.

## Privacy

The app never goes online. It has no account, no ads, no analytics, no tracking and no third-party SDKs. Artwork stays in the app's own folder on the iPad. Saving to Photos uses add-only access, so the app cannot see the photo library. See [PRIVACY.md](PRIVACY.md).

## Building

Requirements:

- Xcode 27
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- To rebuild the pages, stamps or icon: [uv](https://docs.astral.sh/uv/) and `rsvg-convert` (from librsvg)

`Coloring.xcodeproj` is generated from `project.yml` and isn't committed. Every `make` target that builds runs `make generate` first.

```bash
make run        # build, install and launch on the simulator
make test       # unit tests; brush snapshots are written to build/snapshots
make test-ui    # UI walk-through; screenshots are exported to build/ui-shots
make device     # Release build installed on an iPad over USB (libimobiledevice)
make release    # archive and export an .ipa for App Store Connect
make help       # every target
```

Simulator builds are signed ad hoc, so they don't need an Apple account. To build for a device, set `DEVELOPMENT_TEAM` in `project.yml` to your own team.

The test bundles need iOS 17 (Xcode 27's XCTest), so they run on simulators only. The iPadOS 15 floor is checked by hand on a device.

## Coloring pages

Each page starts as one black-and-white drawing in `LineArt/sources/<category>/<page>/`. `make pages` turns every drawing into three files under `Coloring/Resources/Pages/`:

| File | Contents |
|---|---|
| `lineart.png` | Black lines on transparency, drawn above the paint |
| `regions.png` | 8-bit gray. Each pixel holds the ID of the shape it belongs to |
| `thumb.png` | Thumbnail for the category screen |

Shapes are labeled once, when the pages are built, not by a flood fill on the device. A fill at runtime leaks through any gap in a line and leaves halos at anti-aliased edges. Building the regions ahead of time also writes a debug image to `LineArt/debug/`, so a leak gets caught before the page ships. Because `regions.png` is read byte for byte, the Xcode project turns PNG compression off and bundles the pages as a folder reference.

The built pages are committed, so building the app needs no Python.

All of the line art was made for this app. Every drawing was generated locally with Z-Image-Turbo, and a few were touched up with Qwen-Image-Edit. Both models are Apache 2.0. [LineArt/SOURCES.md](LineArt/SOURCES.md) records the prompt, seed and any edit for every page, and `tools/generate_pages.py` reproduces them. Regenerating needs the MLX models on your machine; `make pages` doesn't.

## Project layout

```
Coloring/           app source (App, Canvas, Model) and bundled resources
  Resources/Pages/  built coloring pages (make pages)
  Resources/Stamps/ stamp pictures and their license (make stamps)
ColoringTests/      unit and brush snapshot tests
ColoringUITests/    UI walk-through
LineArt/            line-art sources and where each one came from
tools/              page, stamp and icon pipelines (Python, run with uv)
project.yml         XcodeGen spec for Coloring.xcodeproj
```

## Credits

- The picture stamps are [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji) (3D style), MIT licensed. The license text ships with the app in [Coloring/Resources/Stamps/LICENSE](Coloring/Resources/Stamps/LICENSE). The app draws no Apple emoji.

## Support

Questions and bug reports go to [Issues](https://github.com/linzeyan/LittleStarColoring/issues).
