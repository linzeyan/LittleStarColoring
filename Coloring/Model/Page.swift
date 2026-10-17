import Foundation

/// One coloring page as built by tools/build_pages.py into the bundle's Pages folder.
struct Page: Identifiable, Hashable, Sendable {
    /// The folder name, e.g. "02-rocket": unique across categories, and the key its
    /// artwork is saved under. Its sort order is the order within a category.
    let id: String
    let directory: URL

    var lineArtURL: URL { directory.appendingPathComponent("lineart.png") }
    var regionsURL: URL { directory.appendingPathComponent("regions.png") }
    var thumbnailURL: URL { directory.appendingPathComponent("thumb.png") }

    static func bundled(in bundle: Bundle = .main) -> [Page] {
        PageCategory.bundled(in: bundle).flatMap(\.pages)
    }
}

/// A folder of pages under Pages, e.g. "01-vehicles"; its sort order is the home order.
struct PageCategory: Identifiable, Hashable, Sendable {
    let id: String
    let pages: [Page]

    /// For grown-ups, under the card: children go by the picture.
    var name: String { Self.names[String(id.drop { $0 != "-" }.dropFirst())] ?? id }

    static let names = [
        "vehicles": "交通工具", "farm": "農場動物", "wild": "野生動物", "sea": "海洋動物",
        "birds": "鳥類", "bugs": "昆蟲", "dinosaurs": "恐龍", "plants": "花草植物",
        "fruit": "水果", "vegetables": "蔬菜", "food": "點心食物", "buildings": "建築物", "sky": "天空天氣",
        "fantasy": "幻想生物", "zodiac": "十二生肖", "constellations": "十二星座",
    ]

    static func bundled(in bundle: Bundle = .main) -> [PageCategory] {
        guard let root = bundle.url(forResource: "Pages", withExtension: nil) else {
            assertionFailure("Pages folder missing from the bundle — run `make pages`")
            return []
        }
        return subfolders(of: root).map { folder in
            PageCategory(id: folder.lastPathComponent,
                         pages: subfolders(of: folder).map { Page(id: $0.lastPathComponent, directory: $0) })
        }
    }

    private static func subfolders(of url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

enum CanvasSpec {
    /// Square, in pixels, for every page: line art, region map and paint layer alike.
    static let size = 2048
}
