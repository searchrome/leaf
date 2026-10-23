import Foundation

struct LibraryBook: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var author: String
    var bookmark: Data?
    var chapterIndex: Int
    var pageIndex: Int
    var lastOpened: Date

    func resolvedURL() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        return URL(string: id)
    }
}

@MainActor
enum BookLibraryStore {
    static let key = "bookLibrary"

    static func load(defaults: UserDefaults) -> [LibraryBook] {
        guard let data = defaults.data(forKey: key),
              let books = try? JSONDecoder().decode([LibraryBook].self, from: data) else { return [] }
        var seen = Set<String>()
        return books.filter { $0.chapterIndex >= 0 && $0.pageIndex >= 0 && seen.insert($0.id).inserted }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    static func save(_ books: [LibraryBook], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(books) { defaults.set(data, forKey: key) }
    }
}
