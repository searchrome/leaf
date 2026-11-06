import Foundation

struct ReadingPosition: Codable, Equatable {
    var bookmark: Data?
    var chapterIndex: Int
    var pageIndex: Int
    var textOffset: Int? = nil
    var speechOffset: Int? = nil
    var fileURL: URL? = nil
}

@MainActor
enum ReadingPositionStore {
    static let key = "readingPosition"

    static func save(_ position: ReadingPosition, defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: key)
        }
    }

    static func load(defaults: UserDefaults) -> ReadingPosition? {
        guard let data = defaults.data(forKey: key),
              let position = try? JSONDecoder().decode(ReadingPosition.self, from: data),
              position.chapterIndex >= 0, position.pageIndex >= 0,
              (position.textOffset ?? 0) >= 0, (position.speechOffset ?? 0) >= 0 else { return nil }
        return position
    }
}
