import CoreServices
import Foundation

enum LocalDictionary {
    static func definition(for term: String) -> String? {
        let text = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let range = CFRange(location: 0, length: text.utf16.count)
        guard let definition = DCSCopyTextDefinition(nil, text as CFString, range) else { return nil }
        let value = definition.takeRetainedValue() as String
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
