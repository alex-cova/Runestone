import Foundation

/// Immutable context shared across an editor instance and the EIP.
///
/// This value is created once per editor and passed to providers, ranking, and the workspace.
public struct EditorContext: Hashable, Sendable {
    public let adapterID: EditorAdapterID
    public let rootProjectURL: URL?
    public let userInfo: [String: String]

    public init(
        adapterID: EditorAdapterID = EditorAdapterID(),
        rootProjectURL: URL? = nil,
        userInfo: [String: String] = [:]
    ) {
        self.adapterID = adapterID
        self.rootProjectURL = rootProjectURL
        self.userInfo = userInfo
    }

    public func with(rootProjectURL: URL?) -> EditorContext {
        EditorContext(adapterID: adapterID, rootProjectURL: rootProjectURL, userInfo: userInfo)
    }

    public func with(userInfo: [String: String]) -> EditorContext {
        EditorContext(adapterID: adapterID, rootProjectURL: rootProjectURL, userInfo: userInfo)
    }
}
