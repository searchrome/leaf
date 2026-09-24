import XCTest
@testable import ReaderCore

final class ReadingSessionTests: XCTestCase {
    func testMapsUnicodeWordFromMidChapterToVisiblePage() {
        let text = "Intro 👩🏽‍🚀. Café, naïve — welcome."
        let ns = text as NSString
        let start = ns.range(of: "Café").location
        var session = ReadingSession()
        let token = session.begin(chapter: 2, offset: start, textLength: ns.length)
        let relative = (ns.substring(from: start) as NSString).range(of: "naïve")
        let word = session.word(relative, generation: token)
        XCTAssertEqual(word, ns.range(of: "naïve"))
        XCTAssertEqual(session.chapter, 2)
        let split = ns.range(of: "naïve").location
        XCTAssertEqual(ReadingSession.page(containing: word!.location, in: [NSRange(location: 0, length: split), NSRange(location: split, length: ns.length - split)]), 1)
    }

    func testPauseRejectsQueuedWordAndCompletionThenResumes() {
        var session = ReadingSession()
        let token = session.begin(chapter: 0, offset: 0, textLength: 40)
        session.pause()
        XCTAssertNil(session.word(NSRange(location: 4, length: 3), generation: token))
        XCTAssertFalse(session.finish(generation: token))
        session.resume()
        XCTAssertEqual(session.word(NSRange(location: 4, length: 3), generation: token), NSRange(location: 4, length: 3))
        XCTAssertTrue(session.finish(generation: token))
        XCTAssertFalse(session.finish(generation: token), "Completion may advance the book only once")
    }

    func testOldUtteranceCannotHighlightOrAdvanceAfterNavigation() {
        var session = ReadingSession()
        let old = session.begin(chapter: 0, offset: 0, textLength: 100)
        session.cancel()
        let current = session.begin(chapter: 1, offset: 30, textLength: 90)
        XCTAssertNil(session.word(NSRange(location: 0, length: 5), generation: old))
        XCTAssertFalse(session.finish(generation: old))
        XCTAssertEqual(session.word(NSRange(location: 0, length: 5), generation: current)?.location, 30)
    }

    func testRejectsOutOfBoundsRangesWithoutOverflow() {
        var session = ReadingSession()
        let token = session.begin(chapter: 0, offset: 10, textLength: 30)
        for range in [NSRange(location: NSNotFound, length: 5), NSRange(location: 18, length: 4), NSRange(location: 0, length: 0), NSRange(location: 1, length: Int.max)] {
            XCTAssertNil(session.word(range, generation: token))
        }
    }

    func testDelayedWordCannotMoveTheReaderBackward() {
        var session = ReadingSession()
        let token = session.begin(chapter: 0, offset: 100, textLength: 200)
        XCTAssertNotNil(session.word(NSRange(location: 30, length: 5), generation: token))
        XCTAssertNil(session.word(NSRange(location: 20, length: 5), generation: token))
        XCTAssertEqual(session.offset, 130)
    }

    func testEmptyTextAndInvalidStartAreClamped() {
        var session = ReadingSession()
        _ = session.begin(chapter: 0, offset: 100, textLength: 12)
        XCTAssertEqual(session.state, .finished)
        XCTAssertEqual(session.offset, 12)
        _ = session.begin(chapter: 0, offset: -1, textLength: 12)
        XCTAssertEqual(session.offset, 0)
    }

    func testPageBoundariesAndEndOfBook() {
        let pages = [NSRange(location: 0, length: 10), NSRange(location: 10, length: 20)]
        XCTAssertEqual(ReadingSession.page(containing: 9, in: pages), 0)
        XCTAssertEqual(ReadingSession.page(containing: 10, in: pages), 1)
        XCTAssertEqual(ReadingSession.page(containing: 30, in: pages), 1)
        XCTAssertEqual(ReadingSession.page(containing: 0, in: []), 0)
    }
}
