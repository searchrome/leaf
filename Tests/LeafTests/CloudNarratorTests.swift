import XCTest
import ReaderCore
@testable import Leaf

final class CloudNarratorTests: XCTestCase {
    @MainActor
    func testFreshSpeechSelectionDefaultsToSeedAutomaticVoice() {
        let defaults = UserDefaults(suiteName: "test-seed-default-selection")!
        defer { defaults.removePersistentDomain(forName: "test-seed-default-selection") }
        let selection = SpeechSettings.savedSelection(defaults: defaults)
        XCTAssertEqual(selection.model, SpeechModel.seedAudioID)
        XCTAssertEqual(selection.voice, "")
    }

    @MainActor
    func testSelectingSeedClearsPreviousVoiceAndAllowsAutomaticNarration() {
        let settings = SpeechSettings()
        let previousModel = settings.model
        let previousVoice = settings.voice
        defer { settings.model = previousModel; settings.voice = previousVoice }
        settings.voice = "Zephyr"
        settings.selectModel(SpeechModel.seedAudioID)
        XCTAssertTrue(settings.allowsAutomaticVoice)
        XCTAssertEqual(settings.voice, "")
        XCTAssertTrue(settings.availableVoices.isEmpty)
    }

    @MainActor
    func testSavedGeminiVoiceSurvivesRestart() {
        let defaults = UserDefaults(suiteName: "test-speech-selection")!
        defer { defaults.removePersistentDomain(forName: "test-speech-selection") }
        defaults.set("google/gemini-3.1-flash-tts-preview", forKey: "cloudModel")
        defaults.set("Umbriel", forKey: "cloudVoice")
        let selection = SpeechSettings.savedSelection(defaults: defaults)
        XCTAssertEqual(selection.model, "google/gemini-3.1-flash-tts-preview")
        XCTAssertEqual(selection.voice, "Umbriel")
    }

    @MainActor
    func testUnsupportedVoiceIsRejectedBeforeAnyRequest() {
        let qwen = SpeechModel(id: "qwen/qwen-audio-3.0-tts-flash", name: "Qwen Audio 3.0 TTS Flash", supportedVoices: ["longanhuan_v3.6", "loongjohn"])
        let mismatch = SpeechSettings.unsupportedVoiceMessage(model: qwen.id, voice: "Zephyr", entry: qwen)
        XCTAssertNotNil(mismatch)
        XCTAssertTrue(mismatch!.contains("longanhuan_v3.6, loongjohn"))
        XCTAssertNil(SpeechSettings.unsupportedVoiceMessage(model: qwen.id, voice: "loongjohn", entry: qwen))
        XCTAssertNil(SpeechSettings.unsupportedVoiceMessage(model: qwen.id, voice: "anything", entry: SpeechModel(id: "x", name: "X", supportedVoices: nil)))
    }
    @MainActor
    func testReadingPositionRoundTrip() {
        let defaults = UserDefaults(suiteName: "test-reading-position")!
        defer { defaults.removePersistentDomain(forName: "test-reading-position") }
        XCTAssertNil(ReadingPositionStore.load(defaults: defaults))
        let position = ReadingPosition(bookmark: Data([1, 2, 3]), chapterIndex: 2, pageIndex: 5)
        ReadingPositionStore.save(position, defaults: defaults)
        XCTAssertEqual(ReadingPositionStore.load(defaults: defaults), position)
        let demoPosition = ReadingPosition(bookmark: nil, chapterIndex: 0, pageIndex: 1)
        ReadingPositionStore.save(demoPosition, defaults: defaults)
        XCTAssertEqual(ReadingPositionStore.load(defaults: defaults), demoPosition)
        defaults.set(Data("broken".utf8), forKey: ReadingPositionStore.key)
        XCTAssertNil(ReadingPositionStore.load(defaults: defaults))
        defaults.set(Data(#"{"chapterIndex":-1,"pageIndex":0}"#.utf8), forKey: ReadingPositionStore.key)
        XCTAssertNil(ReadingPositionStore.load(defaults: defaults))
    }

    @MainActor
    func testTextBookmarksPersistPerBookAndDiscardStaleQuotes() {
        let defaults = UserDefaults(suiteName: "test-text-bookmarks")!
        defer { defaults.removePersistentDomain(forName: "test-text-bookmarks") }
        let chapter = Chapter(id: "one", title: "One", text: "The old oak stood beside the lane.")
        let book = Book(title: "Test", author: "Reader", chapters: [chapter])
        let range = (chapter.text as NSString).range(of: "old oak")
        let bookmark = TextBookmark(chapter: chapter, chapterIndex: 0, range: range, quote: "old oak")

        TextBookmarkStore.save([bookmark], bookID: "test-book", defaults: defaults)
        XCTAssertEqual(TextBookmarkStore.load(bookID: "test-book", book: book, defaults: defaults), [bookmark])

        let editedBook = Book(title: "Test", author: "Reader", chapters: [Chapter(id: "one", title: "One", text: "The young oak stood beside the lane.")])
        XCTAssertEqual(TextBookmarkStore.load(bookID: "test-book", book: editedBook, defaults: defaults), [])
        XCTAssertEqual(TextBookmarkStore.load(bookID: "another-book", book: book, defaults: defaults), [])
    }
    @MainActor
    func testTimingFailureFallsBackToEstimatedWordsAndShowsNotice() async throws {
        for response in [
            (422, #"{"error":{"message":"Unsupported timing format"}}"#),
            (200, #"{"words":[{"word":"Goodbye","start":0,"end":0.5}]}"#),
            (200, #"{"text":"Hello"}"#)
        ] {
            NarrationHTTP.timingResponse = response
            let prepared = try await prepare()
            XCTAssertFalse(prepared.audio.isEmpty)
            XCTAssertEqual(prepared.words.count, 1)
            XCTAssertEqual(prepared.words[0].range.location, 0)
            XCTAssertNotNil(prepared.warning)
            XCTAssertTrue(prepared.warning!.contains("estimated"))
        }
    }

    @MainActor
    func testMatchingTimingRetainsHighlightsWithoutNotice() async throws {
        NarrationHTTP.timingResponse = (200, #"{"words":[{"word":"Hello","start":0,"end":0.5}]}"#)
        let prepared = try await prepare()
        XCTAssertEqual(prepared.words.count, 1)
        XCTAssertNil(prepared.warning)
    }

    @MainActor
    func testCancelledPreparationDoesNotFallBackToPlayback() async {
        let task = Task { @MainActor in try await self.prepare() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled preparation must not return playable audio")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    @MainActor
    private func prepare() async throws -> CloudNarrator.Prepared {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [NarrationHTTP.self]
        return try await CloudNarrator.prepare(
            CloudAlignment.chunks("Hello")[0],
            configuration: CloudConfiguration(key: "test-placeholder", model: "google/gemini-3.1-flash-tts-preview", voice: "Zephyr", timingModel: "openai/whisper-1", alignWords: true),
            client: OpenRouterClient(session: URLSession(configuration: session)))
    }
}

private final class NarrationHTTP: URLProtocol {
    static var timingResponse = (200, "{}")
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let speech = request.url!.path.hasSuffix("/speech")
        let status = speech ? 200 : Self.timingResponse.0
        let data = speech ? Data(repeating: 0, count: 48_000) : Data(Self.timingResponse.1.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
