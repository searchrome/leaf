import Foundation
import ReaderCore

struct TextBookmark: Codable, Equatable, Identifiable {
    let id: UUID
    let chapterID: String
    let chapterIndex: Int
    let location: Int
    let length: Int
    let quote: String
    let createdAt: Date

    init(chapter: Chapter, chapterIndex: Int, range: NSRange, quote: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.chapterID = chapter.id
        self.chapterIndex = chapterIndex
        self.location = range.location
        self.length = range.length
        self.quote = quote
        self.createdAt = createdAt
    }

    var range: NSRange { NSRange(location: location, length: length) }

    func isValid(in book: Book) -> Bool {
        guard book.chapters.indices.contains(chapterIndex) else { return false }
        let chapter = book.chapters[chapterIndex]
        guard chapter.id == chapterID, location >= 0, length > 0,
              location <= chapter.text.utf16.count,
              length <= chapter.text.utf16.count - location else { return false }
        return (chapter.text as NSString).substring(with: range) == quote
    }
}

enum TextBookmarkStore {
    static let key = "textBookmarksByBook"

    static func load(bookID: String, book: Book, defaults: UserDefaults = .standard) -> [TextBookmark] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: [TextBookmark]].self, from: data) else { return [] }
        return (stored[bookID] ?? []).filter { $0.isValid(in: book) }
    }

    static func save(_ bookmarks: [TextBookmark], bookID: String, defaults: UserDefaults = .standard) {
        var all: [String: [TextBookmark]] = [:]
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [TextBookmark]].self, from: data) {
            all = decoded
        }
        all[bookID] = bookmarks
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }
}

struct DictionaryLookupResult: Identifiable, Equatable {
    enum Source: String, Equatable {
        case local = "macOS Dictionary"
        case ai = "DeepSeek via OpenRouter"
        case unavailable = "Lookup unavailable"
    }

    let id = UUID()
    let term: String
    let definition: String
    let source: Source
}
