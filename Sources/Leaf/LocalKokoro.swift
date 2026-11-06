import Combine
import CryptoKit
import Foundation

struct LocalSpeechCompatibility {
    let supported: Bool
    let message: String

    static func evaluate(appleSilicon: Bool, memoryGB: UInt64, osMajor: Int, freeBytes: Int64?) -> Self {
        guard appleSilicon else { return Self(supported: false, message: "Local Kokoro requires an Apple Silicon Mac (M1 or newer). Mac voices remain available.") }
        guard osMajor >= 14 else { return Self(supported: false, message: "Local Kokoro requires macOS 14 or later.") }
        guard memoryGB >= 8 else { return Self(supported: false, message: "Local Kokoro requires at least 8 GB of memory.") }
        if let freeBytes, freeBytes < 4_000_000_000 {
            return Self(supported: false, message: "Free at least 4 GB of disk space before setting up Kokoro.")
        }
        return Self(supported: true, message: "Compatible Apple Silicon Mac · \(memoryGB) GB memory")
    }
}

struct LocalKokoroInstallation: Codable {
    let version: Int
    let revision: String
    let voices: [String]
    let audioSeconds: Double
    let generationSeconds: Double

    var benchmark: String {
        String(format: "Speed check: %.1f seconds of speech generated in %.1f seconds (%.1f× real time).", audioSeconds, generationSeconds, audioSeconds / max(0.001, generationSeconds))
    }
}

@MainActor
final class LocalKokoro: ObservableObject {
    static let shared = LocalKokoro()
    static let revision = "a71e4d38b236d968966a2002c4c895dbd12b1c3c"
    @Published private(set) var isInstalling = false
    @Published private(set) var stage = ""
    @Published private(set) var installation: LocalKokoroInstallation?
    @Published private(set) var error: String?
    private var installTask: Task<Void, Never>?
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf/LocalKokoro", isDirectory: true)
        refresh()
    }

    nonisolated static func failure(_ message: String) -> NSError {
        NSError(domain: "Leaf.LocalKokoro", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    var compatibility: LocalSpeechCompatibility {
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        let disk = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return .evaluate(appleSilicon: appleSilicon,
                         memoryGB: ProcessInfo.processInfo.physicalMemory / 1_073_741_824,
                         osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                         freeBytes: isReady ? nil : disk?.volumeAvailableCapacityForImportantUsage)
    }

    var isReady: Bool { installation != nil }
    var hasDownload: Bool { FileManager.default.fileExists(atPath: root.path) }
    var python: URL { root.appendingPathComponent("runtime/bin/python") }
    var voices: [String] { installation?.voices ?? [] }
    func workerURL() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "LocalKokoro", withExtension: "py") { return bundled }
        if Bundle.main.bundleURL.pathExtension != "app",
           let development = Bundle.module.url(forResource: "LocalKokoro", withExtension: "py") {
            return development
        }
        throw Self.failure("The local voice worker is missing from this app. Reinstall Leaf or rebuild its app bundle.")
    }

    func environment(offline: Bool) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["UV_PYTHON_INSTALL_DIR"] = root.appendingPathComponent("python").path
        env["UV_CACHE_DIR"] = root.appendingPathComponent("cache/uv").path
        env["HF_HOME"] = root.appendingPathComponent("cache/huggingface").path
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["DO_NOT_TRACK"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        env["HF_HUB_OFFLINE"] = offline ? "1" : "0"
        return env
    }

    func refresh() {
        installation = nil
        guard FileManager.default.isExecutableFile(atPath: python.path),
              let data = try? Data(contentsOf: root.appendingPathComponent("ready.json")),
              let report = try? JSONDecoder().decode(LocalKokoroInstallation.self, from: data),
              report.version == 1, report.revision == Self.revision,
              !report.voices.isEmpty, report.audioSeconds.isFinite, report.audioSeconds > 0,
              report.generationSeconds.isFinite, report.generationSeconds > 0,
              FileManager.default.fileExists(atPath: root.appendingPathComponent("model/kokoro-v1_0.safetensors").path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("model/config.json").path),
              report.voices.allSatisfy({ FileManager.default.fileExists(atPath: root.appendingPathComponent("model/voices/\($0).safetensors").path) }) else { return }
        installation = report
    }

    func install() {
        guard !isInstalling, compatibility.supported else { return }
        isInstalling = true
        error = nil
        installTask = Task {
            defer { isInstalling = false; installTask = nil }
            do { try await performInstall() }
            catch is CancellationError { stage = "Setup cancelled. You can retry when ready." }
            catch { self.error = error.localizedDescription; stage = "Setup incomplete. Retry to continue." }
        }
    }

    func cancelInstall() { installTask?.cancel() }

    // Used by Settings and the integration verifier; a successful marker is written
    // only after actual offline-capable speech generation has passed.
    func performInstall() async throws {
        guard compatibility.supported else { throw Self.failure(compatibility.message) }
        LocalKokoroWorker.shared.stop()
        installation = nil
        try? FileManager.default.removeItem(at: root.appendingPathComponent("ready.json"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        stage = "Downloading the private voice runtime…"
        let archive = root.appendingPathComponent("uv.tar.gz")
        let uv = root.appendingPathComponent("uv-aarch64-apple-darwin/uv")
        if !FileManager.default.isExecutableFile(atPath: uv.path) {
            let url = URL(string: "https://github.com/astral-sh/uv/releases/download/0.9.5/uv-aarch64-apple-darwin.tar.gz")!
            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == "dc098ff224d78ed418e121fd374f655949d2c7031a70f6f6604eaf016a130433" else {
                throw Self.failure("The runtime download could not be verified. Please retry.")
            }
            try data.write(to: archive, options: .atomic)
            _ = try await LocalCommand.execute(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", root.path], environment: environment(offline: false))
            try? FileManager.default.removeItem(at: archive)
        }
        stage = "Preparing Python for local speech…"
        if !FileManager.default.isExecutableFile(atPath: python.path) {
            _ = try await LocalCommand.execute(uv, ["venv", "--python", "3.12", "--managed-python", root.appendingPathComponent("runtime").path], environment: environment(offline: false))
        }
        stage = "Installing the speech engine…"
        let requirements = try workerURL().deletingLastPathComponent().appendingPathComponent("LocalKokoro.requirements.txt")
        guard FileManager.default.fileExists(atPath: requirements.path) else {
            throw Self.failure("The local voice requirements are missing. Reinstall Leaf or rebuild its app bundle.")
        }
        _ = try await LocalCommand.execute(uv, ["pip", "install", "--python", python.path,
                                               "--requirement", requirements.path], environment: environment(offline: false))
        stage = "Downloading Kokoro and voices, then testing this Mac…"
        _ = try await LocalCommand.execute(python, [try workerURL().path, "install", root.path], environment: environment(offline: false))
        try Task.checkCancellation()
        refresh()
        guard isReady else { throw Self.failure("The model did not pass its readiness check. Retry setup.") }
        stage = "Ready for offline reading."
    }

    func remove() {
        guard !isInstalling else { return }
        LocalKokoroWorker.shared.stop()
        do {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
            installation = nil
            error = nil
            stage = "Local model removed."
        } catch { self.error = error.localizedDescription }
    }
}
