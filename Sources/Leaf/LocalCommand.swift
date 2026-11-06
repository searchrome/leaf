import Foundation

/// A cancellable subprocess. Output is drained off the main thread, including stderr.
final class LocalCommand: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
    }

    private func run(_ executable: URL, arguments: [String], environment: [String: String]) throws -> Data {
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        var tail = Data()
        while let part = try output.fileHandleForReading.read(upToCount: 65_536), !part.isEmpty {
            tail.append(part)
            if tail.count > 32_768 { tail = Data(tail.suffix(32_768)) }
        }
        process.waitUntilExit()
        lock.lock()
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: tail.suffix(1800), as: UTF8.self)
            throw LocalKokoro.failure("Local voice setup failed. Check your internet connection and retry.\n\(detail)")
        }
        return tail
    }

    static func execute(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> Data {
        let command = LocalCommand()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try command.run(executable, arguments: arguments, environment: environment)
            }.value
        } onCancel: { command.cancel() }
    }
}
