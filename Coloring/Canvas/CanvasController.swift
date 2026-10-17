import Photos
import SwiftUI
import UIKit
import os

/// One open page: tool state for the toolbars, input → renderer, undo, autosave.
@MainActor
final class CanvasController: ObservableObject {
    let page: Page

    /// The pop-overs on the canvas. One at a time, and while one is open a touch on the
    /// canvas only closes it.
    enum Panel {
        case stamps, color, size
    }

    enum PhotoSave {
        case ready, saving, saved, denied
    }

    /// None until the child picks one: the canvas ignores touches until then.
    @Published private(set) var tool: Tool?
    /// The side column is out. Put away until a tool is picked.
    @Published private(set) var sideColumnOpen = false
    /// A palette slot, or nil for the child's own color.
    @Published var colorIndex: Int? = 0
    @Published var customColor = CustomColor()
    /// A preset, or nil for the child's own size.
    @Published var size: BrushSize? = .medium
    /// The size slider, 0...1.
    @Published var customSize: Float = 0.5
    @Published var stamp: Stamp = Stamps.available[0]
    @Published var panel: Panel?
    @Published private(set) var canUndo = false
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var photoSave = PhotoSave.ready

    let view: CanvasView
    /// Called with every fresh thumbnail, so the home screen shows the work immediately
    /// rather than after the PNG finishes encoding.
    var onThumbnail: ((String, UIImage) -> Void)?

    private let store: ArtworkStore
    private var renderer: CanvasRenderer?
    private var regions: RegionMap?
    private var fills: [UInt8: RGBA] = [:]
    private var undo = UndoStack()
    private var stroke: StrokeBuilder?
    private var strokeSeed: UInt64 = 0
    private var isDirty = false
    private var saveTask: Task<Void, Never>?

    static let thumbnailPixels = 512
    // Page opens appear under Points of Interest in Instruments, against the spec's
    // 500 ms budget; strokes (named by tool) and fills too, so a dropped frame in a
    // device trace can be pinned to the brush that caused it.
    private static let signposter = OSSignposter(subsystem: "com.zeyanlin.littlestarcoloring", category: .pointsOfInterest)
    private var strokeInterval: OSSignpostIntervalState?

    var color: RGBA { colorIndex.map { Palette.colors[$0] } ?? customColor.rgba }

    /// Dab size for the current tool, in canvas pixels.
    var strokeSize: Float {
        let line = size?.canvasPixels ?? BrushSize.canvasPixels(custom: customSize)
        switch tool {
        case .brush(let kind)?: return line * BrushStyle.brush(kind).scale
        case .eraser?: return line * BrushStyle.eraser.scale
        case .stamp?: return size?.stampPixels ?? BrushSize.stampPixels(custom: customSize)
        case .bucket?, nil: return line
        }
    }

    init(page: Page, store: ArtworkStore) {
        self.page = page
        self.store = store
        view = CanvasView(device: RenderContext.shared.device)
        view.onDraw = { [weak self] layer in self?.renderer?.draw(in: layer) }
        view.onBegan = { [weak self] in self?.began($0) }
        view.onMoved = { [weak self] in self?.moved($0) }
        view.onEnded = { [weak self] in self?.ended() }
    }

    func toggle(_ panel: Panel) {
        self.panel = self.panel == panel ? nil : panel
    }

    /// Any tool brings the side column out, the eraser and rainbow pen too: they have no
    /// color to pick, but they have sizes, and ↶.
    func select(_ tool: Tool) {
        self.tool = tool
        sideColumnOpen = true
    }

    func toggleSideColumn() {
        sideColumnOpen.toggle()
        // The custom color and size panels are opened from the side column.
        if !sideColumnOpen, panel == .color || panel == .size { panel = nil }
    }

    /// First tap picks the child's own color and shows its sliders; later taps show/hide them.
    func chooseCustomColor() {
        if colorIndex == nil {
            toggle(.color)
        } else {
            colorIndex = nil
            panel = .color
        }
    }

    func chooseCustomSize() {
        if size == nil {
            toggle(.size)
        } else {
            size = nil
            panel = .size
        }
    }

    func load() async {
        guard renderer == nil else { return }
        let page = self.page
        let interval = Self.signposter.beginInterval("open page", "\(page.id, privacy: .public)")
        defer { Self.signposter.endInterval("open page", interval) }
        do {
            var step = Self.signposter.beginInterval("open: artwork")
            let artwork = try await store.load(page.id)
            Self.signposter.endInterval("open: artwork", step)
            step = Self.signposter.beginInterval("open: page")
            let assets = try await Task.detached(priority: .userInitiated) {
                try PageAssets.load(page, artwork: artwork)
            }.value
            Self.signposter.endInterval("open: page", step)
            regions = assets.regions
            fills = assets.artwork.fills
            step = Self.signposter.beginInterval("open: upload")
            renderer = CanvasRenderer(assets: assets)
            Self.signposter.endInterval("open: upload", step)
            isLoaded = true
            view.setNeedsRedraw()
        } catch {
            // A page that fails to load is a build defect (bad pipeline output); say so
            // instead of showing an empty canvas a child would scribble on and lose.
            loadError = "\(error)"
            assertionFailure("page \(page.id) failed to load: \(error)")
        }
    }

    // MARK: - Input

    private func began(_ sample: CanvasView.Sample) {
        guard let renderer, let regions else { return }
        // A tap beside an open panel means "close it", not "paint here".
        if panel != nil {
            panel = nil
            return
        }
        guard let tool else { return }
        switch tool {
        case .bucket:
            fill(region: regions.region(at: sample.point))
        case .brush(let kind):
            let style = BrushStyle.brush(kind, paintRunsOut: UserDefaults.standard.bool(forKey: BrushStyle.paintRunsOutKey))
            startStroke(style, tip: RenderContext.shared.tip(for: style), size: strokeSize, sample: sample,
                        renderer: renderer)
        case .eraser:
            let style = BrushStyle.eraser
            startStroke(style, tip: RenderContext.shared.tip(for: style), size: strokeSize, sample: sample,
                        renderer: renderer)
        case .stamp:
            startStroke(.stamp, tip: RenderContext.shared.stampTip(stamp), size: strokeSize, sample: sample,
                        renderer: renderer)
        }
    }

    private func startStroke(_ style: BrushStyle, tip: RenderContext.StrokeTip, size: Float,
                             sample: CanvasView.Sample, renderer: CanvasRenderer) {
        strokeSeed &+= 1
        strokeInterval = Self.signposter.beginInterval("stroke", "\(self.tool.map { String(describing: $0) } ?? "", privacy: .public)")
        var builder = StrokeBuilder(style: style, baseSize: size, aspect: tip.aspect, seed: strokeSeed)
        renderer.beginStroke(style: style, tip: tip, color: color)
        renderer.draw(builder.begin(at: sample.point, time: sample.time))
        stroke = builder
        view.setNeedsRedraw()
    }

    private func moved(_ samples: [CanvasView.Sample]) {
        guard var builder = stroke, let renderer else { return }
        let interval = Self.signposter.beginInterval("touch")
        defer { Self.signposter.endInterval("touch", interval) }
        var dabs: [Dab] = []
        for sample in samples {
            dabs += builder.move(to: sample.point, time: sample.time)
        }
        stroke = builder
        renderer.draw(dabs)
        view.setNeedsRedraw()
    }

    private func ended() {
        guard var builder = stroke, let renderer else { return }
        stroke = nil
        renderer.draw(builder.end())
        if let edit = renderer.endStroke() {
            record(edit)
        }
        view.setNeedsRedraw()
        if let strokeInterval { Self.signposter.endInterval("stroke", strokeInterval) }
        strokeInterval = nil
    }

    private func fill(region: UInt8) {
        guard region != 0, let renderer else { return }
        let old = fills[region] ?? .white
        let new = color
        guard old != new else { return }
        Self.signposter.emitEvent("fill")
        apply(fill: new, region: region, renderer: renderer)
        record(.fill(region: region, old: old, new: new))
        view.setNeedsRedraw()
    }

    private func apply(fill color: RGBA, region: UInt8, renderer: CanvasRenderer) {
        fills[region] = color == .white ? nil : color
        renderer.setFill(color, region: region)
    }

    // MARK: - Undo

    private func record(_ edit: CanvasEdit) {
        undo.push(edit)
        canUndo = true
        markDirty()
    }

    func undoLast() {
        guard stroke == nil, let renderer, let edit = undo.pop() else { return }
        switch edit {
        case .fill(let region, let old, _):
            apply(fill: old, region: region, renderer: renderer)
        case .raster(let rect, let before):
            for (layer, bytes) in before {
                renderer.restore(rect, layer, from: bytes)
            }
        case .clear(let fills, let before):
            let whole = PixelRect(x: 0, y: 0, width: CanvasSpec.size, height: CanvasSpec.size)
            for (layer, bytes) in before {
                renderer.restore(whole, layer, from: bytes)
            }
            for (region, color) in fills {
                apply(fill: color, region: region, renderer: renderer)
            }
        }
        canUndo = !undo.isEmpty
        markDirty()
        view.setNeedsRedraw()
    }

    /// Back to the bare page — one undoable step, so a mistaken "yes" costs nothing.
    func clearAll() {
        guard stroke == nil, let renderer else { return }
        let edit = CanvasEdit.clear(fills: fills, before: renderer.clearLayers())
        for region in fills.keys {
            apply(fill: .white, region: region, renderer: renderer)
        }
        record(edit)
        view.setNeedsRedraw()
    }

    // MARK: - Saving

    private func markDirty() {
        isDirty = true
        // Something new to keep: the photo button comes back.
        photoSave = .ready
        saveTask?.cancel()
        // Debounced: a child mid-scribble triggers dozens of edits a minute, and each
        // save reads back 16 MB from the GPU.
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    func save() async {
        guard isDirty, let renderer else { return }
        isDirty = false
        let layer = renderer.bytes(of: .paint)
        let stamps = renderer.bytes(of: .stamps)
        let thumbnail = renderer.snapshot(pixels: Self.thumbnailPixels)
        if let image = Bitmap.cgImage(premultiplied: thumbnail, width: Self.thumbnailPixels,
                                      height: Self.thumbnailPixels, layout: .bgra) {
            onThumbnail?(page.id, UIImage(cgImage: image))
        }
        do {
            try await store.save(page.id, fills: fills, layer: layer, stamps: stamps, thumbnail: thumbnail,
                                 thumbnailSize: Self.thumbnailPixels)
        } catch {
            isDirty = true
            assertionFailure("save failed for \(page.id): \(error)")
        }
    }

    /// Leaving the page: flush any pending save.
    func close() async {
        saveTask?.cancel()
        if stroke != nil { ended() }
        await save()
    }

    // MARK: - Photos

    /// The page as the child sees it, full size, into the photo library. Add-only access:
    /// the app can put pictures in but never sees the family's photos.
    func saveToPhotos() async {
        guard photoSave == .ready || photoSave == .denied, let renderer else { return }
        photoSave = .saving
        let pixels = CanvasSpec.size
        let snapshot = renderer.snapshot(pixels: pixels)
        let png = await Task.detached(priority: .userInitiated) {
            Bitmap.cgImage(premultiplied: snapshot, width: pixels, height: pixels, layout: .bgra)
                .flatMap { try? Bitmap.png($0) }
        }.value
        guard let png else {
            photoSave = .ready
            assertionFailure("could not encode \(page.id) for Photos")
            return
        }
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else {
            photoSave = .denied
            return
        }
        do {
            try await Self.addToPhotos(png)
            // An edit made while saving already put the button back to .ready; keep that.
            if photoSave == .saving { photoSave = .saved }
        } catch {
            photoSave = .ready
            assertionFailure("Photos refused \(page.id): \(error)")
        }
    }

    /// Photos runs the change block on its own queue. Written inside the @MainActor class,
    /// the closure would be main-actor isolated and Swift 6 traps when Photos calls it.
    private nonisolated static func addToPhotos(_ png: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
        }
    }
}
