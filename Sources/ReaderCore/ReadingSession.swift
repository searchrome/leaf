import Foundation

public struct Chapter: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let text: String

    public init(id: String, title: String, text: String) {
        self.id = id
        self.title = title
        self.text = text
    }
}

public struct Book {
    public let title: String
    public let author: String
    public let chapters: [Chapter]

    public init(title: String, author: String, chapters: [Chapter]) {
        self.title = title
        self.author = author
        self.chapters = chapters
    }
}

/// Every offset is UTF-16, shared by NSString, TextKit, and Apple speech callbacks.
/// Pages are presentation only: one utterance spans the remainder of a chapter.
public struct ReadingSession {
    public enum State: Equatable { case idle, speaking, paused, finished }
    public private(set) var state: State = .idle
    public private(set) var generation = UUID()
    public private(set) var chapter = 0
    public private(set) var offset = 0
    public private(set) var utteranceStart = 0
    public private(set) var utteranceLength = 0
    public private(set) var highlightedRange: NSRange?

    public init() {}

    public mutating func begin(chapter: Int, offset: Int, textLength: Int) -> UUID {
        generation = UUID()
        self.chapter = chapter
        self.offset = max(0, min(offset, textLength))
        utteranceStart = self.offset
        utteranceLength = textLength - self.offset
        highlightedRange = nil
        state = utteranceLength > 0 ? .speaking : .finished
        return generation
    }

    @discardableResult
    public mutating func word(_ relative: NSRange, generation token: UUID) -> NSRange? {
        guard token == generation, state == .speaking,
              relative.location != NSNotFound, relative.location >= 0,
              relative.length > 0, relative.location <= utteranceLength,
              relative.length <= utteranceLength - relative.location else { return nil }
        let absolute = NSRange(location: utteranceStart + relative.location, length: relative.length)
        guard absolute.location >= offset else { return nil }
        offset = absolute.location
        highlightedRange = absolute
        return absolute
    }

    public mutating func pause() { if state == .speaking { state = .paused } }
    public mutating func resume() { if state == .paused { state = .speaking } }

    public mutating func cancel() {
        generation = UUID()
        state = .idle
        highlightedRange = nil
    }

    /// Cancelled or stale completion events must never advance the book.
    public mutating func finish(generation token: UUID) -> Bool {
        guard token == generation, state == .speaking else { return false }
        state = .finished
        offset = utteranceStart + utteranceLength
        highlightedRange = nil
        return true
    }

    public static func page(containing offset: Int, in pages: [NSRange]) -> Int {
        guard !pages.isEmpty else { return 0 }
        return pages.firstIndex { NSLocationInRange(offset, $0) } ?? (offset >= NSMaxRange(pages.last!) ? pages.count - 1 : 0)
    }
}
