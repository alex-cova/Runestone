import Foundation

/// Presentation model for parameter hints.
public struct ParameterHintsModel: Sendable, CustomStringConvertible {
    public let signatures: [String]
    public let activeSignature: Int
    public let activeParameter: Int

    public init(
        signatures: [String],
        activeSignature: Int = 0,
        activeParameter: Int = 0
    ) {
        self.signatures = signatures
        self.activeSignature = activeSignature
        self.activeParameter = activeParameter
    }

    public var description: String {
        "ParameterHintsModel(signature: \(activeSignature), parameter: \(activeParameter))"
    }
}
