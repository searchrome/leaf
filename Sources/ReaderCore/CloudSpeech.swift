import Foundation
import NaturalLanguage

public struct SpeechModel: Decodable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let supportedVoices: [String]?
    enum CodingKeys: String, CodingKey { case id, name; case supportedVoices = "supported_voices" }
    public init(id: String, name: String, supportedVoices: [String]? = nil) {
        self.id = id; self.name = name; self.supportedVoices = supportedVoices
    }
    public static let defaults = [
        SpeechModel(id: "google/gemini-3.8-flash-lite-tts", name: "Gemini 3.8 Flash Lite TTS", supportedVoices: ["Zephyr", "Kore", "Puck", "Charon", "Fenrir", "Aoede"]),
        SpeechModel(id: "google/gemini-3.1-flash-tts-preview", name: "Gemini 3.1 Flash TTS Preview", supportedVoices: ["Zephyr", "Kore", "Puck", "Charon", "Fenrir", "Aoede"])
    ]
}

public struct TranscriptWord: Decodable {
    public let word: String
    public let start: Double
    public let end: Double
    public init(word: String, start: Double, end: Double) {
        self.word = word; self.start = start; self.end = end
    }
}

public struct TimedWord: Equatable {
    public let range: NSRange
    public let start: Double
    public let end: Double
}

public struct SpeechChunk {
    public let text: String
    public let range: NSRange
}

public enum CloudSpeechError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

enum CloudAudio {
    static func isWave(_ data: Data) -> Bool {
        data.count >= 12 && data.prefix(4) == Data("RIFF".utf8)
            && data.dropFirst(8).prefix(4) == Data("WAVE".utf8)
    }

    /// Gemini's raw PCM is signed little-endian, 16-bit mono at 24 kHz.
    /// A WAV container makes those bytes playable by AVAudioPlayer and usable by STT.
    static func waveFromGeminiPCM(_ pcm: Data) throws -> Data {
        if isWave(pcm) { return pcm }
        guard !pcm.isEmpty, pcm.count <= 20_000_000, pcm.count.isMultiple(of: 2) else {
            throw CloudSpeechError.message("Gemini returned empty or invalid PCM audio.")
        }
        var wave = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wave.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count))
        wave.append(Data("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // Linear PCM
        append(UInt16(1)) // Mono
        append(UInt32(24_000))
        append(UInt32(48_000)) // Bytes per second
        append(UInt16(2)) // Block alignment
        append(UInt16(16))
        wave.append(Data("data".utf8))
        append(UInt32(pcm.count))
        wave.append(pcm)
        return wave
    }

    /// Trim measured leading/trailing quiet in our known Gemini WAV layout.
    /// Other containers use the full decoded duration rather than assuming a sample format.
    static func speechBounds(_ audio: Data, duration: Double) -> (Double, Double) {
        guard isWave(audio), audio.count > 44,
              audio.subdata(in: 12..<16) == Data("fmt ".utf8),
              audio.subdata(in: 36..<40) == Data("data".utf8),
              Array(audio[20..<24]) == [1, 0, 1, 0],
              Array(audio[24..<28]) == [192, 93, 0, 0],
              Array(audio[34..<36]) == [16, 0] else { return (0, duration) }
        let bytes = [UInt8](audio.dropFirst(44))
        let frameSamples = 480 // 20 ms at 24 kHz
        var energy: [Double] = []
        for start in stride(from: 0, to: bytes.count / 2, by: frameSamples) {
            let end = min(bytes.count / 2, start + frameSamples)
            var sum = 0.0
            for sample in start..<end {
                let value = Double(Int16(bitPattern: UInt16(bytes[sample * 2]) | UInt16(bytes[sample * 2 + 1]) << 8)) / 32768
                sum += value * value
            }
            energy.append(sqrt(sum / Double(end - start)))
        }
        let threshold = max(0.002, (energy.max() ?? 0) * 0.025)
        guard let first = energy.firstIndex(where: { $0 > threshold }),
              let last = energy.lastIndex(where: { $0 > threshold }) else { return (0, duration) }
        return (max(0, Double(first) * 0.02 - 0.02), min(duration, Double(last + 1) * 0.02 + 0.02))
    }
}

public enum CloudAlignment {
    /// Short sentence groups bound estimated drift and reduce time to the first audio.
    public static func narrationChunks(_ text: String) -> [SpeechChunk] {
        chunks(text, limit: 350, firstLimit: 180)
    }

    /// Deliberately approximate: no transcription or word-accuracy claim.
    /// Each short audio chunk provides a fresh duration anchor; playback rate is handled by the player's clock.
    public static func estimatedTimings(_ text: String, audio: Data, duration: Double) -> [TimedWord] {
        guard duration.isFinite, duration > 0 else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if !normalize(String(text[range])).isEmpty { ranges.append(NSRange(range, in: text)) }
            return true
        }
        guard !ranges.isEmpty else { return [] }
        let ns = text as NSString
        var weights: [(word: Double, pause: Double)] = []
        for (index, range) in ranges.enumerated() {
            let length = normalize(ns.substring(with: range)).count
            let word = 0.7 + pow(Double(max(1, min(16, length))), 0.6)
            var pause = 0.0
            if index + 1 < ranges.count {
                let gap = ns.substring(with: NSRange(location: NSMaxRange(range), length: ranges[index + 1].location - NSMaxRange(range)))
                if gap.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?。！？\n")) != nil { pause = 1.5 }
                else if gap.rangeOfCharacter(from: CharacterSet(charactersIn: ",;:—，；：")) != nil { pause = 0.7 }
            }
            weights.append((word, pause))
        }
        let (start, end) = CloudAudio.speechBounds(audio, duration: duration)
        let scale = (end - start) / weights.reduce(0) { $0 + $1.word + $1.pause }
        var cursor = start
        return zip(ranges, weights).map { range, weight in
            let word = TimedWord(range: range, start: cursor, end: min(end, cursor + weight.word * scale))
            cursor += (weight.word + weight.pause) * scale
            return word
        }
    }

    /// Merge word spans into sentence spans, keeping the union time of each group.
    /// Works from estimated or transcribed word times without further requests.
    public static func sentenceRanges(_ text: String) -> [NSRange] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [NSRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(NSRange(range, in: text))
            return true
        }
        return ranges
    }

    public static func sentenceTimings(text: String, words: [TimedWord]) -> [TimedWord] {
        guard !words.isEmpty else { return [] }
        let sentences = sentenceRanges(text)
        guard !sentences.isEmpty else {
            return [TimedWord(range: NSRange(location: 0, length: text.utf16.count), start: words[0].start, end: words[words.count - 1].end)]
        }
        var result: [TimedWord] = []
        var index = 0
        var current: (start: Double, end: Double)?
        for sentence in sentences {
            while index < words.count, words[index].range.location < NSMaxRange(sentence) {
                current = (current?.start ?? words[index].start, words[index].end)
                index += 1
            }
            if let span = current {
                result.append(TimedWord(range: sentence, start: span.start, end: span.end))
                current = nil
            }
        }
        if let span = current, let last = result.last {
            result[result.count - 1] = TimedWord(range: last.range, start: span.start, end: span.end)
        } else if index < words.count, let last = result.last {
            let start = min(last.start, words[index].start)
            let end = max(last.end, words[words.count - 1].end)
            result[result.count - 1] = TimedWord(range: last.range, start: start, end: end)
        }
        return result
    }

    /// Sentence boundaries keep generated speech natural; offsets remain in the original text.
    public static func chunks(_ text: String, limit: Int = 700, firstLimit: Int? = nil) -> [SpeechChunk] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ends: [Int] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ends.append(NSMaxRange(NSRange(range, in: text)))
            return true
        }
        var chunks: [SpeechChunk] = []
        var start = 0
        while start < ns.length {
            let chunkLimit = chunks.isEmpty ? firstLimit ?? limit : limit
            let bound = min(ns.length, start + max(100, chunkLimit))
            var end = ends.last(where: { $0 > start && $0 <= bound }) ?? bound
            if end == bound, bound < ns.length {
                let search = NSRange(location: start, length: bound - start)
                let space = ns.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: search)
                if space.location != NSNotFound, space.location > start { end = NSMaxRange(space) }
                else {
                    // Do not split a surrogate pair or composed character in long unbroken text.
                    end = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: bound - 1))
                }
            }
            if ns.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, range: NSRange(location: start, length: ns.length - start)).location == NSNotFound {
                if let previous = chunks.popLast() {
                    let range = NSRange(location: previous.range.location, length: ns.length - previous.range.location)
                    chunks.append(SpeechChunk(text: ns.substring(with: range), range: range))
                }
                break
            }
            let range = NSRange(location: start, length: end - start)
            chunks.append(SpeechChunk(text: ns.substring(with: range), range: range))
            start = end
        }
        return chunks
    }

    /// Exact normalized text matching, allowing tokenization differences such as "can't" / "can 't".
    /// Never invent timings for unmatched words: an unsupported transcript fails explicitly.
    public static func align(_ text: String, words: [TranscriptWord], duration: Double) throws -> [TimedWord] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var source: [(range: NSRange, key: String)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let key = normalize(String(text[range]))
            if !key.isEmpty { source.append((NSRange(range, in: text), key)) }
            return true
        }
        let transcript = words.filter { !normalize($0.word).isEmpty }
        guard !source.isEmpty, !transcript.isEmpty, duration.isFinite, duration > 0 else {
            throw CloudSpeechError.message("OpenRouter did not return usable word timings. Try another timing model, or turn off word highlighting in Settings.")
        }
        var previousEnd = 0.0
        for word in transcript {
            guard word.start.isFinite, word.end.isFinite, word.start >= 0, word.start >= previousEnd - 0.03,
                  word.end > word.start, word.end <= duration + 0.25 else {
                throw CloudSpeechError.message("The cloud word timings were invalid. Playback stopped to avoid incorrect highlights.")
            }
            previousEnd = word.end
        }
        var result: [TimedWord] = []
        var s = 0
        var t = 0
        while s < source.count, t < transcript.count {
            var match: (Int, Int)?
            for sourceCount in 1...min(3, source.count - s) {
                let sourceKey = source[s..<(s + sourceCount)].map(\.key).joined()
                for transcriptCount in 1...min(3, transcript.count - t) {
                    let transcriptKey = transcript[t..<(t + transcriptCount)].map { normalize($0.word) }.joined()
                    if sourceKey == transcriptKey { match = (sourceCount, transcriptCount); break }
                }
                if match != nil { break }
            }
            guard let (sourceCount, transcriptCount) = match else {
                throw CloudSpeechError.message("The generated voice and word transcript did not match the book exactly. Try another timing model, or turn off word highlighting to listen without it.")
            }
            let range = NSRange(location: source[s].range.location, length: NSMaxRange(source[s + sourceCount - 1].range) - source[s].range.location)
            result.append(TimedWord(range: range, start: transcript[t].start, end: transcript[t + transcriptCount - 1].end))
            s += sourceCount
            t += transcriptCount
        }
        guard s == source.count, t == transcript.count else {
            throw CloudSpeechError.message("The cloud transcript omitted or added words. Playback stopped to avoid drifting highlights.")
        }
        return result
    }

    private static func normalize(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}

public struct OpenRouterClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func models() async throws -> [SpeechModel] {
        let (data, response) = try await session.data(from: URL(string: "https://openrouter.ai/api/v1/models?output_modalities=speech")!)
        try Self.check(response, data: data, operation: "model catalog")
        struct Catalog: Decodable { let data: [SpeechModel] }
        return try JSONDecoder().decode(Catalog.self, from: data).data.sorted { $0.name < $1.name }
    }

    public func speech(text: String, model: String, voice: String, key: String) async throws -> Data {
        let usesPCM = model.hasPrefix("google/gemini-")
        let data = try await post("audio/speech", body: ["model": model, "input": text, "voice": voice, "response_format": usesPCM ? "pcm" : "mp3"], key: key, operation: "speech generation (\(model), voice \(voice))", privateValues: [text])
        guard !data.isEmpty, data.count <= 20_000_000 else { throw CloudSpeechError.message("The voice provider returned empty or oversized audio.") }
        return usesPCM ? try CloudAudio.waveFromGeminiPCM(data) : data
    }

    public func timings(audio: Data, model: String, key: String) async throws -> [TranscriptWord] {
        let data = try await post("audio/transcriptions", body: [
            "model": model,
            "input_audio": ["data": audio.base64EncodedString(), "format": CloudAudio.isWave(audio) ? "wav" : "mp3"],
            "response_format": "verbose_json",
            "timestamp_granularities": ["word"]
        ], key: key, operation: "word timing (\(model))", privateValues: [audio.base64EncodedString()])
        struct Transcript: Decodable { let words: [TranscriptWord]? }
        guard let transcript = try? JSONDecoder().decode(Transcript.self, from: data),
              let words = transcript.words, !words.isEmpty else {
            throw CloudSpeechError.message("OpenRouter returned no usable word timings for \(model). Choose a timing model that supports word timestamps, or turn off word highlighting in Settings.")
        }
        return words
    }

    private func post(_ path: String, body: [String: Any], key: String, operation: String, privateValues: [String]) async throws -> Data {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudSpeechError.message("Add your OpenRouter API key in Reading settings first.")
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Leaf EPUB Reader", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        try Self.check(response, data: data, operation: operation, privateValues: privateValues + [key])
        return data
    }

    private static func check(_ response: URLResponse, data: Data, operation: String, privateValues: [String] = []) throws {
        guard let http = response as? HTTPURLResponse else { throw CloudSpeechError.message("OpenRouter returned an invalid response.") }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            switch http.statusCode {
            case 401: message = "OpenRouter rejected the API key. Check the key in Settings."
            case 403: message = "OpenRouter denied this request. Check the key permissions and your account's model and privacy restrictions."
            case 402: message = "Your OpenRouter account needs credits to generate speech."
            case 400, 404, 422:
                message = operation.hasPrefix("word timing")
                    ? "Choose a timing model that supports word timestamps, or turn off word highlighting in Settings."
                    : "Refresh models in Settings and choose a supported model and voice."
            case 429: message = "OpenRouter is rate limiting requests. Please try again shortly."
            default: message = "OpenRouter request failed (HTTP \(http.statusCode)). Please try again."
            }
            // Only show the top-level API message, never raw provider metadata or request bodies.
            var detail = ""
            if http.statusCode != 401, http.statusCode != 403,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any], let value = error["message"] as? String {
                detail = value
                for value in privateValues where !value.isEmpty {
                    detail = detail.replacingOccurrences(of: value, with: "[redacted]")
                }
                detail = detail.replacingOccurrences(of: "sk-[A-Za-z0-9_-]+", with: "[redacted]", options: .regularExpression)
                detail = String(detail.components(separatedBy: .controlCharacters).joined(separator: " ").prefix(400))
            }
            throw CloudSpeechError.message("OpenRouter \(operation) failed (HTTP \(http.statusCode)). \(message)" + (detail.isEmpty ? "" : " Provider: \(detail)"))
        }
    }
}
