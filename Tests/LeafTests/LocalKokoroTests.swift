import AVFoundation
import XCTest
import ReaderCore
@testable import Leaf

final class LocalKokoroTests: XCTestCase {
    func testCompatibilityChecksArchitectureMemoryOSAndDisk() {
        func check(_ arm: Bool, _ memory: UInt64, _ os: Int, _ disk: Int64?) -> Bool {
            LocalSpeechCompatibility.evaluate(appleSilicon: arm, memoryGB: memory, osMajor: os, freeBytes: disk).supported
        }
        XCTAssertTrue(check(true, 8, 14, 4_000_000_000))
        XCTAssertTrue(check(true, 24, 26, nil))
        XCTAssertFalse(check(false, 32, 26, 100_000_000_000))
        XCTAssertFalse(check(true, 4, 26, 100_000_000_000))
        XCTAssertFalse(check(true, 16, 13, 100_000_000_000))
        XCTAssertFalse(check(true, 16, 14, 3_999_999_999))
    }

    @MainActor
    func testReadinessRejectsPartialAndIncompatibleInstallationAndRemovalIsScoped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leaf-kokoro-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = LocalKokoro(root: root)
        XCTAssertFalse(runtime.isReady)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("incomplete".utf8).write(to: root.appendingPathComponent("ready.json"))
        runtime.refresh()
        XCTAssertFalse(runtime.isReady)
        XCTAssertTrue(runtime.hasDownload)
        runtime.remove()
        XCTAssertFalse(runtime.hasDownload)
    }

    @MainActor
    func testMissingLocalModelFailsBeforeSpeechOrAnyCloudRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leaf-missing-kokoro-\(UUID())")
        let runtime = LocalKokoro(root: root)
        do {
            _ = try await LocalKokoroWorker.shared.generate(text: "Hello", voice: "af_heart", runtime: runtime)
            XCTFail("A missing model should fail before starting a worker")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Download and prepare"))
        }
    }

    /// Opt-in: downloads and prepares the model in Leaf's actual application-support
    /// directory. Run with LEAF_VERIFY_LOCAL_KOKORO=1 when qualifying a release.
    @MainActor
    func testFullSetupOfflineWorkerAndLocalNarration() async throws {
        guard ProcessInfo.processInfo.environment["LEAF_VERIFY_LOCAL_KOKORO"] == "1" else {
            throw XCTSkip("Opt-in model download and hardware qualification")
        }
        let runtime = LocalKokoro.shared
        try await runtime.performInstall()
        XCTAssertTrue(runtime.isReady)
        XCTAssertEqual(runtime.voices.count, 28)
        XCTAssertEqual(runtime.environment(offline: true)["HF_HUB_OFFLINE"], "1")
        let worker = LocalKokoroWorker.shared
        defer { worker.stop() }
        for voice in ["af_heart", "bf_emma"] {
            let data = try await worker.generate(text: "A little room for a good book.", voice: voice)
            XCTAssertEqual(data.prefix(4), Data("RIFF".utf8))
            XCTAssertGreaterThan(try AVAudioPlayer(data: data).duration, 0.5)
        }
        let cancelled = Task { try await worker.generate(text: String(repeating: "A longer passage to test cancellation. ", count: 100), voice: "af_heart") }
        await Task.yield()
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled local generation should not continue into playback")
        } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        // A cancelled request must not poison the next worker or leave it waiting.
        let restarted = try await worker.generate(text: "Ready to read again.", voice: "af_heart")
        XCTAssertGreaterThan(try AVAudioPlayer(data: restarted).duration, 0.5)
        worker.stop()
        let settings = SpeechSettings()
        let oldProvider = settings.provider
        let oldVoice = settings.localVoice
        defer { settings.provider = oldProvider; settings.localVoice = oldVoice }
        settings.provider = .local
        settings.localVoice = "af_heart"
        let configuration = try settings.configuration()
        XCTAssertTrue(configuration.isLocal)
        XCTAssertEqual(configuration.key, "")
        XCTAssertEqual(configuration.timingMode, .estimated)
        let passage = "Welcome to Leaf. Find a comfortable place, open a good book, and let me read to you."
        let chunk = try XCTUnwrap(CloudAlignment.narrationChunks(passage).first)
        let prepared = try await CloudNarrator.prepare(chunk, configuration: configuration)
        XCTAssertGreaterThan(try AVAudioPlayer(data: prepared.audio).duration, 0.5)
        if configuration.alignWords { XCTAssertFalse(prepared.words.isEmpty) }
        print("LOCAL_KOKORO_BENCHMARK: \(try XCTUnwrap(runtime.installation).benchmark)")
    }
}
