import CoreImage
import SwiftUI
import UIKit

@MainActor
final class AppModel: ObservableObject {
    let categories: [PageCategory]
    /// Each category's first page, blank: the picture on its home card.
    let covers: [String: UIImage]
    /// The covers blurred, for cards away from the middle of home. Blurred once here: a
    /// blur whose radius followed the scroll would redo every card's blur every frame,
    /// and home faded between the two costs only compositing.
    @Published private(set) var blurredCovers: [String: UIImage] = [:]
    @Published private(set) var category: PageCategory?
    /// The open category's pages as drawn so far. Only that category's: a decoded 512²
    /// thumbnail is 1 MB, and 120 of them would eat half the memory budget.
    @Published private(set) var thumbnails: [String: UIImage] = [:]
    @Published private(set) var canvas: CanvasController?

    private let store: ArtworkStore

    init(store: ArtworkStore, categories: [PageCategory] = PageCategory.bundled()) {
        self.store = store
        self.categories = categories
        // Decoded now: home shows all of them on its first frame anyway, and a lazily
        // decoded cover would decode again on the main thread mid-transition.
        covers = Dictionary(uniqueKeysWithValues: categories.compactMap { category in
            category.pages.first.flatMap { UIImage(contentsOfFile: $0.thumbnailURL.path)?.preparingForDisplay() }
                .map { (category.id, $0) }
        })
        // Ready long before a child gets to the stamp picker; were it first touched on
        // the main thread, opening a page would wait for all 212.
        Task.detached(priority: .utility) { _ = Stamps.thumbnails }
        // Off the main thread, so launch doesn't wait; until it lands, home is all sharp.
        Task { [covers] in
            blurredCovers = await Task.detached(priority: .userInitiated) { Self.blurred(covers) }.value
        }
    }

    private nonisolated static func blurred(_ covers: [String: UIImage]) -> [String: UIImage] {
        let context = CIContext()
        return covers.compactMapValues { cover in
            guard let image = CIImage(image: cover) else { return nil }
            // At a quarter size: a sixteenth of the work, and the result is soft anyway.
            let small = image.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
            let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: small.extent)
            return context.createCGImage(blurred, from: small.extent).map(UIImage.init(cgImage:))
        }
    }

    func show(_ category: PageCategory) {
        thumbnails = [:]
        self.category = category
    }

    func closeCategory() {
        category = nil
        thumbnails = [:]
    }

    /// UI tests start from a blank slate in a throwaway folder, never the real artworks.
    static func storeRoot() -> URL {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ui-artworks", isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            return root
        }
        return ArtworkStore.defaultRoot()
    }

    func loadThumbnails() async {
        for page in category?.pages ?? [] where thumbnails[page.id] == nil {
            thumbnails[page.id] = await thumbnail(for: page)
        }
    }

    private func thumbnail(for page: Page) async -> UIImage? {
        guard let image = await store.thumbnail(page.id).flatMap(UIImage.init(data:))
                ?? UIImage(contentsOfFile: page.thumbnailURL.path)
        else { return nil }
        // Decoded off the main thread. Left lazy, the PNG decodes on the main thread the
        // first time its card draws: mid-transition into the category, or mid-scroll.
        return await image.byPreparingForDisplay() ?? image
    }

    func open(_ page: Page) {
        let controller = CanvasController(page: page, store: store)
        controller.onThumbnail = { [weak self] id, image in self?.thumbnails[id] = image }
        canvas = controller
    }

    /// Returns to the page's category at once; the save finishes behind it.
    func closeCanvas() {
        guard let controller = canvas else { return }
        canvas = nil
        Task { await controller.close() }
    }

    func saveOpenPage() async {
        await canvas?.save()
    }

    func restart(_ page: Page) async {
        do {
            try await store.delete(page.id)
        } catch {
            assertionFailure("restart \(page.id): \(error)")
        }
        thumbnails[page.id] = await thumbnail(for: page)
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            if let canvas = model.canvas {
                CanvasScreen(controller: canvas, placeholder: model.thumbnails[canvas.page.id],
                             onClose: model.closeCanvas)
                    .transition(.opacity)
            } else if let category = model.category {
                CategoryView(model: model, category: category)
                    .transition(.opacity)
            } else {
                HomeView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.canvas?.page.id)
        .animation(.easeInOut(duration: 0.2), value: model.category?.id)
    }
}
