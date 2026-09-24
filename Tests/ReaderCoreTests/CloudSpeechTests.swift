import XCTest
import AVFoundation
@testable import ReaderCore

final class CloudSpeechTests: XCTestCase {
    func testAlignmentUsesSourceUTF16OffsetsAndActualTimestamps() throws {
        let text = "👩🏽‍🚀 Café, welcome home."
        let words = [TranscriptWord(word: "Cafe", start: 0.2, end: 0.5), TranscriptWord(word: "welcome", start: 0.6, end: 1), TranscriptWord(word: "home.", start: 1.1, end: 1.4)]
        let aligned = try CloudAlignment.align(text, words: words, duration: 1.5)
        XCTAssertEqual(aligned.count, 3)
        XCTAssertEqual(aligned[0].range, (text as NSString).range(of: "Café"))
        XCTAssertEqual(aligned[1].start, 0.6)
        XCTAssertEqual(aligned[2].end, 1.4)
    }

    func testAlignmentDoesNotGuessMissingOrChangedWords() {
        for transcript in [
            [TranscriptWord(word: "hello", start: 0, end: 0.5)],
            [TranscriptWord(word: "hello", start: 0, end: 0.5), TranscriptWord(word: "moon", start: 0.5, end: 1)],
            [TranscriptWord(word: "hello", start: 0, end: 0.5), TranscriptWord(word: "world", start: 0.5, end: 1), TranscriptWord(word: "again", start: 1, end: 1.5)]
        ] { XCTAssertThrowsError(try CloudAlignment.align("Hello world", words: transcript, duration: 2)) }
    }

    func testAlignmentRejectsInvalidAndOverlappingTimes() {
        for words in [
            [TranscriptWord(word: "hello", start: -1, end: 0.5)],
            [TranscriptWord(word: "hello", start: -0.01, end: 0.5)],
            [TranscriptWord(word: "hello", start: 0, end: .infinity)],
            [TranscriptWord(word: "hello", start: 0, end: 50)],
            [TranscriptWord(word: "hello", start: 0.5, end: 0.2)],
            [TranscriptWord(word: "hello", start: 0, end: 1), TranscriptWord(word: "world", start: 0.5, end: 1.2)]
        ] { XCTAssertThrowsError(try CloudAlignment.align("hello world", words: words, duration: 2)) }
    }

    func testRepeatedWordsMapInOrder() throws {
        let result = try CloudAlignment.align("Go, go, go!", words: [
            TranscriptWord(word: "go", start: 0, end: 0.2),
            TranscriptWord(word: "go", start: 0.3, end: 0.5),
            TranscriptWord(word: "go", start: 0.6, end: 0.8)
        ], duration: 1)
        XCTAssertEqual(result.map { $0.range.location }, [0, 4, 8])
    }

    func testEstimatedTimingsSpanWordsWithinMeasuredSpeech() throws {
        let sampleRate = 24_000
        var pcm = Data()
        func append(_ sample: Int16) {
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
        }
        for sample in 0..<2 * sampleRate {
            append(sample >= 6_000 && sample < 42_000 ? 12_000 : 0)
        }
        let wave = try CloudAudio.waveFromGeminiPCM(pcm)
        XCTAssertEqual(try XCTUnwrap(CloudAudio.envelope(wave)).duration, 2, accuracy: 0.001)
        let text = "Hello, wider world! Hello again."
        let timings = CloudAlignment.estimatedTimings(text, audio: wave, duration: 2)
        XCTAssertEqual(timings.count, 5)
        XCTAssertTrue(timings.allSatisfy { $0.start >= 0.21 && $0.end <= 1.79 })
        XCTAssertEqual(timings.map(\.start), timings.map(\.start).sorted())
        for pair in zip(timings, timings.dropFirst()) {
            XCTAssertTrue(pair.0.end <= pair.1.start + 0.001)
        }
        XCTAssertEqual(timings[0].range.location, 0)
        XCTAssertEqual(NSMaxRange(timings.last!.range), NSMaxRange((text as NSString).range(of: "again")))
        let silent = try CloudAudio.waveFromGeminiPCM(Data(repeating: 0, count: 2 * sampleRate))
        let fallback = CloudAlignment.estimatedTimings("Hello world", audio: silent, duration: 1)
        XCTAssertEqual(fallback.count, 2)
        XCTAssertEqual(fallback[0].start, 0)
        XCTAssertEqual(fallback[1].end, 1, accuracy: 0.001)
        XCTAssertTrue(CloudAlignment.estimatedTimings("Hi", audio: wave, duration: 0).isEmpty)
        // AVAudioPlayer under-reports header-less VBR MP3 (Kokoro); the decoded length wins.
        let understated = CloudAlignment.estimatedTimings(text, audio: wave, duration: 1.2)
        XCTAssertEqual(understated.last!.end, timings.last!.end, accuracy: 0.001)
    }

    func testJoinedMP3SegmentsLoseTheirLengthHeaders() {
        // MPEG-2 layer III, 64 kbps, 24 kHz mono: 192-byte frames, Xing tag at byte 13.
        func frame(_ fill: UInt8, xing: Bool = false) -> Data {
            var bytes = [UInt8](repeating: fill, count: 192)
            bytes[0...3] = [0xFF, 0xF3, 0x84, 0xC4]
            if xing { bytes[13..<17] = ArraySlice("Xing".utf8) }
            return Data(bytes)
        }
        let audio = [frame(0, xing: true), frame(1), frame(2), frame(0, xing: true), frame(3)].reduce(Data(), +)
        XCTAssertEqual(CloudAudio.removingMP3LengthHeaders(audio), [frame(1), frame(2), frame(3)].reduce(Data(), +))
        let plain = frame(1) + frame(2)
        XCTAssertEqual(CloudAudio.removingMP3LengthHeaders(plain), plain)
        let notMP3 = Data("not audio".utf8)
        XCTAssertEqual(CloudAudio.removingMP3LengthHeaders(notMP3), notMP3)
    }

    func testEstimatedTimingsRejectTruncatedSpeech() throws {
        let sampleRate = 24_000
        func chunkedPCM(toneFrames: Int) throws -> Data {
            var pcm = Data()
            func append(_ sample: Int16) {
                var littleEndian = sample.littleEndian
                withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
            }
            let total = Int(2.3 * Double(sampleRate))
            let toneStart = sampleRate, toneEnd = toneStart + toneFrames * Int(0.02 * Double(sampleRate))
            for sample in 0..<total {
                append(sample >= toneStart && sample < toneEnd ? 12_000 : 0)
            }
            return try CloudAudio.waveFromGeminiPCM(pcm)
        }
        let text = "Hello world where rivers quietly run"
        XCTAssertTrue(CloudAlignment.estimatedTimings(text, audio: try chunkedPCM(toneFrames: 12), duration: 2.3).isEmpty)
        XCTAssertEqual(CloudAlignment.estimatedTimings(text, audio: try chunkedPCM(toneFrames: 100), duration: 2.3).count, 6)
    }

    func testSentenceTimingsMergeWordsIntoSentenceSpans() throws {
        let text = "Hello world. Hello again!"
        let ns = text as NSString
        let words = [
            TimedWord(range: ns.range(of: "Hello"), start: 0, end: 0.5),
            TimedWord(range: ns.range(of: "world."), start: 0.6, end: 1),
            TimedWord(range: ns.range(of: "Hello", options: .backwards), start: 1.1, end: 1.5),
            TimedWord(range: ns.range(of: "again!"), start: 1.6, end: 2)
        ]
        let sentences = CloudAlignment.sentenceTimings(text: text, words: words)
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].range, NSRange(location: 0, length: 13))
        XCTAssertEqual(sentences[0].start, 0)
        XCTAssertEqual(sentences[0].end, 1)
        XCTAssertEqual(sentences[1].range, NSRange(location: 13, length: 12))
        XCTAssertEqual(sentences[1].start, 1.1)
        XCTAssertEqual(sentences[1].end, 2)
        XCTAssertTrue(CloudAlignment.sentenceTimings(text: text, words: []).isEmpty)
        XCTAssertTrue(CloudAlignment.sentenceRanges("").isEmpty)
        let unterminated = CloudAlignment.sentenceTimings(text: "Hello world", words: [
            TimedWord(range: ns.range(of: "Hello"), start: 0, end: 0.5),
            TimedWord(range: ns.range(of: "world"), start: 0.6, end: 1)
        ])
        XCTAssertEqual(unterminated.count, 1)
        XCTAssertEqual(unterminated[0].range, NSRange(location: 0, length: "Hello world".utf16.count))
        XCTAssertEqual(unterminated[0].start, 0)
        XCTAssertEqual(unterminated[0].end, 1)
    }

    func testSeekStartSnapsToUnitStarts() {
        let text = "Hello world. Hello again!"
        let ns = text as NSString
        XCTAssertEqual(CloudAlignment.seekStart(text, at: ns.range(of: "world.").location + 2, bySentence: false), ns.range(of: "world.").location)
        XCTAssertEqual(CloudAlignment.seekStart(text, at: ns.range(of: "world.").location + 2, bySentence: true), 0)
        XCTAssertEqual(CloudAlignment.seekStart(text, at: ns.range(of: "again!").location, bySentence: true), ns.range(of: "Hello", options: .backwards).location)
        XCTAssertEqual(CloudAlignment.seekStart(text, at: 0, bySentence: false), 0)
        XCTAssertEqual(CloudAlignment.seekStart(text, at: 99, bySentence: false), text.utf16.count)
        XCTAssertEqual(CloudAlignment.seekStart(text, at: -3, bySentence: true), 0)
        XCTAssertEqual(CloudAlignment.seekStart("", at: 0, bySentence: false), 0)
    }

    func testChunkingPreservesAllTextAndUTF16Ranges() {
        for text in [String(repeating: "Café 👩🏽‍🚀 beside the sea. Another sentence!\n\n", count: 50), String(repeating: "👩🏽‍🚀", count: 100), "One sentence.\n\n", ""] {
            let chunks = CloudAlignment.chunks(text, limit: 110)
            XCTAssertEqual(chunks.map(\.text).joined(), text)
            var offset = 0
            for chunk in chunks {
                XCTAssertEqual(chunk.range.location, offset)
                XCTAssertEqual(chunk.text.utf16.count, chunk.range.length)
                XCTAssertFalse(chunk.text.contains("�"))
                offset = NSMaxRange(chunk.range)
            }
            XCTAssertEqual(offset, text.utf16.count)
        }
    }

    func testMissingTimingsFailExplicitly() {
        XCTAssertThrowsError(try CloudAlignment.align("Hello", words: [], duration: 1))
    }
}

final class OpenRouterClientTests: XCTestCase {
    private func client() -> OpenRouterClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubHTTP.self]
        return OpenRouterClient(session: URLSession(configuration: config))
    }

    override func tearDown() { StubHTTP.handler = nil; super.tearDown() }

    func testSpeechRequestUsesSelectedModelVoiceAndAudioFormat() async throws {
        StubHTTP.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/audio/speech")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-placeholder")
            let body = try self.body(request)
            XCTAssertEqual(body["model"] as? String, "google/gemini-3.1-flash-tts-preview")
            XCTAssertEqual(body["voice"] as? String, "Zephyr")
            XCTAssertEqual(body["response_format"] as? String, "pcm")
            XCTAssertEqual(body["input"] as? String, "Hello")
            XCTAssertNil(body["key"])
            return (200, Data(repeating: 0, count: 48_000))
        }
        let audio = try await client().speech(text: "Hello", model: "google/gemini-3.1-flash-tts-preview", voice: "Zephyr", key: "test-placeholder")
        XCTAssertTrue(CloudAudio.isWave(audio))
        XCTAssertEqual(audio.count, 48_044)
        let player = try AVAudioPlayer(data: audio)
        XCTAssertEqual(player.duration, 1, accuracy: 0.001)
    }

    func testTimingRequestAndResponse() async throws {
        StubHTTP.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/audio/transcriptions")
            let body = try self.body(request)
            XCTAssertEqual(body["response_format"] as? String, "verbose_json")
            XCTAssertEqual(body["timestamp_granularities"] as? [String], ["word"])
            XCTAssertEqual(body["model"] as? String, "openai/whisper-1")
            XCTAssertEqual((body["input_audio"] as? [String: String])?["format"], "mp3")
            return (200, Data("{\"words\":[{\"word\":\"Hello\",\"start\":0.1,\"end\":0.5}]}".utf8))
        }
        let words = try await client().timings(audio: Data([1]), model: "openai/whisper-1", key: "test-placeholder")
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].start, 0.1)
    }

    func testOtherSpeechModelsStillUseMP3() async throws {
        StubHTTP.handler = { request in
            XCTAssertEqual(try self.body(request)["response_format"] as? String, "mp3")
            return (200, Data([1, 2, 3]))
        }
        let audio = try await client().speech(text: "Hello", model: "mistralai/voxtral-mini-tts-2603", voice: "test", key: "test-placeholder")
        XCTAssertEqual(audio, Data([1, 2, 3]))
    }

    func testGeminiWaveIsPassedToTranscriptionWithCorrectFormat() async throws {
        let wave = try CloudAudio.waveFromGeminiPCM(Data(repeating: 0, count: 48_000))
        XCTAssertEqual(try CloudAudio.waveFromGeminiPCM(wave), wave)
        StubHTTP.handler = { request in
            let input = try self.body(request)["input_audio"] as? [String: String]
            XCTAssertEqual(input?["format"], "wav")
            XCTAssertEqual(input?["data"], wave.base64EncodedString())
            return (200, Data(#"{"words":[{"word":"Hello","start":0,"end":0.5}]}"#.utf8))
        }
        _ = try await client().timings(audio: wave, model: "openai/whisper-1", key: "test-placeholder")
    }

    func testInvalidPCMIsRejected() {
        for data in [Data(), Data([1, 2, 3])] {
            XCTAssertThrowsError(try CloudAudio.waveFromGeminiPCM(data))
        }
    }

    func testMissingTimingResponseExplainsHowToListen() async {
        StubHTTP.handler = { _ in (200, Data(#"{"text":"Hello"}"#.utf8)) }
        do {
            _ = try await client().timings(audio: Data([1]), model: "test/timing", key: "test-placeholder")
            XCTFail("Expected missing timestamps error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("test/timing"))
            XCTAssertTrue(error.localizedDescription.contains("turn off word highlighting"))
        }
    }

    func testSpeechErrorIncludesReasonButRedactsCredentialsAndText() async {
        StubHTTP.handler = { _ in
            (400, Data(#"{"error":{"message":"Only pcm is supported. test-placeholder sk-or-secret Private book text","metadata":{"raw":"secret metadata"}}}"#.utf8))
        }
        do {
            _ = try await client().speech(text: "Private book text", model: "test/model", voice: "test", key: "test-placeholder")
            XCTFail("Expected speech error")
        } catch {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("speech generation (test/model"))
            XCTAssertTrue(message.contains("HTTP 400"))
            XCTAssertTrue(message.contains("Only pcm is supported"))
            for secret in ["test-placeholder", "sk-or-secret", "Private book text", "secret metadata"] {
                XCTAssertFalse(message.contains(secret))
            }
        }
    }

    func testTimingFailureIdentifiesTimingInsteadOfVoice() async {
        StubHTTP.handler = { _ in (422, Data(#"{"error":{"message":"Unsupported verbose_json"}}"#.utf8)) }
        do {
            _ = try await client().timings(audio: Data([1]), model: "test/timing", key: "test-placeholder")
            XCTFail("Expected timing error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("word timing (test/timing)"))
            XCTAssertTrue(error.localizedDescription.contains("turn off word highlighting"))
            XCTAssertFalse(error.localizedDescription.contains("choose a supported model and voice"))
        }
    }

    func testAuthenticationErrorDoesNotExposeResponseOrCredential() async {
        StubHTTP.handler = { _ in (401, Data("sensitive provider response".utf8)) }
        do {
            _ = try await client().speech(text: "Hi", model: "test", voice: "test", key: "test-placeholder")
            XCTFail("Expected authorization error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API key"))
            XCTAssertFalse(error.localizedDescription.contains("sensitive"))
            XCTAssertFalse(error.localizedDescription.contains("test-placeholder"))
        }
    }

    func testSpeechCatalogUsesSpeechFilter() async throws {
        StubHTTP.handler = { request in
            XCTAssertEqual(request.url?.query, "output_modalities=speech")
            return (200, Data("{\"data\":[{\"id\":\"test/tts\",\"name\":\"Test voice\",\"supported_voices\":[\"Zephyr\"]}]}".utf8))
        }
        let models = try await client().models()
        XCTAssertEqual(models.first?.id, "test/tts")
        XCTAssertEqual(models.first?.supportedVoices, ["Zephyr"])
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}

private final class StubHTTP: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
