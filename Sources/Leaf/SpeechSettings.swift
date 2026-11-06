import Foundation
import Security
import LocalAuthentication
import ReaderCore

@MainActor
final class SpeechSettings: ObservableObject {
    enum Provider: String, CaseIterable { case mac = "Mac voice"; case openRouter = "OpenRouter"; case local = "Local model" }
    @Published var provider: Provider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "speechProvider") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "cloudModel") } }
    @Published var voice: String { didSet { UserDefaults.standard.set(voice, forKey: "cloudVoice") } }
    @Published var timingModel: String { didSet { UserDefaults.standard.set(timingModel, forKey: "timingModel") } }
    @Published var wordHighlighting: Bool { didSet { UserDefaults.standard.set(wordHighlighting, forKey: "cloudWordHighlighting") } }
    @Published var timingMode: CloudWordTiming { didSet { UserDefaults.standard.set(timingMode.rawValue, forKey: "cloudTimingMode") } }
    @Published var highlightGranularity: HighlightGranularity { didSet { UserDefaults.standard.set(highlightGranularity.rawValue, forKey: "highlightGranularity") } }
    @Published var localVoice: String { didSet { UserDefaults.standard.set(localVoice, forKey: "localKokoroVoice") } }
    @Published var keyDraft = ""
    @Published var hasKey = false
    @Published var message: String?
    @Published var models = SpeechModel.defaults
    @Published var loadingModels = false

    init() {
        let defaults = UserDefaults.standard
        localVoice = defaults.string(forKey: "localKokoroVoice") ?? "af_heart"
        provider = Provider(rawValue: defaults.string(forKey: "speechProvider") ?? "") ?? .mac
        let selection = Self.savedSelection(defaults: defaults)
        model = selection.model
        voice = selection.voice
        timingModel = defaults.string(forKey: "timingModel") ?? "openai/whisper-1"
        wordHighlighting = defaults.object(forKey: "cloudWordHighlighting") as? Bool ?? true
        timingMode = CloudWordTiming(rawValue: defaults.string(forKey: "cloudTimingMode") ?? "") ?? .estimated
        highlightGranularity = HighlightGranularity(rawValue: defaults.string(forKey: "highlightGranularity") ?? "") ?? .sentence
        hasKey = KeychainKey.exists
    }

    static func savedSelection(defaults: UserDefaults) -> (model: String, voice: String) {
        let model = defaults.string(forKey: "cloudModel") ?? SpeechModel.seedAudioID
        let defaultVoice = SpeechModel.allowsAutomaticVoice(model) ? "" : "Zephyr"
        return (model, defaults.string(forKey: "cloudVoice") ?? defaultVoice)
    }

    func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { message = "Enter an OpenRouter API key first."; return }
        do {
            try KeychainKey.save(key)
            keyDraft = ""
            hasKey = true
            provider = .openRouter
            message = "Key saved in macOS Keychain. OpenRouter is selected."
        } catch { message = error.localizedDescription }
    }

    func removeKey() {
        do {
            try KeychainKey.remove()
            keyDraft = ""
            hasKey = false
            message = "API key removed."
        } catch { message = error.localizedDescription }
    }

    func selectModel(_ id: String) {
        model = id
        if availableVoices.contains("Zephyr") { voice = "Zephyr" }
        else if let first = availableVoices.first { voice = first }
        else if id.hasPrefix("openai/") { voice = "alloy" }
        else { voice = "" }
    }

    var availableVoices: [String] { models.first(where: { $0.id == model })?.supportedVoices ?? [] }
    var allowsAutomaticVoice: Bool { SpeechModel.allowsAutomaticVoice(model) }

    func refreshModels() async {
        loadingModels = true
        defer { loadingModels = false }
        do {
            let fetched = try await OpenRouterClient().models()
            guard !fetched.isEmpty else { throw CloudSpeechError.message("No speech models were returned. You can enter a model ID manually.") }
            models = fetched
            message = "Speech model list updated."
        } catch { message = error.localizedDescription }
    }

    var narrationVoice: String {
        switch provider {
        case .mac: return "Mac voice"
        case .openRouter: return voice.isEmpty ? "Automatic" : voice
        case .local: return "Kokoro · \(localVoice)"
        }
    }

    func configuration(preview: Bool = false) throws -> CloudConfiguration {
        if provider == .local {
            guard LocalKokoro.shared.isReady, !LocalKokoro.shared.isInstalling else {
                throw LocalKokoro.failure("Download and prepare Kokoro in Reading settings first.")
            }
            guard LocalKokoro.shared.voices.contains(localVoice) else {
                throw LocalKokoro.failure("Choose an installed Kokoro voice in Reading settings.")
            }
            return CloudConfiguration(key: "", model: "local/kokoro-82m", voice: localVoice,
                                      timingModel: "", alignWords: wordHighlighting && !preview,
                                      timingMode: .estimated, highlightGranularity: highlightGranularity, isLocal: true)
        }
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedVoice = voice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty, !selectedVoice.isEmpty || SpeechModel.allowsAutomaticVoice(selectedModel) else { throw CloudSpeechError.message("Choose a speech model and enter a supported voice in Settings.") }
        if let entry = models.first(where: { $0.id == selectedModel }),
           let problem = Self.unsupportedVoiceMessage(model: selectedModel, voice: selectedVoice, entry: entry) {
            throw CloudSpeechError.message(problem)
        }
        let alignWords = wordHighlighting && !preview
        let selectedTimingModel = timingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alignWords || timingMode == .estimated || !selectedTimingModel.isEmpty else { throw CloudSpeechError.message("Enter a timing model, or select Fast word follow.") }
        return CloudConfiguration(key: try KeychainKey.read(), model: selectedModel, voice: selectedVoice, timingModel: selectedTimingModel, alignWords: alignWords, timingMode: timingMode, highlightGranularity: highlightGranularity)
    }

    func openRouterKey() throws -> String {
        try KeychainKey.read()
    }

    static func unsupportedVoiceMessage(model: String, voice: String, entry: SpeechModel) -> String? {
        guard let voices = entry.supportedVoices, !voices.isEmpty, !voices.contains(voice) else { return nil }
        return "Voice \(voice) is not supported by \(model). Choose one of: \(voices.joined(separator: ", "))."
    }
}

private enum KeychainKey {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "local.leaf.reader").openrouter",
        kSecAttrAccount as String: "api-key"
    ]

    static var exists: Bool {
        var lookup = query
        lookup[kSecReturnAttributes as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        lookup[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(lookup as CFDictionary, nil) == errSecSuccess
    }

    static func read() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw CloudSpeechError.message("The OpenRouter key could not be read from Keychain. Save your key in Settings and try again.")
        }
        return key
    }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CloudSpeechError.message("Keychain could not save the API key (\(status)).") }
    }

    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudSpeechError.message("Keychain could not remove the API key (\(status)).") }
    }
}
