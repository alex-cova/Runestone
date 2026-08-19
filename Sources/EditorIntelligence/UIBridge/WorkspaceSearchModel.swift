import Foundation

public struct WorkspaceSearchModel: Sendable {
    public let query: String
    public let results: [WorkspaceSearchResult]
    public let selectedIndex: Int

    public init(query: String, results: [WorkspaceSearchResult], selectedIndex: Int = 0) {
        self.query = query
        self.results = results
        self.selectedIndex = selectedIndex
    }
}
