import AVFoundation
import ReaderCore
import SwiftUI

@MainActor
final class PassageChatModel: NSObject, ObservableObject, Identifiable, AVSpeechSynthesizerDelegate {
    enum QuickPrompt: String, CaseIterable {
        case summarize = "Summarize"
        case simplify = "Simplify"
        case keyPoints = "Key points"
        case example = "Give an example"

        var question: String {
            switch self {
            case .summarize: return "Can you summarize this passage briefly?"
            case .simplify: return "Can you explain this passage at a more basic level, using simple words?"
            case .keyPoints: return "What are the key points in this passage?"
            case .example: return "Can you give a simple, concrete example that helps explain this passage?"
            }
        }
    }

    typealias Reply = (String, [PassageChatMessage], String, String) async throws -> String
    let id = UUID()
    let passage: String
    let settings: SpeechSettings
    let voiceID: String
    let rate: Float
    @Published var draft = ""
    @Published private(set) var messages: [PassageChatMessage] = []
    @Published private(set) var pendingQuestion: String?
    @Published private(set) var isThinking = false
    @Published private(set) var speakingMessageID: UUID?
    @Published private(set) var preparingAudio = false
    @Published var error: String?
    private let reply: Reply
    private let key: () throws -> String
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let synthesizer = AVSpeechSynthesizer()
    private let audio = CloudNarrator()
    private let activity = PlaybackActivity()
    private var utterance: AVSpeechUtterance?

    init(passage: String, settings: SpeechSettings, voiceID: String, rate: Float,
         key: (() throws -> String)? = nil,
         reply: @escaping Reply = { passage, messages, model, key in
             try await OpenRouterClient().passageChat(passage: passage, messages: messages, model: model, key: key)
         }) {
        self.passage = passage
        self.settings = settings
        self.voiceID = voiceID
        self.rate = rate
        self.key = key ?? { try settings.openRouterKey() }
        self.reply = reply
        super.init()
        synthesizer.delegate = self
    }

    deinit { task?.cancel() }

    var canSend: Bool {
        canSendQuickPrompt && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSendQuickPrompt: Bool { !isThinking && messages.count < 40 }

    func sendQuickPrompt(_ prompt: QuickPrompt) {
        guard canSendQuickPrompt else { return }
        draft = prompt.question
        send()
    }

    func send() {
        guard canSend else { return }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.utf16.count <= 8_000 else { error = "Keep your question under 8,000 characters."; return }
        let credential: String
        do { credential = try key() } catch { self.error = error.localizedDescription; return }
        stopAudio()
        error = nil
        let user = PassageChatMessage(role: .user, content: question)
        let history = messages + [user]
        let model = settings.chatModel
        let passage = passage
        let reply = reply
        let token = UUID()
        generation = token
        pendingQuestion = question
        isThinking = true
        task = Task { [weak self] in
            do {
                let answer = try await reply(passage, history, model, credential)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.messages = history + [PassageChatMessage(role: .assistant, content: answer)]
                self.draft = ""
                self.pendingQuestion = nil
                self.isThinking = false
                self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.pendingQuestion = nil
                self.isThinking = false
                self.task = nil
                self.error = error.localizedDescription
            }
        }
    }

    func cancelRequest() {
        generation = UUID()
        task?.cancel()
        task = nil
        isThinking = false
        pendingQuestion = nil
    }

    func close() {
        cancelRequest()
        stopAudio()
    }

    func listen(_ message: PassageChatMessage) {
        if speakingMessageID == message.id { stopAudio(); return }
        stopAudio()
        guard message.role == .assistant else { return }
        error = nil
        speakingMessageID = message.id
        if settings.provider == .mac {
            let utterance = AVSpeechUtterance(string: message.content)
            utterance.voice = voiceID.isEmpty ? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en") : AVSpeechSynthesisVoice(identifier: voiceID)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
            self.utterance = utterance
            activity.setActive(true)
            synthesizer.speak(utterance)
        } else {
            do {
                let config = try settings.configuration(preview: true)
                activity.setActive(true)
                audio.start(text: message.content, configuration: config, rate: rate,
                            onWord: { _ in }, onFinish: { [weak self] in self?.stopAudio() },
                            onPreparing: { [weak self] in self?.preparingAudio = $0 },
                            onError: { [weak self] error in self?.stopAudio(); self?.error = error.localizedDescription })
            } catch { stopAudio(); self.error = error.localizedDescription }
        }
    }

    func stopAudio() {
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        audio.stop()
        speakingMessageID = nil
        preparingAudio = false
        activity.setActive(false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.stopAudio()
        }
    }
}
