import Foundation

/// One private child process, communicating through pipes; no network listener.
@MainActor
final class LocalKokoroWorker {
    static let shared = LocalKokoroWorker()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]

    func stop() {
        let old = process
        process = nil
        (old?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if old?.isRunning == true { old?.terminate() }
        try? input?.close()
        input = nil
        buffer.removeAll()
        failPending(CancellationError())
    }

    private func failPending(_ error: Error) {
        let requests = pending.values
        pending.removeAll()
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        for continuation in requests { continuation.resume(throwing: error) }
    }

    private func start(_ runtime: LocalKokoro) throws {
        if process?.isRunning == true { return }
        stop()
        let child = Process()
        child.executableURL = runtime.python
        child.arguments = [try runtime.workerURL().path, "serve", runtime.root.path]
        child.environment = runtime.environment(offline: true)
        let stdin = Pipe(), stdout = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, let child, self.process === child else { return }
                if data.isEmpty { handle.readabilityHandler = nil; return }
                self.receive(data)
            }
        }
        child.terminationHandler = { [weak self] child in
            Task { @MainActor in
                guard let self, self.process === child else { return }
                self.process = nil
                self.failPending(LocalKokoro.failure("The local voice stopped unexpectedly. Retry, or reinstall Kokoro in Reading settings."))
            }
        }
        process = child
        do { try child.run() } catch { stop(); throw error }
        input = stdin.fileHandleForWriting
    }

    func generate(text: String, voice: String, runtime selectedRuntime: LocalKokoro? = nil) async throws -> Data {
        let runtime = selectedRuntime ?? LocalKokoro.shared
        guard runtime.isReady, !runtime.isInstalling else { throw LocalKokoro.failure("Download and prepare Kokoro in Reading settings first.") }
        guard runtime.voices.contains(voice) else { throw LocalKokoro.failure("Choose an installed local voice in Reading settings.") }
        try Task.checkCancellation()
        try start(runtime)
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 180_000_000_000) } catch { return }
                    guard let self, self.pending[id] != nil else { return }
                    self.failPending(LocalKokoro.failure("Local speech took too long. Try a shorter passage or a Mac voice."))
                    self.stop()
                }
                do {
                    var data = try JSONSerialization.data(withJSONObject: ["id": id, "text": text, "voice": voice])
                    data.append(10)
                    guard let input else { throw LocalKokoro.failure("The local voice is not connected. Try playback again.") }
                    try input.write(contentsOf: data)
                } catch { failPending(error); stop() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.pending[id] != nil { self?.stop() }
            }
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 20_000_000 else { failPending(LocalKokoro.failure("Local voice returned oversized audio.")); stop(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: String],
                  let id = object["id"], let request = pending.removeValue(forKey: id) else { continue }
            timeouts.removeValue(forKey: id)?.cancel()
            if let encoded = object["audio"], let audio = Data(base64Encoded: encoded), !audio.isEmpty {
                request.resume(returning: audio)
            } else { request.resume(throwing: LocalKokoro.failure(object["error"] ?? "Local speech generation failed.")) }
        }
    }
}
