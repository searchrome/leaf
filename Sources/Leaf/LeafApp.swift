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
                Button(reader.isListeningView ? "Exit listening view" : "Open listening view") {
                    reader.toggleListeningView()
                }
                .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
                .disabled(!reader.isListeningView && !reader.canOpenListeningView)
                Divider()
                Button("Bookmark Selected Text", action: reader.bookmarkSelectedText).disabled(!reader.hasTextSelection)
                Button("Look Up Selected Text", action: reader.lookUpSelectedText).disabled(!reader.hasTextSelection)
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
        .alert("Leaf needs your attention", isPresented: Binding(get: { reader.error != nil && !reader.showSettings }, set: { if !$0 { reader.error = nil } })) {
            Button("OK") { reader.error = nil }
        } message: { Text(reader.error ?? "") }
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
                }.buttonStyle(.plain).help("Read or pause (Space)")
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

private struct ListeningExperience: View {
    @ObservedObject var reader: ReaderModel

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { reader.dismissListeningView() }
            cornerOrnaments
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(reader.book.title.uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(green.opacity(0.78))
                    Text(reader.chapter.title)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                }
                .padding(.top, 44)
                Spacer(minLength: 24)
                Text(reader.listeningSentence)
                    .id(reader.listeningSentenceID)
                    .font(.system(size: sentenceFontSize, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(12)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: 1_000, maxHeight: .infinity)
                    .padding(.horizontal, 80)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeInOut(duration: 0.28), value: reader.listeningSentenceID)
                Spacer(minLength: 24)
                HStack(spacing: 16) {
                    Image(systemName: reader.isReading ? "speaker.wave.2.fill" : "pause.circle.fill")
                    Text(reader.isReading ? "Listening" : "Paused")
                    Text("Click anywhere to exit")
                    Text("F5 also exits fullscreen").opacity(0.72)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(green.opacity(0.86))
                .padding(.bottom, 34)
            }
            .contentShape(Rectangle())
        }
        .onTapGesture { reader.dismissListeningView() }
        .onExitCommand { reader.dismissListeningView() }
    }

    private var cornerOrnaments: some View {
        ZStack {
            ornament("leaf.fill", alignment: .topLeading, rotation: -25)
            ornament("leaf.fill", alignment: .topTrailing, rotation: 35)
            ornament("sparkles", alignment: .bottomLeading, rotation: 0)
            ornament("sparkles", alignment: .bottomTrailing, rotation: 0)
        }
        .allowsHitTesting(false)
    }

    private func ornament(_ name: String, alignment: Alignment, rotation: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: 54, weight: .ultraLight))
            .foregroundStyle(green.opacity(0.12))
            .rotationEffect(.degrees(rotation))
            .padding(42)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var sentenceFontSize: CGFloat {
        switch reader.listeningSentence.count {
        case ..<90: return 64
        case ..<170: return 52
        case ..<280: return 42
        default: return 34
        }
    }
}

private struct DictionaryLookupView: View {
    let result: DictionaryLookupResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.term).font(.system(size: 24, weight: .medium, design: .serif))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text(result.source.rawValue.uppercased())
                .font(.caption.weight(.semibold)).tracking(1.1).foregroundStyle(.secondary)
            ScrollView {
                Text(result.definition)
                    .font(.system(size: 15, design: .serif))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(26)
        .frame(width: 480, height: 330)
        .background(paper)
    }
}

struct PageText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let highlight: NSRange?
    let bookmarks: [NSRange]
    let selectedBookmark: NSRange?
    let selectedBookmarkID: UUID?
    let onSeek: (Int) -> Void
    let onSelection: (NSRange) -> Void
    let onBookmarkHit: (Int) -> Bool
    let onRemoveBookmark: () -> Void
    let onBookmark: () -> Void
    let onLookup: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PageText
        var updatingView = false

        init(_ parent: PageText) { self.parent = parent }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updatingView else { return }
            guard let view = notification.object as? NSTextView else { return }
            parent.onSelection(view.selectedRange())
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class SeekTextView: NSTextView {
        var onSeek: ((Int) -> Void)?
        var onBookmarkHit: ((Int) -> Bool)?
        var onBookmark: (() -> Void)?
        var onLookup: (() -> Void)?
        var onRemoveBookmark: (() -> Void)?
        var removalRange: NSRange?
        private(set) lazy var removeButton: NSButton = {
            let button = NSButton(title: "×", target: self, action: #selector(removeSelectedBookmark))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.cgColor
            button.layer?.cornerRadius = 6
            button.contentTintColor = .selectedTextColor
            button.font = .systemFont(ofSize: 18, weight: .semibold)
            button.toolTip = "Remove this bookmark"
            button.setAccessibilityLabel("Remove selected bookmark")
            addSubview(button)
            return button
        }()

        @objc private func removeSelectedBookmark() { onRemoveBookmark?() }

        func positionRemoveButton() {
            guard let range = removalRange, range.length > 0,
                  NSMaxRange(range) <= (string as NSString).length,
                  let layoutManager, let container = textContainer else {
                removeButton.isHidden = true
                return
            }
            layoutManager.ensureLayout(for: container)
            let glyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            removeButton.frame = NSRect(
                x: min(max(0, rect.maxX + textContainerOrigin.x + 4), max(0, bounds.width - 26)),
                y: min(max(0, rect.midY + textContainerOrigin.y - 13), max(0, bounds.height - 26)),
                width: 26, height: 26)
            removeButton.isHidden = false
        }

        override func layout() {
            super.layout()
            positionRemoveButton()
        }
        var displayedBookmarkID: UUID?
        var bookmarkRanges: [NSRange] = []
        private var downPoint: NSPoint?

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if event.clickCount == 1, !event.modifierFlags.contains(.shift),
               let index = characterAtPoint(point),
               let range = bookmarkRanges.first(where: { NSLocationInRange(index, $0) }),
               onBookmarkHit?(index) == true {
                window?.makeFirstResponder(self)
                setSelectedRange(range)
                downPoint = nil
                return
            }
            downPoint = point
            super.mouseDown(with: event)
        }

        /// Hit the glyph itself, not the nearest insertion position in blank space.
        func characterAtPoint(_ point: NSPoint) -> Int? {
            guard let layoutManager, let container = textContainer, !string.isEmpty else { return nil }
            layoutManager.ensureLayout(for: container)
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = layoutManager.glyphIndex(for: local, in: container)
            guard glyph < layoutManager.numberOfGlyphs,
                  layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
            return layoutManager.characterIndexForGlyph(at: glyph)
        }

        override func mouseUp(with event: NSEvent) {
            defer { downPoint = nil }
            let upPoint = convert(event.locationInWindow, from: nil)
            let dragged = downPoint.map { abs($0.x - upPoint.x) > 3 || abs($0.y - upPoint.y) > 3 } ?? true
            if !dragged {
                var fraction = CGFloat(0)
                if let layoutManager, let container = textContainer {
                    var index = layoutManager.characterIndex(for: upPoint, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
                    let length = (string as NSString).length
                    if index != NSNotFound, index >= length { index = max(0, length - 1) }
                    if index != NSNotFound, index >= 0 {
                        if onBookmarkHit?(index) == true {
                            super.mouseUp(with: event)
                            return
                        }
                        onSeek?(index)
                    }
                }
            }
            super.mouseUp(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = super.menu(for: event) ?? NSMenu()
            guard selectedRange().length > 0 else { return menu }
            let bookmark = NSMenuItem(title: "Bookmark Selected Text", action: #selector(bookmarkSelection), keyEquivalent: "")
            bookmark.target = self
            let lookup = NSMenuItem(title: "Look Up Selected Text", action: #selector(lookUpSelection), keyEquivalent: "")
            lookup.target = self
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(lookup, at: 0)
            menu.insertItem(bookmark, at: 0)
            return menu
        }

        @objc private func bookmarkSelection() { onBookmark?() }
        @objc private func lookUpSelection() { onLookup?() }
    }

    func makeNSView(context: Context) -> NSTextView {
        let view = SeekTextView()
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
        view.onSeek = onSeek
        view.onBookmarkHit = onBookmarkHit
        view.bookmarkRanges = bookmarks
        view.onBookmark = onBookmark
        view.onLookup = onLookup
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.updatingView = true
        defer { context.coordinator.updatingView = false }
        context.coordinator.parent = self
        if let seekView = view as? SeekTextView {
            seekView.onSeek = onSeek
            seekView.onBookmarkHit = onBookmarkHit
            seekView.bookmarkRanges = bookmarks
            seekView.onBookmark = onBookmark
            seekView.onLookup = onLookup
            seekView.onRemoveBookmark = onRemoveBookmark
            seekView.removalRange = selectedBookmark
        }
        if view.string != text || view.font?.pointSize != fontSize {
            view.textStorage?.setAttributedString(Pagination.attributed(text, fontSize: fontSize))
        }
        if let seekView = view as? SeekTextView, seekView.displayedBookmarkID != selectedBookmarkID {
            seekView.displayedBookmarkID = selectedBookmarkID
            if let selectedBookmark { view.setSelectedRange(selectedBookmark) }
        }
        let entire = NSRange(location: 0, length: (text as NSString).length)
        view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: entire)
        for bookmark in bookmarks where bookmark.location >= 0 && NSMaxRange(bookmark) <= entire.length {
            view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.94, green: 0.88, blue: 0.55, alpha: 0.55), forCharacterRange: bookmark)
        }
        if let highlight, NSMaxRange(highlight) <= entire.length {
            view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.77, green: 0.85, blue: 0.62, alpha: 0.9), forCharacterRange: highlight)
        }
        (view as? SeekTextView)?.positionRemoveButton()
    }
}
