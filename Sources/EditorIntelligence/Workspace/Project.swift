import Foundation

/// A project in the workspace.
public struct Project: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let name: String

    public init(id: UUID = UUID(), url: URL, name: String) {
        self.id = id
        self.url = url
        self.name = name
    }
}