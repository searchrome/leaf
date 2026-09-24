import SwiftUI
import AppKit
import ReaderCore

@main
struct LeafApp: App {
    @StateObject private var reader = ReaderModel()
    var body: some Scene {
        WindowGroup("Leaf") {
            ReaderView(reader: reader)
                .frame(minWidth: 850, minHeight: 600)
                .onOpenURL { reader.load($0) }
        }
        .defaultSize(width: 1140, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open EPUB…", action: reader.openBook).keyboardShortcut("o")
            }
            CommandMenu("Reading") {
                Button(reader.isReading ? "Pause" : "Read aloud", action: reader.toggleReading).keyboardShortcut(" ", modifiers: [])
                Button("Next page") { reader.turnPage(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Previous page") { reader.turnPage(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            }
        }
    }
}

private let ink = Color(red: 0.17, green: 0.24, blue: 0.20)
private let green = Color(red: 0.22, green: 0.37, blue: 0.29)
private let paper = Color(red: 0.98, green: 0.97, blue: 0.94)

struct ReaderView: View {
    @ObservedObject var reader: ReaderModel
    @ObservedObject var speech: SpeechSettings

    init(reader: ReaderModel) {
        self.reader = reader
        self.speech = reader.speechSettings
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Divider().opacity(0.45)
                GeometryReader { geo in
                    let width = min(640.0, geo.size.width - 100)
                    let height = max(150.0, geo.size.height - 76)
                    VStack(spacing: 0) {
                        PageText(text: reader.pageText, fontSize: reader.fontSize, highlight: reader.localHighlight)
                            .frame(width: width, height: height)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { reader.resize(CGSize(width: width, height: height)) }
                    .onChange(of: geo.size) { _ in reader.resize(CGSize(width: width, height: height)) }
                }
                footer
            }
            .background(paper)
        }
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .alert("Leaf needs your attention", isPresented: Binding(get: { reader.error != nil && !reader.showSettings }, set: { if !$0 { reader.error = nil } })) {
            Button("OK") { reader.error = nil }
        } message: { Text(reader.error ?? "") }
        .overlay {
            if reader.isImporting {
                ZStack {
                    paper.opacity(0.9)
                    ProgressView("Opening your book…").controlSize(.large)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "leaf.fill").font(.system(size: 25)).foregroundStyle(green)
                Text("leaf").font(.system(size: 30, weight: .semibold, design: .serif))
            }.padding(.top, 44).padding(.bottom, 32)
            Button(action: reader.openBook) {
                Label("Open a book", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 9)
            }.buttonStyle(.bordered).controlSize(.large).disabled(reader.isImporting)
            Text("ON YOUR DESK").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary).padding(.top, 35)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 37, weight: .ultraLight)).foregroundStyle(Color(red: 0.85, green: 0.87, blue: 0.72))
                .frame(width: 90, height: 120)
                .background(green.gradient, in: RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.13), radius: 7, x: 3, y: 5).padding(.top, 19)
            Text(reader.book.title).font(.system(size: 17, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true).padding(.top, 19)
            Text(reader.book.author).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 5)
            Divider().padding(.vertical, 24)
            Text("CONTENTS").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(Array(reader.book.chapters.enumerated()), id: \.element.id) { index, chapter in
                        Button { reader.selectChapter(index) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).opacity(0.55)
                                Text(chapter.title).font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == reader.chapterIndex ? green.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 12)
            }
            Spacer(minLength: 16)
            Label("A little space to slow down.", systemImage: "sun.max")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 22)
        }
        .padding(.horizontal, 24)
        .frame(width: 222)
        .background(Color(red: 0.93, green: 0.93, blue: 0.89))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("CHAPTER \(reader.chapterIndex + 1) OF \(reader.book.chapters.count)")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                Text(reader.chapter.title).font(.system(size: 14, weight: .medium, design: .serif)).lineLimit(1)
            }
            Spacer()
            Button { reader.showSettings.toggle() } label: {
                Image(systemName: "textformat.size").font(.system(size: 17)).frame(width: 38, height: 34)
            }.buttonStyle(.plain).help("Reading settings").accessibilityLabel("Reading settings")
                .sheet(isPresented: $reader.showSettings) { ReadingSettingsView(reader: reader, speech: speech) }
        }.padding(.horizontal, 38).padding(.top, 28).padding(.bottom, 22)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Circle().fill(reader.isReading ? green : green.opacity(0.25)).frame(width: 6, height: 6)
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(reader.progress * 100))% through book").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                HStack(spacing: 13) {
                    Button { reader.turnPage(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(reader.chapterIndex == 0 && reader.pageIndex == 0).accessibilityLabel("Previous page")
                    Text("\(reader.pageIndex + 1) / \(reader.pages.count)").font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    Button { reader.turnPage(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(reader.chapterIndex == reader.book.chapters.count - 1 && reader.pageIndex == reader.pages.count - 1).accessibilityLabel("Next page")
                }.buttonStyle(.plain).frame(width: 125, alignment: .leading)
                Spacer()
                Button(action: reader.toggleReading) {
                    Label(reader.isReading ? "Pause" : reader.state == .paused ? "Resume" : "Read aloud", systemImage: reader.isReading ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .medium)).frame(width: 118).padding(.vertical, 12)
                        .foregroundStyle(.white).background(green, in: Capsule())
                }.buttonStyle(.plain).help("Read or pause (Space)")
                Spacer()
                Text(String(format: "%.2g× · %@", reader.rate, speech.provider == .openRouter ? speech.voice : "Mac voice")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 125, alignment: .trailing)
            }
            GeometryReader { geometry in
                Capsule().fill(green.opacity(0.1)).overlay(alignment: .leading) {
                    Capsule().fill(green.opacity(0.65)).frame(width: geometry.size.width * reader.progress)
                }
            }.frame(height: 3)
        }.padding(.horizontal, 38).padding(.bottom, 24).padding(.top, 12)
    }

    private var status: String {
        if reader.preparingCloud { return reader.state == .paused ? "Paused · preparing your cloud voice" : "Preparing your OpenRouter voice…" }
        if reader.isPreviewing { return "Previewing your OpenRouter voice" }
        if speech.provider == .openRouter, speech.wordHighlighting, reader.state == .speaking,
           speech.timingMode == .estimated || reader.cloudNotice != nil { return "Listening with you · estimated word following" }
        switch reader.state {
        case .speaking: return speech.provider == .openRouter && !speech.wordHighlighting ? "Listening with you · word highlighting is off" : "Listening with you · words follow the voice"
        case .paused: return "Paused · your place is saved here"
        case .finished: return "You’ve reached the end of this book"
        case .idle:
            if speech.provider == .openRouter { return speech.hasKey ? "Ready to read with \(speech.voice) · OpenRouter" : "Add your OpenRouter key in Reading settings" }
            return "Read at your pace, or let your Mac read to you"
        }
    }

}

struct PageText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let highlight: NSRange?

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = true
        view.setAccessibilityLabel("Book page")
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        if view.string != text || view.font?.pointSize != fontSize {
            view.textStorage?.setAttributedString(Pagination.attributed(text, fontSize: fontSize))
        }
        let entire = NSRange(location: 0, length: (text as NSString).length)
        view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: entire)
        if let highlight, NSMaxRange(highlight) <= entire.length {
            view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.77, green: 0.85, blue: 0.62, alpha: 0.9), forCharacterRange: highlight)
        }
    }
}
