import SwiftUI
import ReaderCore

struct PassageChatView: View {
    @ObservedObject var chat: PassageChatModel
    @ObservedObject var settings: SpeechSettings
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var questionFocused: Bool

    private let messageBlue = Color(red: 0.0, green: 0.44, blue: 0.95)
    private let receivedBackground = Color(red: 0.91, green: 0.92, blue: 0.94)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 23)).foregroundStyle(green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Passage chat").font(.system(size: 19, weight: .semibold))
                    Text(settings.chatModel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Settings") { chat.close(); dismiss(); openSettings() }
                Button("Done") { chat.close(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            Divider()
            conversation
            Divider()
            composer
        }
        .frame(width: 660, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { questionFocused = true }
        .onDisappear { chat.close() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected passage").font(.caption).foregroundStyle(.secondary)
                            .padding(.leading, 14)
                        bubble(chat.passage, sent: false)
                    }
                    ForEach(chat.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            bubble(message.content, sent: message.role == .user)
                            if message.role == .assistant {
                                Button { chat.listen(message) } label: {
                                    Label(chat.speakingMessageID == message.id ? "Stop listening" : "Listen",
                                          systemImage: chat.speakingMessageID == message.id ? "stop.fill" : "speaker.wave.2")
                                }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(green)
                                .padding(.leading, 14)
                            }
                        }
                    }
                    if let question = chat.pendingQuestion {
                        bubble(question, sent: true)
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(receivedBackground, in: RoundedRectangle(cornerRadius: 19))
                        .accessibilityElement(children: .combine)
                    }
                    if let error = chat.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                            .padding(12)
                    }
                    if chat.messages.count >= 40 {
                        Text("This chat has reached its limit. Close it and select a passage to start a new conversation.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ChatContentHeight.self, value: geometry.size.height)
                })
            }
            // Defer until the new bubbles have their final wrapped heights. The task is
            // replaced if another message arrives before the layout settles.
            .task(id: scrollRevision) {
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onPreferenceChange(ChatContentHeight.self) { _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var scrollRevision: String {
        "\(chat.messages.count):\(chat.pendingQuestion ?? ""):\(chat.error ?? "")"
    }

    private func bubble(_ text: String, sent: Bool) -> some View {
        HStack {
            if sent { Spacer(minLength: 64) }
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(sent ? Color.white : Color.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(sent ? messageBlue : receivedBackground,
                            in: RoundedRectangle(cornerRadius: 19))
            if !sent { Spacer(minLength: 64) }
        }
        .frame(maxWidth: .infinity, alignment: sent ? .trailing : .leading)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if chat.preparingAudio { ProgressView("Preparing answer audio…").controlSize(.small) }
            HStack(spacing: 8) {
                ForEach(PassageChatModel.QuickPrompt.allCases, id: \.self) { prompt in
                    Button { chat.sendQuickPrompt(prompt) } label: {
                        Text(prompt.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(green.opacity(0.09), in: Capsule())
                            .overlay(Capsule().strokeBorder(green.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Send: \(prompt.question)")
                    .accessibilityHint("Sends a prepared question: \(prompt.question)")
                    .disabled(!chat.canSendQuickPrompt)
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about this passage…", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).focused($questionFocused)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(receivedBackground, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.secondary.opacity(0.22)))
                    .disabled(chat.isThinking)
                    .onSubmit { chat.send() }
                Button {
                    if chat.isThinking { chat.cancelRequest() } else { chat.send() }
                } label: {
                    Image(systemName: chat.isThinking ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(messageBlue.opacity(chat.isThinking || chat.canSend ? 1 : 0.35), in: Circle())
                }
                .buttonStyle(.plain).padding(.bottom, 2)
                .disabled(!chat.isThinking && !chat.canSend)
                .accessibilityLabel(chat.isThinking ? "Cancel request" : "Send question")
                .help(chat.isThinking ? "Cancel request" : "Send question")
                .keyboardShortcut(.return, modifiers: .command)
            }
            Text("Passage and messages are sent to OpenRouter when you ask. Usage charges apply. Chat clears when closed. AI can make mistakes.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}

private struct ChatContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
