import Foundation

public struct BreadcrumbSegment: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let range: TextRange

    public init(id: UUID = UUID(), title: String, range: TextRange) {
        self.id = id
        self.title = title
        self.range = range
    }
}

public struct BreadcrumbBarModel: Sendable {
    public let segments: [BreadcrumbSegment]

    public init(segments: [BreadcrumbSegment]) {
        self.segments = segments
    }
}
