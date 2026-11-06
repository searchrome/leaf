import XCTest
@testable import ReaderCore

final class SentenceNavigationTests: XCTestCase {
    private let text = "\nFirst café sentence. Second 👩🏽‍🚀 sentence! Third sentence?\n"
    private func chapters(_ texts: [String]) -> [Chapter] {
        texts.enumerated().map { Chapter(id: String($0.offset), title: "Test", text: $0.element) }
    }

    func testMovesFromInsideSentenceUsingUTF16Offsets() throws {
        let book = chapters([text])
        let second = (text as NSString).range(of: "Second").location
        let third = (text as NSString).range(of: "Third").location
        let current = (text as NSString).range(of: "👩🏽‍🚀").location
        XCTAssertEqual(SentenceNavigation.destination(in: book, chapter: 0, offset: current, direction: 1)?.offset, third)
        XCTAssertEqual(SentenceNavigation.destination(in: book, chapter: 0, offset: current, direction: -1)?.offset,
                       (text as NSString).range(of: "First").location)
        XCTAssertEqual(SentenceNavigation.destination(in: book, chapter: 0, offset: 0, direction: 1)?.offset, second)
    }

    func testRepeatedMovesUseTheNewDestinationBeforeAudioStarts() throws {
        let book = chapters([text])
        let second = try XCTUnwrap(SentenceNavigation.destination(in: book, chapter: 0, offset: 0, direction: 1))
        let third = try XCTUnwrap(SentenceNavigation.destination(in: book, chapter: 0, offset: second.offset, direction: 1))
        XCTAssertEqual(third.offset, (text as NSString).range(of: "Third").location)
        XCTAssertEqual(SentenceNavigation.destination(in: book, chapter: 0, offset: third.offset, direction: -1), second)
        XCTAssertNil(SentenceNavigation.destination(in: book, chapter: 0, offset: third.offset, direction: 1))
        XCTAssertNil(SentenceNavigation.destination(in: book, chapter: 0, offset: 0, direction: -1))
        XCTAssertNil(SentenceNavigation.destination(in: book, chapter: 0, offset: 0, direction: 0))
    }

    func testCrossesChapterBoundariesAndSkipsBlankChapters() throws {
        let book = chapters([text, "\n \t", "\nLast chapter."])
        let destination = try XCTUnwrap(SentenceNavigation.destination(in: book, chapter: 0, offset: text.utf16.count - 1, direction: 1))
        XCTAssertEqual(destination.chapter, 2)
        let previous = try XCTUnwrap(SentenceNavigation.destination(in: book, chapter: 2, offset: destination.offset, direction: -1))
        XCTAssertEqual(previous.chapter, 0)
        XCTAssertEqual(previous.offset, (text as NSString).range(of: "Third").location)
        XCTAssertNil(SentenceNavigation.destination(in: [], chapter: 0, offset: 0, direction: 1))
    }
}
