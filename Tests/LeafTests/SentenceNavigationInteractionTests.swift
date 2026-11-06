import XCTest
import ReaderCore
@testable import Leaf

final class SentenceNavigationInteractionTests: XCTestCase {
    @MainActor
    func testPausedJumpsUpdateSentenceWithoutStartingAudioInEitherView() {
        for fullscreen in [false, true] {
            let reader = makeReader()
            reader.book = Book(title: "Test", author: "Test", chapters: [
                Chapter(id: "one", title: "One", text: "First sentence. Second sentence. Third sentence.")
            ])
            reader.repaginate()
            reader.state = .paused
            reader.isListeningView = fullscreen
            reader.navigateReading(1)
            XCTAssertEqual(reader.listeningSentence.trimmingCharacters(in: .whitespacesAndNewlines), "Second sentence.")
            XCTAssertEqual(reader.state, .paused)
            XCTAssertEqual(reader.isListeningView, fullscreen)
            XCTAssertFalse(reader.preparingCloud)
            reader.navigateReading(1)
            XCTAssertEqual(reader.listeningSentence, "Third sentence.")
            reader.navigateReading(1)
            XCTAssertEqual(reader.listeningSentence, "Third sentence.")
            XCTAssertEqual(reader.state, .paused)
            reader.navigateReading(-1)
            XCTAssertEqual(reader.listeningSentence.trimmingCharacters(in: .whitespacesAndNewlines), "Second sentence.")
            XCTAssertEqual(reader.state, .paused)
            XCTAssertEqual(reader.isListeningView, fullscreen)
            reader.stop()
        }
    }

    @MainActor
    func testPausedJumpCrossesPagesAndChaptersWhileKeepingListeningView() {
        let reader = makeReader()
        let first = String(repeating: "Long passage ", count: 100) + "."
        reader.book = Book(title: "Test", author: "Test", chapters: [
            Chapter(id: "one", title: "One", text: first + " Last sentence."),
            Chapter(id: "empty", title: "Empty", text: "\n"),
            Chapter(id: "two", title: "Two", text: "Next chapter.")
        ])
        reader.resize(CGSize(width: 240, height: 180))
        reader.state = .paused
        reader.isListeningView = true
        reader.navigateReading(1)
        XCTAssertGreaterThan(reader.pageIndex, 0)
        reader.navigateReading(1)
        XCTAssertEqual(reader.chapterIndex, 2)
        XCTAssertEqual(reader.pageIndex, 0)
        reader.navigateReading(-1)
        XCTAssertEqual(reader.chapterIndex, 0)
        XCTAssertGreaterThan(reader.pageIndex, 0)
        XCTAssertEqual(reader.state, .paused)
        XCTAssertTrue(reader.isListeningView)
        XCTAssertFalse(reader.preparingCloud)
        reader.stop()
    }
    @MainActor
    private func makeReader() -> ReaderModel {
        let suite = "leaf-reader-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ReaderModel(restorePosition: false, defaults: defaults)
    }

}
