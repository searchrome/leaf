import XCTest
import AppKit
@testable import ReaderCore

final class PaginationTests: XCTestCase {
    func testPagesCoverEveryCharacterExactlyOnceAtDifferentSizes() {
        let text = String(repeating: "A café 👩🏽‍🚀 beside the sea. Curly ‘quotes’, naïve ideas, and a very long afternoon.\n\n", count: 60)
        for size in [CGSize(width: 240, height: 200), CGSize(width: 580, height: 600)] {
            let pages = Pagination.pages(for: text, fontSize: 21, size: size)
            XCTAssertGreaterThan(pages.count, 1)
            var next = 0
            var reconstructed = ""
            for page in pages {
                XCTAssertEqual(page.location, next)
                XCTAssertGreaterThan(page.length, 0)
                reconstructed += (text as NSString).substring(with: page)
                next = NSMaxRange(page)
            }
            XCTAssertEqual(next, text.utf16.count)
            XCTAssertEqual(reconstructed, text)
        }
    }

    func testReflowKeepsTheSpokenWordOnItsNewPage() {
        let text = String(repeating: "This is a sentence that will move as the page changes. ", count: 70)
        let anchor = (text as NSString).range(of: "move", options: [], range: NSRange(location: 1000, length: 500)).location
        for font in [CGFloat(17), CGFloat(30)] {
            let pages = Pagination.pages(for: text, fontSize: font, size: CGSize(width: 400, height: 400))
            let index = ReadingSession.page(containing: anchor, in: pages)
            XCTAssertTrue(NSLocationInRange(anchor, pages[index]))
        }
    }
}
