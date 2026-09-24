import XCTest
import ReaderCore
@testable import Leaf

final class CloudNarratorTests: XCTestCase {
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
