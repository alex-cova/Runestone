import Foundation
import XCTest
import RunestoneMarkdownLanguage
import TreeSitter
import TreeSitterMarkdown
import TreeSitterMarkdownInline
@testable import Runestone

final class MarkdownLanguageTests: XCTestCase {
    func testMarkdownLanguageCanBeCreated() {
        let language = TreeSitterLanguage.markdown
        XCTAssertNotNil(language.highlightsQuery)
        XCTAssertNotNil(language.injectionsQuery)
    }

    func testMarkdownInlineLanguageCanBeCreated() {
        let language = TreeSitterLanguage.markdownInline
        XCTAssertNotNil(language.highlightsQuery)
        XCTAssertNotNil(language.injectionsQuery)
    }

    func testMarkdownParserProducesTree() {
        let text: NSString = "# Hello\n\nThis is **bold** text.\n"
        let parser = TreeSitterParser(encoding: .treeSitterUTF16)
        parser.language = TreeSitterLanguagePointer(tree_sitter_markdown())
        let tree = parser.parse(text)
        XCTAssertNotNil(tree)
        XCTAssertFalse(tree?.rootNode.expressionString?.isEmpty ?? true)
    }

    func testMarkdownInlineParserProducesTree() {
        let text: NSString = "This is **bold** and _italic_ with a [link](https://example.com)."
        let parser = TreeSitterParser(encoding: .treeSitterUTF16)
        parser.language = TreeSitterLanguagePointer(tree_sitter_markdown_inline())
        let tree = parser.parse(text)
        XCTAssertNotNil(tree)
        XCTAssertFalse(tree?.rootNode.expressionString?.isEmpty ?? true)
    }

    func testMarkdownHighlightCaptures() {
        let text = "# Heading\n\n* item one\n* item two\n"
        let languageMode = makeMarkdownLanguageMode(text: text)
        let byteRange = ByteRange(from: 0, to: (text as NSString).byteCount)
        let captures = languageMode.captures(in: byteRange)
        let names = Set(captures.map { $0.name })

        XCTAssertTrue(names.contains("punctuation.special"), "Expected punctuation.special capture for the heading/list markers")
    }

    func testMarkdownInlineInjectionIsResolvedThroughLanguageProvider() {
        let text = "# Hello **World**\n"
        let languageMode = makeMarkdownLanguageMode(text: text, languageProvider: MarkdownLanguageProvider())
        let byteRange = ByteRange(from: 0, to: (text as NSString).byteCount)
        let captures = languageMode.captures(in: byteRange)
        let names = Set(captures.map { $0.name })

        XCTAssertTrue(names.contains("markup.heading"), "Expected markup.heading capture from the block grammar")
        XCTAssertTrue(names.contains("markup.bold"), "Expected markup.bold capture from the injected markdown_inline grammar")
    }

    func testMarkdownLanguageProviderResolvesMarkdownInline() {
        let provider = MarkdownLanguageProvider()
        XCTAssertNotNil(provider.treeSitterLanguage(named: "markdown_inline"))
        XCTAssertNil(provider.treeSitterLanguage(named: "html"))
    }

    private func makeMarkdownLanguageMode(text: String, languageProvider: TreeSitterLanguageProvider? = nil) -> TreeSitterInternalLanguageMode {
        let language = TreeSitterLanguage.markdown
        let stringView = StringView(string: text)
        let lineManager = LineManager(stringView: stringView)
        lineManager.rebuild()
        let languageMode = TreeSitterInternalLanguageMode(
            language: language.internalLanguage,
            languageProvider: languageProvider,
            stringView: stringView,
            lineManager: lineManager)
        languageMode.parse(text as NSString)
        return languageMode
    }
}
