import Foundation

struct PixelRect: Hashable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var isEmpty: Bool { width <= 0 || height <= 0 }

    func union(_ other: PixelRect) -> PixelRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let minX = min(x, other.x), minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width), maxY = max(y + height, other.y + other.height)
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func clamped(to size: Int) -> PixelRect {
        let minX = max(x, 0), minY = max(y, 0)
        let maxX = min(x + width, size), maxY = min(y + height, size)
        return PixelRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    static let empty = PixelRect(x: 0, y: 0, width: 0, height: 0)
}

/// The two raster layers a child can draw on: brush paint under the line art, stamps over it.
enum CanvasLayer: CaseIterable, Sendable {
    case paint, stamps
}

enum CanvasEdit: Sendable {
    case fill(region: UInt8, old: RGBA, new: RGBA)
    /// Each touched layer's pixels under `rect` from before the edit (premultiplied RGBA8).
    case raster(rect: PixelRect, before: [CanvasLayer: Data])
    /// The whole page from before "clear": every fill and both layers in full.
    case clear(fills: [UInt8: RGBA], before: [CanvasLayer: Data])

    var byteCost: Int {
        switch self {
        case .fill: 0
        case .raster(_, let before), .clear(_, let before): before.values.reduce(0) { $0 + $1.count }
        }
    }
}

/// Undo only — no redo, which a child under five has no model for. Bounded by bytes as
/// well as count, because one full-canvas stroke costs 16 MB on a 2 GB iPad.
struct UndoStack {
    let maxCount: Int
    let maxBytes: Int
    private(set) var edits: [CanvasEdit] = []
    private(set) var bytes = 0

    init(maxCount: Int = 40, maxBytes: Int = 64 << 20) {
        self.maxCount = maxCount
        self.maxBytes = maxBytes
    }

    var isEmpty: Bool { edits.isEmpty }

    mutating func push(_ edit: CanvasEdit) {
        edits.append(edit)
        bytes += edit.byteCost
        // Keep the newest edit even when it alone is over budget: "undo" must always
        // take back what the child just did.
        while edits.count > 1 && (edits.count > maxCount || bytes > maxBytes) {
            bytes -= edits.removeFirst().byteCost
        }
    }

    mutating func pop() -> CanvasEdit? {
        guard let edit = edits.popLast() else { return nil }
        bytes -= edit.byteCost
        return edit
    }
}
