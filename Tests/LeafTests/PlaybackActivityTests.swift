import XCTest
@testable import Leaf

final class PlaybackActivityTests: XCTestCase {
    @MainActor
    func testReaderHoldsSleepDuringNarrationAndPreparationAndReleasesWhenPausedOrFinished() {
        let reader = makeReader()
        XCTAssertFalse(reader.preventsIdleSleep)
        reader.state = .speaking
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.preparingCloud = true
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.preparingCloud = false
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.state = .paused
        XCTAssertFalse(reader.preventsIdleSleep)
        reader.state = .speaking
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.state = .finished
        XCTAssertFalse(reader.preventsIdleSleep)
        reader.state = .speaking
        reader.stop()
        XCTAssertFalse(reader.preventsIdleSleep)
    }

    @MainActor
    func testPreviewHoldsSleepUntilStoppedAndPreparationAloneDoesNot() {
        let reader = makeReader()
        reader.preparingCloud = true
        XCTAssertFalse(reader.preventsIdleSleep)
        reader.isPreviewing = true
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.preparingCloud = false
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.stop()
        XCTAssertFalse(reader.preventsIdleSleep)
        reader.isPreviewing = true
        reader.isPreviewing = false
        XCTAssertFalse(reader.preventsIdleSleep)
    }

    @MainActor
    func testRepeatedStateUpdatesAndOverlappingPreviewDoNotReleaseNarrationHold() {
        let reader = makeReader()
        reader.state = .speaking
        reader.state = .speaking
        reader.isPreviewing = true
        reader.isPreviewing = false
        XCTAssertTrue(reader.preventsIdleSleep)
        reader.stop()
        reader.stop()
        XCTAssertFalse(reader.preventsIdleSleep)
    }
    @MainActor
    private func makeReader() -> ReaderModel {
        let suite = "leaf-reader-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ReaderModel(restorePosition: false, defaults: defaults)
    }

}
