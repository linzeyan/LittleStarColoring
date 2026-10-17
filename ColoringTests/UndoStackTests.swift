import XCTest
@testable import Coloring

final class UndoStackTests: XCTestCase {
    private func raster(_ bytes: Int) -> CanvasEdit {
        .raster(rect: PixelRect(x: 0, y: 0, width: 1, height: 1), before: [.paint: Data(count: bytes)])
    }

    /// The eraser touches both layers; both copies count against the budget.
    func testCostCountsEveryLayer() {
        let edit = CanvasEdit.raster(rect: PixelRect(x: 0, y: 0, width: 1, height: 1),
                                     before: [.paint: Data(count: 30), .stamps: Data(count: 12)])
        XCTAssertEqual(edit.byteCost, 42)
        XCTAssertEqual(CanvasEdit.clear(fills: [1: .white], before: [.paint: Data(count: 7)]).byteCost, 7)
    }

    func testPopsNewestFirst() {
        var stack = UndoStack()
        stack.push(.fill(region: 1, old: .white, new: Palette.colors[0]))
        stack.push(.fill(region: 2, old: .white, new: Palette.colors[1]))
        guard case .fill(let region, _, _) = stack.pop() else { return XCTFail() }
        XCTAssertEqual(region, 2)
    }

    /// A 2 GB iPad can't hold forty full-canvas snapshots; the oldest go first.
    func testByteBudgetEvictsOldestEdits() {
        var stack = UndoStack(maxCount: 100, maxBytes: 100)
        for _ in 0..<5 { stack.push(raster(30)) }
        XCTAssertEqual(stack.edits.count, 3)
        XCTAssertEqual(stack.bytes, 90)
    }

    /// Whatever it costs, the child's last action must be undoable.
    func testNewestEditSurvivesEvenWhenOverBudget() {
        var stack = UndoStack(maxCount: 100, maxBytes: 10)
        stack.push(raster(5))
        stack.push(raster(500))
        XCTAssertEqual(stack.edits.count, 1)
        XCTAssertEqual(stack.bytes, 500)
        XCTAssertNotNil(stack.pop())
        XCTAssertTrue(stack.isEmpty)
        XCTAssertEqual(stack.bytes, 0)
    }

    func testCountLimit() {
        var stack = UndoStack(maxCount: 3, maxBytes: .max)
        for i in 0..<10 { stack.push(.fill(region: UInt8(i), old: .white, new: .white)) }
        XCTAssertEqual(stack.edits.count, 3)
    }
}
