import AppKit
import XCTest
import ReaderCore
@testable import Leaf

final class BookmarkInteractionTests: XCTestCase {
    @MainActor
    func testMouseDownOnEveryBookmarkedLetterSelectsPassageWithoutSeeking() throws {
        let view = PageText.SeekTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        view.textContainerInset = .zero
        view.textStorage?.setAttributedString(Pagination.attributed("Before saved passage after.", fontSize: 21))
        let range = (view.string as NSString).range(of: "saved passage")
        view.bookmarkRanges = [range]
        var hits: [Int] = []
        view.onBookmarkHit = { hits.append($0); return true }
        view.onSeek = { _ in XCTFail("Bookmark clicks must not start narration") }
        let layout = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layout.ensureLayout(for: container)
        for index in range.location..<NSMaxRange(range) {
            let glyph = layout.glyphIndexForCharacter(at: index)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let point = NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            view.mouseDown(with: event)
            XCTAssertEqual(view.selectedRange(), range)
            XCTAssertEqual(hits.last, index)
        }
        XCTAssertEqual(hits.count, range.length)
        XCTAssertNil(view.characterAtPoint(NSPoint(x: 550, y: 150)))
    }
}
