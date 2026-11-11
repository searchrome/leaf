import Foundation

public struct PassageChatMessage: Codable, Equatable, Identifiable {
    public enum Role: String, Codable { case user, assistant }
    public let id: UUID
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        id = UUID()
        self.role = role
        self.content = content
    }
}
