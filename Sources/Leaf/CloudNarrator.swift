import AVFoundation
import CryptoKit
import Foundation
import ReaderCore

enum CloudWordTiming: String, CaseIterable {
    case estimated
    case transcribed
}

enum HighlightGranularity: String, CaseIterable {
    case word
    case sentence
}

struct CloudConfiguration {
    let key: String
    let model: String
    let voice: String
    let timingModel: String
    var alignWords: Bool
    var timingMode: CloudWordTiming = .transcribed
    var highlightGranularity: HighlightGranularity = .word
}

@MainActor
final class CloudNarrator: NSObject, AVAudioPlayerDelegate {
    struct Prepared {
        let audio: Data
        let words: [TimedWord]
        let warning: String?
    }
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var queued: [Int: Task<Prepared, Error>] = [:]
    private var preparing: Task<Prepared, Error>?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var chunks: [SpeechChunk] = []
    private var index = 0
    private var timedWords: [TimedWord] = []
    private var paused = false
    private var completionPending = false
    private var rate: Float = 1
    private var sentenceHighlighting = false
    private var lastRange: NSRange?
    private var config: CloudConfiguration?
    private var onWord: ((NSRange?) -> Void)?
    private var onFinish: (() -> Void)?
    private var onPreparing: ((Bool) -> Void)?
    private var onError: ((Error) -> Void)?
    private var onWarning: ((String) -> Void)?
    private struct CacheKey: Hashable {
        let text: String
        let model: String
        let voice: String
        let timingModel: String
        let alignWords: Bool
        let timingMode: CloudWordTiming
        let credentialDigest: Data
        init(_ text: String, _ config: CloudConfiguration) {
            self.text = text; model = config.model; voice = config.voice
            timingModel = config.timingModel; alignWords = config.alignWords; timingMode = config.timingMode
            credentialDigest = Data(SHA256.hash(data: Data(config.key.utf8)))
        }
    }
    private var cache: [(key: CacheKey, value: Prepared)] = []

    func start(text: String, configuration: CloudConfiguration, rate: Float,
               onWord: @escaping (NSRange?) -> Void, onFinish: @escaping () -> Void,
               onPreparing: @escaping (Bool) -> Void, onError: @escaping (Error) -> Void,
               onWarning: @escaping (String) -> Void = { _ in }) {
        stop()
        self.config = configuration
        self.rate = rate
        self.sentenceHighlighting = configuration.highlightGranularity == .sentence
        self.onWord = onWord
        self.onFinish = onFinish
        self.onPreparing = onPreparing
        self.onError = onError
        self.onWarning = onWarning
        chunks = CloudAlignment.narrationChunks(text)
        index = 0
        loadChunk()
    }

    func stop() {
        generation = UUID()
        task?.cancel()
        queued.values.forEach { $0.cancel() }
        preparing?.cancel()
        task = nil
        queued.removeAll()
        preparing = nil
        timer?.invalidate()
        timer = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        config = nil
        chunks = []
        paused = false
        completionPending = false
        sentenceHighlighting = false
        lastRange = nil
        onWord = nil
        onFinish = nil
        onPreparing = nil
        onError = nil
        onWarning = nil
    }

    func pause() { paused = true; player?.pause() }
    func resume() {
        paused = false
        if completionPending {
            completionPending = false
            finishedChunk()
        } else if let player, !player.play() {
            onError?(CloudSpeechError.message("The generated audio could not resume."))
        }
    }
    func setRate(_ rate: Float) { self.rate = rate; player?.rate = rate }

    private func loadChunk() {
        guard index < chunks.count, let config else { onFinish?(); return }
        let token = generation
        let chunk = chunks[index]
        // Start a bounded lookahead immediately, overlapping speech and timing requests.
        for upcoming in index...min(index + 2, chunks.count - 1) where queued[upcoming] == nil {
            let next = chunks[upcoming]
            let key = CacheKey(next.text, config)
            if let cached = cache.first(where: { $0.key == key })?.value {
                queued[upcoming] = Task { cached }
            } else {
                queued[upcoming] = Task { try await Self.prepare(next, configuration: config) }
            }
        }
        let preparation = queued.removeValue(forKey: index)!
        preparing = preparation
        lastRange = nil
        onWord?(nil)
        onPreparing?(true)
        task = Task { [weak self] in
            do {
                let prepared = try await preparation.value
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.preparing = nil
                let key = CacheKey(chunk.text, config)
                self.cache.removeAll { $0.key == key }
                self.cache.append((key, prepared))
                while self.cache.count > 12 || self.cache.reduce(0, { $0 + $1.value.audio.count }) > 24_000_000 {
                    self.cache.removeFirst()
                }
                let audioPlayer = try AVAudioPlayer(data: prepared.audio)
                self.player = audioPlayer
                self.timedWords = self.sentenceHighlighting
                    ? CloudAlignment.sentenceTimings(text: chunk.text, words: prepared.words)
                    : prepared.words
                if let warning = prepared.warning {
                    self.config?.timingMode = .estimated
                    self.onWarning?(warning)
                }
                audioPlayer.delegate = self
                audioPlayer.enableRate = true
                audioPlayer.rate = self.rate
                audioPlayer.prepareToPlay()
                self.onPreparing?(false)
                if !self.paused, !audioPlayer.play() { throw CloudSpeechError.message("The generated audio could not play.") }
                self.timer?.invalidate()
                let timer = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.tick() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            } catch {
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.onPreparing?(false)
                self.onError?(error)
            }
        }
    }

    static func prepare(_ chunk: SpeechChunk, configuration: CloudConfiguration, client: OpenRouterClient = OpenRouterClient()) async throws -> Prepared {
        try Task.checkCancellation()
        let audio = try await client.speech(text: chunk.text, model: configuration.model, voice: configuration.voice, key: configuration.key)
        try Task.checkCancellation()
        let probe = try AVAudioPlayer(data: audio)
        guard probe.duration.isFinite, probe.duration > 0 else { throw CloudSpeechError.message("The cloud voice returned invalid audio.") }
        var words: [TimedWord] = []
        var warning: String?
        if configuration.alignWords {
            if configuration.timingMode == .estimated {
                words = CloudAlignment.estimatedTimings(chunk.text, audio: audio, duration: probe.duration)
                if words.isEmpty {
                    warning = "The voice returned much shorter audio than this passage needs, so word following is off for it."
                }
            } else {
                do {
                    let transcript = try await client.timings(audio: audio, model: configuration.timingModel, key: configuration.key)
                    try Task.checkCancellation()
                    words = try CloudAlignment.align(chunk.text, words: transcript, duration: probe.duration)
                } catch {
                    try Task.checkCancellation()
                    words = CloudAlignment.estimatedTimings(chunk.text, audio: audio, duration: probe.duration)
                    warning = "Using estimated word following because audio timestamps were unavailable or did not match the text. Highlights may drift; each short passage starts a fresh estimate."
                }
            }
        }
        return Prepared(audio: audio, words: words, warning: warning)
    }

    private func tick() {
        guard !paused, let player, player.isPlaying, index < chunks.count else { return }
        let time = player.currentTime
        let word = timedWords.first { time >= $0.start && time < $0.end }
        let chunkRange = chunks[index].range
        let range: NSRange?
        if timedWords.isEmpty {
            range = sentenceHighlighting
                ? chunkRange
                : NSRange(location: chunkRange.location, length: min(1, chunkRange.length))
        } else if let word {
            range = NSRange(location: chunkRange.location + word.range.location, length: word.range.length)
        } else if sentenceHighlighting, let current = timedWords.last(where: { $0.start <= time }) {
            range = NSRange(location: chunkRange.location + current.range.location, length: current.range.length)
        } else {
            range = nil
        }
        if range != lastRange { lastRange = range; onWord?(range) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            guard flag else { self.onError?(CloudSpeechError.message("Cloud audio playback was interrupted.")); return }
            if self.paused { self.completionPending = true; return }
            self.finishedChunk()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.onError?(CloudSpeechError.message("The cloud voice returned audio that this Mac could not decode."))
        }
    }

    private func finishedChunk() {
        timer?.invalidate()
        timer = nil
        player = nil
        index += 1
        loadChunk()
    }
}
