import AppKit
import AVFoundation
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ReaderModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var book = Demo.book
    @Published var chapterIndex = 0
    @Published var pageIndex = 0
    @Published var pages = [NSRange(location: 0, length: 0)]
    @Published var highlight: NSRange?
    @Published var state: ReadingSession.State = .idle
    @Published var fontSize: CGFloat = 21
    @Published var rate: Float = 1
    @Published var voiceID = ""
    @Published var error: String?
    @Published var cloudNotice: String?
    @Published var isImporting = false
    @Published var showSettings = false
    @Published var preparingCloud = false
    @Published var isPreviewing = false
    let speechSettings = SpeechSettings()
    private let cloud = CloudNarrator()
    private var usingCloud = false
    let voices = AVSpeechSynthesisVoice.speechVoices().sorted { $0.name < $1.name }
    private var session = ReadingSession()
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private var activeGeneration: UUID?
    private var utteranceSentenceRanges: [NSRange] = []
    private var deferredCompletion = false
    private var viewport = CGSize(width: 580, height: 570)
    private var importTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
        repaginate()
    }

    var chapter: Chapter { book.chapters[chapterIndex] }
    var pageRange: NSRange { pages[min(pageIndex, pages.count - 1)] }
    var pageText: String { (chapter.text as NSString).substring(with: pageRange) }
    var isReading: Bool { state == .speaking }
    var progress: Double { (Double(chapterIndex) + Double(pageIndex + 1) / Double(max(1, pages.count))) / Double(book.chapters.count) }
    var localHighlight: NSRange? {
        guard let highlight else { return nil }
        let intersection = NSIntersectionRange(highlight, pageRange)
        guard intersection.length > 0 else { return nil }
        return NSRange(location: intersection.location - pageRange.location, length: intersection.length)
    }

    func resize(_ size: CGSize) {
        let next = CGSize(width: max(200, size.width), height: max(150, size.height))
        guard abs(next.width - viewport.width) > 1 || abs(next.height - viewport.height) > 1 else { return }
        viewport = next
        repaginate()
    }

    func repaginate() {
        let anchor = (state == .speaking || state == .paused) && session.chapter == chapterIndex ? session.offset : pageRange.location
        pages = Pagination.pages(for: chapter.text, fontSize: fontSize, size: viewport)
        pageIndex = ReadingSession.page(containing: anchor, in: pages)
    }

    func toggleReading() {
        switch state {
        case .speaking:
            session.pause()
            state = session.state
            if usingCloud { cloud.pause() } else { synthesizer.pauseSpeaking(at: .immediate) }
        case .paused:
            session.resume()
            state = session.state
            if deferredCompletion {
                deferredCompletion = false
                completeChapter()
            } else {
                if usingCloud { cloud.resume() } else { synthesizer.continueSpeaking() }
            }
        case .idle, .finished:
            speak(from: pageRange.location)
        }
    }

    func stop() {
        session.cancel()
        activeUtterance = nil
        activeGeneration = nil
        utteranceSentenceRanges = []
        deferredCompletion = false
        synthesizer.stopSpeaking(at: .immediate)
        cloud.stop()
        preparingCloud = false
        isPreviewing = false
        usingCloud = false
        highlight = nil
        state = .idle
    }

    func selectChapter(_ index: Int) {
        guard book.chapters.indices.contains(index) else { return }
        stop()
        chapterIndex = index
        pageIndex = 0
        pages = [NSRange(location: 0, length: 0)]
        repaginate()
    }

    func turnPage(_ direction: Int) {
        stop()
        let next = pageIndex + direction
        if next < 0, chapterIndex > 0 {
            selectChapter(chapterIndex - 1)
            pageIndex = pages.count - 1
        } else if next >= pages.count, chapterIndex < book.chapters.count - 1 {
            selectChapter(chapterIndex + 1)
        } else { pageIndex = min(max(next, 0), pages.count - 1) }
    }

    func updateVoice() {
        let anchor = highlight?.location ?? pageRange.location
        let wasReading = isReading
        stop()
        if wasReading { speak(from: anchor) }
    }

    func updateRate() {
        if usingCloud { cloud.setRate(rate) } else { updateVoice() }
    }

    func previewCloudVoice() {
        if isPreviewing { stop(); return }
        stop()
        do {
            let configuration = try speechSettings.configuration(preview: true)
            usingCloud = true
            isPreviewing = true
            cloud.start(text: "Welcome to Leaf. Find a comfortable place, open a good book, and let me read to you.",
                        configuration: configuration, rate: rate, onWord: { _ in },
                        onFinish: { [weak self] in self?.stop() },
                        onPreparing: { [weak self] in self?.preparingCloud = $0 },
                        onError: { [weak self] error in self?.stop(); self?.error = error.localizedDescription })
        } catch { self.error = error.localizedDescription }
    }

    private func speak(from offset: Int) {
        stop()
        cloudNotice = nil
        let text = chapter.text as NSString
        let token = session.begin(chapter: chapterIndex, offset: offset, textLength: text.length)
        activeGeneration = token
        state = session.state
        if speechSettings.provider == .openRouter {
            do {
                let configuration = try speechSettings.configuration()
                usingCloud = true
                cloud.start(text: text.substring(from: session.utteranceStart), configuration: configuration, rate: rate,
                            onWord: { [weak self] range in
                                guard let self, self.activeGeneration == token else { return }
                                if let range, let absolute = self.session.word(range, generation: token) {
                                    self.highlight = self.speechSettings.wordHighlighting ? absolute : nil
                                    self.pageIndex = ReadingSession.page(containing: absolute.location, in: self.pages)
                                } else if range == nil, self.state == .speaking { self.highlight = nil }
                            },
                            onFinish: { [weak self] in
                                guard let self, self.activeGeneration == token else { return }
                                if self.state == .paused { self.deferredCompletion = true }
                                else { self.completeChapter() }
                            },
                            onPreparing: { [weak self] preparing in
                                guard let self, self.activeGeneration == token else { return }
                                self.preparingCloud = preparing
                            },
                            onError: { [weak self] error in
                                guard let self, self.activeGeneration == token else { return }
                                self.stop()
                                self.error = error.localizedDescription
                            }, onWarning: { [weak self] warning in
                                guard let self, self.activeGeneration == token else { return }
                                self.cloudNotice = warning
                                self.highlight = nil
                            })
            } catch { stop(); self.error = error.localizedDescription; showSettings = true }
            return
        }
        let utterance = AVSpeechUtterance(string: text.substring(from: session.utteranceStart))
        utterance.voice = voiceID.isEmpty ? AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en") : AVSpeechSynthesisVoice(identifier: voiceID)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        utteranceSentenceRanges = speechSettings.highlightGranularity == .sentence
            ? CloudAlignment.sentenceRanges(text.substring(from: session.utteranceStart))
            : []
        activeUtterance = utterance
        activeGeneration = token
        state = session.state
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.activeUtterance, let token = self.activeGeneration else { return }
            var spoken = range
            if !self.utteranceSentenceRanges.isEmpty,
               let sentence = self.utteranceSentenceRanges.first(where: { $0.location <= range.location && NSMaxRange(range) <= NSMaxRange($0) }) {
                spoken = sentence
            }
            guard let absolute = self.session.word(spoken, generation: token) else { return }
            self.highlight = absolute
            self.pageIndex = ReadingSession.page(containing: absolute.location, in: self.pages)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard utterance === self.activeUtterance else { return }
            // A pause click can race the final audio frame. Advance only after Resume.
            if self.state == .paused { self.deferredCompletion = true; return }
            self.completeChapter()
        }
    }

    private func completeChapter() {
        guard let token = activeGeneration, session.finish(generation: token) else { return }
        highlight = nil
        if chapterIndex + 1 < book.chapters.count {
            chapterIndex += 1
            pageIndex = 0
            pages = [NSRange(location: 0, length: 0)]
            repaginate()
            speak(from: 0)
        } else {
            activeUtterance = nil
            activeGeneration = nil
            state = .finished
        }
    }

    func openBook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    func load(_ url: URL) {
        stop()
        importTask?.cancel()
        isImporting = true
        importTask = Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) { try EPUBImporter.load(url) }.value
                guard !Task.isCancelled else { return }
                book = imported
                chapterIndex = 0
                pageIndex = 0
                pages = [NSRange(location: 0, length: 0)]
                repaginate()
                isImporting = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isImporting = false
            }
        }
    }
}

enum Demo {
    static let book = Book(title: "A quieter kind of reading", author: "Welcome to Leaf", chapters: [
        Chapter(id: "welcome", title: "A little room for a good book", text: """
        A little room for a good book

        There is a particular pleasure in opening a book when the rest of the world has grown quiet. A chair by the window. A little afternoon light. A sentence that asks for nothing except your attention.

        Leaf is a place for that kind of reading. Open an EPUB, find your page, and settle in. When you would rather listen, press Read aloud. The voice begins on the page in front of you, and a small green highlight follows each spoken word.

        You do not have to keep turning pages. As the story continues, Leaf moves with it, from page to page and chapter to chapter. Press Pause whenever you need a moment. Press Resume when you are ready to return.

        The default voice belongs to your Mac. Your book stays on this computer, and reading aloud does not require an account or an internet connection. You can choose another installed voice or adjust the pace in Reading settings.

        Try resizing this window while the voice is reading. The page can change its shape, but your place stays anchored to the words. A long word, a curly quotation mark, even a café on a rainy afternoon: the highlight follows the text itself.

        This little introduction has a second chapter so you can try continuous reading before opening your own book. Leave the voice running, and it will take you there.

        Outside the window, a branch moved in the wind. Somewhere a kettle clicked off. There was time for another page.
        """),
        Chapter(id: "next", title: "One more page", text: """
        One more page

        And here we are. The next chapter arrived without a click.

        Good tools should leave room for the thing you came to do. For a reader, that means clear type, comfortable space, and a voice that knows where you are.

        Use the arrows below to browse pages yourself. Choosing another page or chapter pauses the voice, so you can explore at your own pace. Read aloud will then begin at the top of that page.

        Now open a book of your own. There is always another story waiting.
        """)
    ])
}
