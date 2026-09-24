import SwiftUI
import ReaderCore

struct ReadingSettingsView: View {
    @ObservedObject var reader: ReaderModel
    @ObservedObject var speech: SpeechSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Reading settings").font(.system(size: 25, weight: .medium, design: .serif))
                    Text("Make the page and the voice your own.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(26)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ON THE PAGE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack {
                            Text("Text size")
                            Slider(value: $reader.fontSize, in: 17...30, step: 1)
                            Text("\(Int(reader.fontSize)) pt").monospacedDigit().frame(width: 44)
                        }.onChange(of: reader.fontSize) { _ in reader.repaginate() }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("READ ALOUD").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("Voice provider", selection: $speech.provider) {
                            ForEach(SpeechSettings.Provider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden().onChange(of: speech.provider) { _ in reader.stop() }
                        HStack {
                            Text("Pace").frame(width: 70, alignment: .leading)
                            Picker("Reading pace", selection: $reader.rate) {
                                Text("0.8×").tag(Float(0.8)); Text("1×").tag(Float(1)); Text("1.2×").tag(Float(1.2)); Text("1.5×").tag(Float(1.5))
                            }.pickerStyle(.segmented).labelsHidden().onChange(of: reader.rate) { _ in reader.updateRate() }
                        }
                        if speech.provider == .mac {
                            Picker("Mac voice", selection: $reader.voiceID) {
                                Text("System default").tag("")
                                ForEach(reader.voices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
                            }.onChange(of: reader.voiceID) { _ in reader.updateVoice() }
                            Text("Mac voices work locally without an account.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    cloudSettings
                }.padding(26)
            }
        }
        .frame(width: 560, height: 700)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94))
        .onDisappear { speech.keyDraft = "" }
    }

    private var cloudSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OPENROUTER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Label(speech.hasKey ? "Key saved" : "No key saved", systemImage: speech.hasKey ? "checkmark.shield" : "key")
                    .font(.caption).foregroundStyle(speech.hasKey ? Color.green : Color.secondary)
            }
            HStack {
                SecureField(speech.hasKey ? "Replace API key" : "OpenRouter API key", text: $speech.keyDraft)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("OpenRouter API key")
                Button("Save key") { reader.stop(); speech.saveKey() }.disabled(speech.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Text("Stored securely in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if speech.hasKey { Button("Remove key", role: .destructive) { reader.stop(); speech.removeKey() }.font(.caption) }
                Link("Get an API key", destination: URL(string: "https://openrouter.ai/settings/keys")!).font(.caption)
            }
            Picker("Speech model", selection: Binding(get: { speech.model }, set: { speech.selectModel($0) })) {
                ForEach(speech.models) { Text($0.name).tag($0.id) }
                if !speech.models.contains(where: { $0.id == speech.model }) { Text(speech.model.isEmpty ? "Custom model" : speech.model).tag(speech.model) }
            }.onChange(of: speech.model) { _ in reader.stop() }
            HStack {
                TextField("Model ID", text: $speech.model).textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                Button(speech.loadingModels ? "Loading…" : "Refresh models") { Task { await speech.refreshModels() } }.disabled(speech.loadingModels)
            }
            HStack {
                Text("Voice").frame(width: 70, alignment: .leading)
                TextField("Voice name, e.g. Zephyr", text: $speech.voice).textFieldStyle(.roundedBorder)
                if !speech.availableVoices.isEmpty {
                    Menu("Choose") {
                        ForEach(speech.availableVoices, id: \.self) { voice in Button(voice) { speech.voice = voice } }
                    }.frame(width: 85)
                }
            }.onChange(of: speech.voice) { _ in reader.stop() }
            Toggle("Highlight while reading", isOn: $speech.wordHighlighting)
                .onChange(of: speech.wordHighlighting) { _ in reader.stop() }
            if speech.wordHighlighting {
                Picker("Highlight", selection: $speech.highlightGranularity) {
                    Text("Word by word").tag(HighlightGranularity.word)
                    Text("Whole sentences").tag(HighlightGranularity.sentence)
                }.onChange(of: speech.highlightGranularity) { _ in reader.stop() }
                Picker("Word following", selection: $speech.timingMode) {
                    Text("Fast word follow · estimated").tag(CloudWordTiming.estimated)
                    Text("Audio timestamps · extra preparation").tag(CloudWordTiming.transcribed)
                }.onChange(of: speech.timingMode) { _ in reader.stop() }
                if speech.timingMode == .estimated {
                    Text("Starts as soon as each short audio passage is ready. Word positions are estimated from audio duration, word length, and punctuation, so they may drift. No transcription request is needed.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                HStack {
                    Text("Timing model")
                    TextField("Word-timing model", text: $speech.timingModel).textFieldStyle(.roundedBorder)
                        .onChange(of: speech.timingModel) { _ in reader.stop() }
                }
                Text("Word timing uses a second OpenRouter request and adds preparation time and cost. If timings are unavailable or do not match, word following uses clearly labeled estimates instead.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("When you play a cloud voice, book text and generated audio are sent to OpenRouter and its providers. Usage is billed to your OpenRouter account.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(reader.isPreviewing ? "Stop preview" : "Preview voice") { reader.previewCloudVoice() }.disabled(!speech.hasKey)
                if reader.isPreviewing && reader.preparingCloud { ProgressView().controlSize(.small) }
                Text("A short sample; no book text.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = speech.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let notice = reader.cloudNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = reader.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                Button("Dismiss message") { reader.error = nil }.font(.caption)
            }
        }
    }
}
