import Foundation

/// Request/response types for the EIP foundation.
public struct EditorRequest: Hashable, Sendable {
    public let documentID: DocumentID
    public let cursor: Cursor
    public let trigger: RequestTrigger

    public init(documentID: DocumentID, cursor: Cursor, trigger: RequestTrigger) {
        self.documentID = documentID
        self.cursor = cursor
        self.trigger = trigger
    }
}

public enum RequestTrigger: Hashable, Sendable {
    case manual
    case keystroke(String)
    case idle
}

public struct EditorResponse<T: Sendable>: Sendable {
    public let requestID: UUID
    public let documentID: DocumentID
    public let result: T

    public init(requestID: UUID, documentID: DocumentID, result: T) {
        self.requestID = requestID
        self.documentID = documentID
        self.result = result
    }
}
