import Foundation

/// What a child has done to one page.
struct Artwork: Sendable {
    /// Region ID → fill color. Absent means paper white.
    var fills: [UInt8: RGBA] = [:]
    /// The paint layer, premultiplied RGBA8, CanvasSpec.size² — nil when never painted.
    var layer: [UInt8]?
    /// The stamp layer, same format — nil when never stamped.
    var stamps: [UInt8]?
}

/// One folder per page under Application Support. An actor so a save still encoding
/// when its page is reopened finishes before the reopen reads the files.
actor ArtworkStore {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Artworks", isDirectory: true)
    }

    private func folder(_ pageID: String) -> URL { root.appendingPathComponent(pageID, isDirectory: true) }
    private func fillsURL(_ pageID: String) -> URL { folder(pageID).appendingPathComponent("fill.json") }
    private func layerURL(_ pageID: String) -> URL { folder(pageID).appendingPathComponent("strokes.png") }
    private func stampsURL(_ pageID: String) -> URL { folder(pageID).appendingPathComponent("stamps.png") }
    private func thumbnailURL(_ pageID: String) -> URL { folder(pageID).appendingPathComponent("thumb.png") }

    func load(_ pageID: String) throws -> Artwork {
        var artwork = Artwork()
        if let data = try? Data(contentsOf: fillsURL(pageID)) {
            let saved = try JSONDecoder().decode(SavedFills.self, from: data)
            for (key, hex) in saved.regionColors {
                guard let region = UInt8(key), let color = RGBA(hex: hex) else { continue }
                artwork.fills[region] = color
            }
        }
        artwork.layer = try canvasBytes(at: layerURL(pageID))
        artwork.stamps = try canvasBytes(at: stampsURL(pageID))
        return artwork
    }

    private func canvasBytes(at url: URL) throws -> [UInt8]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return Bitmap.rgbaBytes(of: try Bitmap.image(at: url), size: CanvasSpec.size)
    }

    /// `layer` and `stamps` are premultiplied RGBA8; `thumbnail` is premultiplied BGRA8,
    /// `thumbnailSize`².
    func save(_ pageID: String, fills: [UInt8: RGBA], layer: Data, stamps: Data, thumbnail: Data,
              thumbnailSize: Int) throws {
        try FileManager.default.createDirectory(at: folder(pageID), withIntermediateDirectories: true)
        let saved = SavedFills(regionColors: Dictionary(uniqueKeysWithValues: fills.map { (String($0.key), $0.value.hex) }))
        try JSONEncoder().encode(saved).write(to: fillsURL(pageID), options: .atomic)
        let size = CanvasSpec.size
        guard let layerImage = Bitmap.cgImage(premultiplied: layer, width: size, height: size, layout: .rgba),
              let stampsImage = Bitmap.cgImage(premultiplied: stamps, width: size, height: size, layout: .rgba),
              let thumbImage = Bitmap.cgImage(
                premultiplied: thumbnail, width: thumbnailSize, height: thumbnailSize, layout: .bgra)
        else { throw Bitmap.Failure.encodeFailed }
        try Bitmap.png(layerImage).write(to: layerURL(pageID), options: .atomic)
        try Bitmap.png(stampsImage).write(to: stampsURL(pageID), options: .atomic)
        try Bitmap.png(thumbImage).write(to: thumbnailURL(pageID), options: .atomic)
    }

    func thumbnail(_ pageID: String) -> Data? {
        try? Data(contentsOf: thumbnailURL(pageID))
    }

    func delete(_ pageID: String) throws {
        let url = folder(pageID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private struct SavedFills: Codable {
        var regionColors: [String: String]
    }
}
