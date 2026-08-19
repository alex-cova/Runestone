import Foundation

/// Fold provider that derives regions from tree-sitter syntax nodes.
final class TreeSitterLineFoldProvider: LineFoldProvider {
    weak var languageMode: TreeSitterInternalLanguageMode?

    private var cachedLineCount = -1
    private var eventsByLine: [[LineFoldEvent]] = []

    func invalidate() {
        cachedLineCount = -1
        eventsByLine = []
    }

    func foldEvents(
        atLine lineIndex: Int,
        previousDepth: Int,
        in lineManager: LineManager,
        stringView: StringView
    ) -> [LineFoldEvent] {
        rebuildIfNeeded(lineCount: lineManager.lineCount)
        guard lineIndex < eventsByLine.count else {
            return []
        }
        return eventsByLine[lineIndex]
    }
}

private extension TreeSitterLineFoldProvider {
    private func rebuildIfNeeded(lineCount: Int) {
        guard lineCount != cachedLineCount else {
            return
        }
        cachedLineCount = lineCount
        eventsByLine = Array(repeating: [], count: max(lineCount, 0))
        guard let languageMode, let rootNode = languageMode.rootSyntaxNode, lineCount > 0 else {
            return
        }

        var regions: [(Int, Int)] = []
        collectFoldRegions(from: rootNode, into: &regions)

        var depthAtLine = Array(repeating: 0, count: lineCount)
        for region in regions where region.1 > region.0 {
            for line in (region.0 + 1)...min(region.1, lineCount - 1) {
                depthAtLine[line] += 1
            }
        }

        var currentDepth = 0
        for line in 0..<lineCount {
            let lineDepth = depthAtLine[line]
            var events: [LineFoldEvent] = []
            if lineDepth < currentDepth {
                events.append(.endFold(depth: lineDepth))
            }
            let nextDepth = line + 1 < lineCount ? depthAtLine[line + 1] : 0
            if nextDepth > lineDepth {
                events.append(.startFold(depth: nextDepth))
            }
            eventsByLine[line] = events
            currentDepth = lineDepth
        }
    }

    private func collectFoldRegions(from node: TreeSitterNode, into regions: inout [(Int, Int)]) {
        let startRow = Int(node.startPoint.row)
        let endRow = Int(node.endPoint.row)
        if isFoldable(node), endRow > startRow {
            regions.append((startRow, max(startRow, endRow - 1)))
        }
        for index in 0..<node.childCount {
            if let child = node.child(at: index) {
                collectFoldRegions(from: child, into: &regions)
            }
        }
    }

    private func isFoldable(_ node: TreeSitterNode) -> Bool {
        guard let type = node.type, node.childCount > 0 else {
            return false
        }
        if type.contains("comment") || type == "ERROR" || type == "program" {
            return false
        }
        let foldableHints = [
            "block", "body", "function", "class", "method", "struct", "enum",
            "interface", "namespace", "module", "switch", "try", "catch", "statement"
        ]
        return foldableHints.contains(where: { type.contains($0) })
    }
}
