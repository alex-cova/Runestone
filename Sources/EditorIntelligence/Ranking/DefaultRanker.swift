import Foundation

/// Default ranker combining prefix, camelCase, fuzzy, provider, and kind signals.
public struct DefaultRanker: Ranker {
    public init() {}

    public func rank(items: [CompletionItem], context: CompletionContext) async -> [RankedCompletionItem] {
        let prefix = context.prefix
        let ranked = items.map { item -> RankedCompletionItem in
            let score = score(item: item, prefix: prefix)
            return RankedCompletionItem(item: item, score: score)
        }
        return ranked.sorted { $0.score > $1.score }
    }

    private func score(item: CompletionItem, prefix: String) -> Double {
        let label = item.label
        let lowerPrefix = prefix.lowercased()
        let lowerLabel = label.lowercased()
        var score: Double = 0

        if prefix.isEmpty {
            score += 0.1
        } else if label == prefix {
            score += 1.0
        } else if lowerLabel == lowerPrefix {
            score += 0.95
        } else if lowerLabel.hasPrefix(lowerPrefix) {
            score += 0.8
        } else if isCamelCaseMatch(label: label, prefix: prefix) {
            score += 0.7
        } else if lowerLabel.contains(lowerPrefix) {
            score += 0.5
        } else if isFuzzyMatch(label: label, prefix: prefix) {
            score += 0.3
        }

        score += providerWeight(item.source)
        score += kindWeight(item.kind)
        return score
    }

    private func isCamelCaseMatch(label: String, prefix: String) -> Bool {
        let upperPrefix = prefix.uppercased()
        let acronym = label.reduce("") { result, character in
            if character.isUppercase {
                return result + String(character)
            }
            return result
        }
        return acronym.hasPrefix(upperPrefix)
    }

    private func isFuzzyMatch(label: String, prefix: String) -> Bool {
        var labelIndex = label.startIndex
        for character in prefix {
            guard let matchIndex = label[labelIndex...].firstIndex(where: { $0.lowercased() == character.lowercased() }) else {
                return false
            }
            labelIndex = label.index(after: matchIndex)
        }
        return true
    }

    private func providerWeight(_ source: String) -> Double {
        switch source {
        case "Symbol":
            return 0.3
        case "Snippet":
            return 0.2
        case "Word":
            return 0.1
        default:
            return 0.0
        }
    }

    private func kindWeight(_ kind: CompletionItemKind) -> Double {
        switch kind {
        case .function, .method:
            return 0.2
        case .type:
            return 0.15
        case .property, .variable:
            return 0.1
        case .snippet:
            return 0.05
        case .keyword:
            return 0.04
        case .text:
            return 0.0
        case .module, .file:
            return 0.05
        }
    }
}
