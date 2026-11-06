import SwiftUI
import AppKit
import ReaderCore

struct ReaderView: View {
    @ObservedObject var reader: ReaderModel
    @ObservedObject var speech: SpeechSettings
    @State private var bookmarksExpanded = false
    @State private var listeningViewEnteredFullscreen = false

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
                        PageText(
                            text: reader.pageText,
                            fontSize: reader.fontSize,
                            highlight: reader.localHighlight,
                            bookmarks: reader.bookmarkLocalRanges,
                            selectedBookmark: reader.selectedBookmarkLocalRange,
                            selectedBookmarkID: reader.selectedBookmark?.id,
                            onSeek: { local in reader.seek(pageLocal: local) },
                            onSelection: { range in reader.selectionChanged(pageLocal: range) },
                            onBookmarkHit: { local in reader.selectBookmark(atPageLocal: local) },
                            onRemoveBookmark: {
                                if let bookmark = reader.selectedBookmark { reader.removeBookmark(bookmark) }
                            },
                            onBookmark: reader.bookmarkSelectedText,
                            onLookup: reader.lookUpSelectedText)
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
        .alert("Leaf needs your attention", isPresented: Binding(get: { reader.error != nil && !reader.showSettings && !reader.showLibrary }, set: { if !$0 { reader.error = nil } })) {
            Button("OK") { reader.error = nil }
        } message: { Text(reader.error ?? "") }
        .sheet(isPresented: $reader.showLibrary) { BookLibraryView(reader: reader) }
        .sheet(item: $reader.lookupResult) { result in
            DictionaryLookupView(result: result)
        }
        .overlay {
            if reader.isImporting {
                ZStack {
                    paper.opacity(0.9)
                    ProgressView("Opening your book…").controlSize(.large)
                }
            }
        }
        .overlay {
            if reader.isListeningView {
                ListeningExperience(reader: reader)
                    .transition(.opacity)
            }
        }
        .onChange(of: reader.isListeningView) { active in
            syncListeningFullscreen(active)
        }
    }

    private func syncListeningFullscreen(_ active: Bool) {
        guard let window = NSApp.keyWindow else { return }
        if active, !window.styleMask.contains(.fullScreen) {
            listeningViewEnteredFullscreen = true
            window.toggleFullScreen(nil)
        } else if !active, listeningViewEnteredFullscreen, window.styleMask.contains(.fullScreen) {
            listeningViewEnteredFullscreen = false
            window.toggleFullScreen(nil)
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
            Button { reader.showLibrary = true } label: {
                HStack {
                    Label("Library", systemImage: "books.vertical")
                    Spacer()
                    Text("\(reader.library.count)").foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 8)
            .help("Previously opened books (⌘L)")
            Text("ON YOUR DESK").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary).padding(.top, 35)
            Image(systemName: "book.closed.fill")
                .font(.system(size: 37, weight: .ultraLight)).foregroundStyle(Color(red: 0.85, green: 0.87, blue: 0.72))
                .frame(width: 90, height: 120)
                .background(green.gradient, in: RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.13), radius: 7, x: 3, y: 5).padding(.top, 19)
            Text(reader.book.title).font(.system(size: 17, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true).padding(.top, 19)
            Text(reader.book.author).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 5)
            Divider().padding(.vertical, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Button { bookmarksExpanded.toggle() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: bookmarksExpanded ? "chevron.down" : "chevron.right")
                            Text("BOOKMARKS (\(reader.bookmarks.count))").tracking(1.2)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(bookmarksExpanded ? "Expanded" : "Collapsed")
                    if bookmarksExpanded {
                        if reader.bookmarks.isEmpty {
                            Text("Select text to save your first bookmark.")
                                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                        }
                        ForEach(reader.bookmarks) { bookmark in
                            HStack(alignment: .top, spacing: 5) {
                                Button { reader.openBookmark(bookmark) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("CHAPTER \(bookmark.chapterIndex + 1)")
                                            .font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
                                        Text(bookmark.quote.replacingOccurrences(of: "\n", with: " "))
                                            .font(.system(size: 11, design: .serif)).lineLimit(3).multilineTextAlignment(.leading)
                                    }
                                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(red: 0.91, green: 0.88, blue: 0.67).opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(.plain)
                                Button { reader.removeBookmark(bookmark) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 24)
                                }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Remove bookmark")
                            }
                        }
                    }
                    Divider().padding(.vertical, 12)
                    Text("CONTENTS").font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
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
            if reader.selectedBookmark == nil && reader.hasTextSelection {
                HStack(spacing: 8) {
                    Button(action: reader.bookmarkSelectedText) {
                        Label("Bookmark", systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button(action: reader.lookUpSelectedText) {
                        Label("Look Up", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(reader.isLookingUp)
                    if reader.isLookingUp { ProgressView().controlSize(.small) }
                }
            }
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
                }.buttonStyle(.plain).help("Space: read or pause. While reading, ← / → moves to the previous / next sentence.")
                if reader.canOpenListeningView {
                    Button(action: reader.toggleListeningView) {
                        Image(systemName: "rectangle.inset.filled").font(.system(size: 14, weight: .medium))
                            .frame(width: 38, height: 38).foregroundStyle(green)
                            .background(green.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain).help("Open listening view (F5)")
                    .accessibilityLabel("Open listening view")
                }
                Spacer()
                Text(String(format: "%.2g× · %@", reader.rate, speech.narrationVoice)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 125, alignment: .trailing)
            }
            GeometryReader { geometry in
                Capsule().fill(green.opacity(0.1)).overlay(alignment: .leading) {
                    Capsule().fill(green.opacity(0.65)).frame(width: geometry.size.width * reader.progress)
                }
            }.frame(height: 3)
        }.padding(.horizontal, 38).padding(.bottom, 24).padding(.top, 12)
    }

    private var status: String {
        if speech.provider == .local {
            if reader.preparingCloud { return reader.state == .paused ? "Paused · preparing local voice" : "Preparing Kokoro on this Mac…" }
            if reader.isPreviewing { return "Previewing local Kokoro" }
            switch reader.state {
            case .speaking: return speech.wordHighlighting ? "Listening locally · estimated word following" : "Listening locally with Kokoro"
            case .paused: return "Paused · your place is saved here"
            case .finished: return "You’ve reached the end of this book"
            case .idle: return LocalKokoro.shared.isReady ? "Ready to read offline with Kokoro" : "Download Kokoro in Reading settings"
            }
        }
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
