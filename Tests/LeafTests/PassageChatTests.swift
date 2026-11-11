import XCTest
import ReaderCore
@testable import Leaf

final class PassageChatTests: XCTestCase {
    @MainActor
    func testFollowupsKeepPassageAndHistoryAndUseSelectedModel() async throws {
        let settings = SpeechSettings()
        let original = settings.chatModel
        defer { settings.chatModel = original }
        settings.chatModel = "custom/chat"
        var requests: [[PassageChatMessage]] = []
        let chat = PassageChatModel(passage: "Selected text", settings: settings, voiceID: "", rate: 1,
                                    key: { "test-placeholder" }) { passage, messages, model, _ in
            XCTAssertEqual(passage, "Selected text")
            XCTAssertEqual(model, "custom/chat")
            requests.append(messages)
            return "Answer \(requests.count)"
        }
        chat.draft = "Question one"
        chat.send()
        try await finish(chat)
        chat.draft = "Question two"
        chat.send()
        try await finish(chat)
        XCTAssertEqual(requests.map(\.count), [1, 3])
        XCTAssertEqual(requests[1].map(\.content), ["Question one", "Answer 1", "Question two"])
        XCTAssertEqual(chat.messages.count, 4)
        XCTAssertEqual(chat.draft, "")
        chat.close()
    }

    @MainActor
    func testFailureKeepsQuestionForRetryAndDoesNotPolluteHistory() async throws {
        let chat = PassageChatModel(passage: "Selected text", settings: SpeechSettings(), voiceID: "", rate: 1,
                                    key: { "test-placeholder" }) { _, _, _, _ in
            throw URLError(.notConnectedToInternet)
        }
        chat.draft = "Explain this"
        chat.send()
        try await finish(chat)
        XCTAssertEqual(chat.draft, "Explain this")
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNotNil(chat.error)
        XCTAssertTrue(chat.canSend)
    }

    @MainActor
    func testCloseRejectsLateReplyAndKeepsDraft() async throws {
        var continuation: CheckedContinuation<String, Never>?
        let chat = PassageChatModel(passage: "Selected text", settings: SpeechSettings(), voiceID: "", rate: 1,
                                    key: { "test-placeholder" }) { _, _, _, _ in
            await withCheckedContinuation { continuation = $0 }
        }
        chat.draft = "Explain this"
        chat.send()
        for _ in 0..<100 {
            if continuation != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let pending = try XCTUnwrap(continuation)
        chat.close()
        pending.resume(returning: "Late answer")
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(chat.isThinking)
        XCTAssertNil(chat.pendingQuestion)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.draft, "Explain this")
    }

    @MainActor
    func testMissingKeyDoesNotSendOrDiscardQuestion() {
        let chat = PassageChatModel(passage: "Selected text", settings: SpeechSettings(), voiceID: "", rate: 1,
                                    key: { throw URLError(.userAuthenticationRequired) }) { _, _, _, _ in
            XCTFail("Missing key must not send a request")
            return ""
        }
        chat.draft = "Explain"
        chat.send()
        XCTAssertFalse(chat.isThinking)
        XCTAssertEqual(chat.draft, "Explain")
        XCTAssertNotNil(chat.error)
    }

    @MainActor
    func testChatCapturesSelectionAndStopsBookNarration() throws {
        let suite = "leaf-chat-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = ReaderModel(restorePosition: false, defaults: defaults)
        reader.selectionChanged(pageLocal: NSRange(location: 0, length: 8))
        let selection = reader.selectedText
        reader.state = .speaking
        reader.chatAboutSelectedText()
        let chat = try XCTUnwrap(reader.passageChat)
        XCTAssertEqual(chat.passage, selection)
        XCTAssertFalse(reader.isReading)
        reader.selectionChanged(pageLocal: NSRange(location: 10, length: 5))
        XCTAssertEqual(chat.passage, selection)
        chat.close()
    }

    @MainActor
    func testListenAndStopUseMacVoiceWithoutChangingConversation() {
        let settings = SpeechSettings()
        let original = settings.provider
        defer { settings.provider = original }
        settings.provider = .mac
        let chat = PassageChatModel(passage: "Selected text", settings: settings, voiceID: "", rate: 1)
        let answer = PassageChatMessage(role: .assistant, content: "A short answer for the reader.")
        chat.listen(answer)
        XCTAssertEqual(chat.speakingMessageID, answer.id)
        XCTAssertFalse(chat.preparingAudio)
        chat.listen(answer)
        XCTAssertNil(chat.speakingMessageID)
        XCTAssertTrue(chat.messages.isEmpty)
        chat.listen(answer)
        chat.close()
        XCTAssertNil(chat.speakingMessageID)
    }

    @MainActor
    func testEmptyQuestionDoesNotReadKeyOrSend() {
        let chat = PassageChatModel(passage: "Selected text", settings: SpeechSettings(), voiceID: "", rate: 1,
                                    key: { XCTFail("Empty questions must not read the key"); return "" }) { _, _, _, _ in
            XCTFail("Empty questions must not send")
            return ""
        }
        chat.draft = "   \n"
        chat.send()
        XCTAssertFalse(chat.isThinking)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNil(chat.error)
    }

    @MainActor
    func testQuickPromptsSendImmediatelyWithPassageAndFollowupHistory() async throws {
        var requests: [[PassageChatMessage]] = []
        let chat = PassageChatModel(passage: "Selected passage", settings: SpeechSettings(), voiceID: "", rate: 1,
                                    key: { "test-placeholder" }) { passage, messages, _, _ in
            XCTAssertEqual(passage, "Selected passage")
            requests.append(messages)
            return "Prepared answer"
        }
        for prompt in PassageChatModel.QuickPrompt.allCases {
            XCTAssertTrue(chat.canSendQuickPrompt)
            chat.sendQuickPrompt(prompt)
            XCTAssertTrue(chat.isThinking)
            XCTAssertEqual(chat.pendingQuestion, prompt.question)
            // An additional click while the first request is pending must not send or replace it.
            chat.sendQuickPrompt(.summarize)
            XCTAssertEqual(chat.pendingQuestion, prompt.question)
            try await finish(chat)
            XCTAssertEqual(requests.last?.last?.content, prompt.question)
        }
        XCTAssertEqual(requests.map(\.count), [1, 3, 5, 7])
        XCTAssertEqual(chat.messages.count, 8)
    }

    @MainActor
    private func finish(_ chat: PassageChatModel) async throws {
        for _ in 0..<100 {
            if !chat.isThinking { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Chat request did not finish")
    }
}
