#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
@testable import Pulp
import Testing

/// Tests for the expanded Markdown coverage (underscore emphasis, nested lists,
/// autolinks, math, images, reference/footnote forms). See the plan at
/// docs/plans/2026-05-29-001-feat-pulp-markdown-coverage-plan.md.
@Suite("Markdown coverage")
struct MarkdownCoverageTests {
    private func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer().tokenize(text)
    }

    private func hasToken(_ text: String, _ type: MarkdownTokenType) -> Bool {
        tokens(text).contains { $0.type == type }
    }

    // MARK: - U2: Underscore emphasis

    @Test func underscoreItalic() {
        #expect(hasToken("an _italic_ word", .italic))
    }

    @Test func underscoreBold() {
        #expect(hasToken("a __bold__ word", .bold))
    }

    @Test func underscoreBoldItalic() {
        #expect(hasToken("a ___both___ word", .boldItalic))
    }

    @Test func snakeCaseNotEmphasized() {
        #expect(!hasToken("call snake_case_name here", .italic))
        #expect(!hasToken("call snake_case_name here", .bold))
    }

    @Test func pathUnderscoresNotEmphasized() {
        #expect(!hasToken("see path/to_file_name.swift", .italic))
    }

    @Test func hashtagWithUnderscoreStaysHashtag() {
        let result = tokens("see #v2_release notes")
        #expect(result.contains { $0.type == .hashtag })
        #expect(!result.contains { $0.type == .italic })
    }

    @Test func underscoreAndAsteriskMixOnOneLine() {
        let result = tokens("_em_ and **strong**")
        #expect(result.contains { $0.type == .italic })
        #expect(result.contains { $0.type == .bold })
    }

    @Test func underscoreWithInnerLeadingSpaceNotEmphasis() {
        #expect(!hasToken("a _ not italic_ b", .italic))
    }

    @Test func underscoreInsideInlineCodeNotEmphasis() {
        #expect(!hasToken("`_x_`", .italic))
    }

    @Test func emptyUnderscoresNotEmphasis() {
        #expect(!hasToken("__ ____ here", .bold))
    }

    @Test func underscoreMarkersAreShrinkable() {
        // Marker ranges must be recorded so marker-shrinking/reveal works.
        let italic = tokens("an _italic_ word").first { $0.type == .italic }
        #expect(italic?.markerRanges.count == 2)
    }

    // MARK: - U3: Nested-list indentation

    private func headIndent(for token: MarkdownToken) -> CGFloat? {
        let runs = MarkdownStyler().styleRuns(for: [token])
        for run in runs {
            if let style = run.attributes[.paragraphStyle] as? NSParagraphStyle {
                return style.headIndent
            }
        }
        return nil
    }

    @Test func topLevelBulletIsDepthZero() {
        let item = tokens("- item").first { $0.type == .listItem }
        #expect(item?.indentDepth == 0)
    }

    @Test func twoSpaceBulletIsDepthOne() {
        let item = tokens("  - nested").first { $0.type == .listItem }
        #expect(item?.indentDepth == 1)
    }

    @Test func tabIndentedBulletIsDepthOne() {
        let item = tokens("\t- tabbed").first { $0.type == .listItem }
        #expect(item?.indentDepth == 1)
    }

    @Test func nestedOrderedAndTaskCaptureDepth() {
        let ordered = tokens("  1. nested").first { $0.type == .orderedListItem }
        #expect(ordered?.indentDepth == 1)
        let task = tokens("    - [ ] deep").first { $0.type == .taskItem(checked: false) }
        #expect(task?.indentDepth == 2)
    }

    @Test func indentScalesWithDepth() {
        let top = tokens("- a").first { $0.type == .listItem }!
        let nested = tokens("    - b").first { $0.type == .listItem }!
        let topIndent = headIndent(for: top)!
        let nestedIndent = headIndent(for: nested)!
        #expect(nestedIndent > topIndent)
    }

    @Test func topLevelIndentUnchangedBaseline() {
        // Regression guard: depth-0 list keeps the original 28pt indent.
        let top = tokens("- a").first { $0.type == .listItem }!
        #expect(headIndent(for: top) == 28)
    }

    @Test func nestedUncheckedTodoStillDetected() {
        // I3 guard at the Pulp layer: derivation unaffected by nesting.
        #expect(ContentAnalyzer.hasUncheckedTodos(in: "  - [ ] nested task"))
    }

    // MARK: - U4: Autolinks

    private func hasAutolink(_ text: String, url: String) -> Bool {
        tokens(text).contains { $0.type == .autolink(url: url) }
    }

    @Test func bareHttpsURLLinkified() {
        #expect(hasAutolink("see https://example.com here", url: "https://example.com"))
    }

    @Test func bareHttpURLLinkified() {
        #expect(hasAutolink("go http://example.com now", url: "http://example.com"))
    }

    @Test func markdownLinkNotDoubleMatchedAsAutolink() {
        let result = tokens("[label](https://example.com)")
        #expect(result.contains { if case .link = $0.type { return true }; return false })
        #expect(!result.contains { if case .autolink = $0.type { return true }; return false })
    }

    @Test func trailingPeriodNotPartOfURL() {
        #expect(hasAutolink("visit https://example.com.", url: "https://example.com"))
    }

    @Test func closingParenNotSwallowed() {
        #expect(hasAutolink("(see https://example.com)", url: "https://example.com"))
    }

    @Test func balancedParensInURLKept() {
        #expect(hasAutolink("https://en.wikipedia.org/wiki/Foo_(bar) end",
                            url: "https://en.wikipedia.org/wiki/Foo_(bar)"))
    }

    @Test func urlInsideInlineCodeNotLinkified() {
        #expect(!tokens("`https://example.com`").contains { if case .autolink = $0.type { return true }; return false })
    }

    // MARK: - U5: Math

    @Test func inlineMathRecognized() {
        let math = tokens("euler $x^2 + y^2$ here").first { $0.type == .inlineMath }
        #expect(math != nil)
        #expect(math?.markerRanges.count == 2)
    }

    @Test func blockMathRecognized() {
        let math = tokens("$$\n\\int_0^1 f(x)dx\n$$").first { $0.type == .blockMath }
        #expect(math != nil)
    }

    @Test func currencyNotMath() {
        #expect(!tokens("it cost $5 and $10 today").contains { $0.type == .inlineMath })
    }

    @Test func mathInsideInlineCodeNotMath() {
        #expect(!tokens("`$x$`").contains { $0.type == .inlineMath })
    }

    @Test func unbalancedDollarNotMath() {
        #expect(!tokens("a lone $ here").contains { $0.type == .inlineMath })
    }

    @Test func underscoreInsideBlockMathNotEmphasis() {
        // Block math content (LaTeX) must render raw — `_` is a subscript, not italic.
        #expect(!tokens("$$\na_{ij} + b_{kl}\n$$").contains { $0.type == .italic })
    }

    // MARK: - U6: Images

    @Test func imageRecognized() {
        let img = tokens("![alt](https://x/y.png)").first { if case .image = $0.type { return true }; return false }
        #expect(img != nil)
        #expect(img?.markerRanges.count == 4)
    }

    @Test func imageNotParsedAsLink() {
        let result = tokens("![alt](https://x/y.png)")
        #expect(!result.contains { if case .link = $0.type { return true }; return false })
    }

    @Test func plainLinkNotParsedAsImage() {
        let result = tokens("[alt](https://x/y)")
        #expect(result.contains { if case .link = $0.type { return true }; return false })
        #expect(!result.contains { if case .image = $0.type { return true }; return false })
    }

    @Test func imageWithEmptyAltRecognized() {
        #expect(tokens("![](https://x/y.png)").contains { if case .image = $0.type { return true }; return false })
    }

    @Test func bangWithoutBracketsIsPlainText() {
        #expect(!tokens("hello! not an image").contains { if case .image = $0.type { return true }; return false })
    }

    @Test func imageInsideCodeNotParsed() {
        #expect(!tokens("`![a](b)`").contains { if case .image = $0.type { return true }; return false })
    }

    @Test func imageAndLinkOnSameLine() {
        let result = tokens("![img](a.png) and [link](b)")
        #expect(result.contains { if case .image = $0.type { return true }; return false })
        #expect(result.contains { if case .link = $0.type { return true }; return false })
    }

    // MARK: - U7: reference links, footnotes (setext headings intentionally dropped)

    private func headingLevels(_ text: String) -> [Int] {
        tokens(text).compactMap { if case let .heading(level) = $0.type { return level }; return nil }
    }

    @Test func setextUnderlineNotTreatedAsHeading() {
        // Setext headings are unsupported (Bear ignores them): `Title\n===` is just
        // two normal text lines — no heading is derived from the underline.
        #expect(headingLevels("Title\n===").isEmpty)
        #expect(headingLevels("Title\n---").isEmpty)
    }

    @Test func dashRuleStaysHorizontalRule() {
        // `---` on its own line is a horizontal rule.
        #expect(tokens("\n---").contains { $0.type == .horizontalRule })
    }

    @Test func bulletListUnderTextStaysListItem() {
        let result = tokens("text\n- item")
        #expect(result.contains { $0.type == .listItem })
    }

    @Test func tableSeparatorStaysTable() {
        let result = tokens("| a | b |\n| --- | --- |\n| 1 | 2 |")
        #expect(result.contains { if case .table = $0.type { return true }; return false })
    }

    @Test func referenceLinkRecognized() {
        let result = tokens("see [text][ref] here")
        #expect(result.contains { if case .referenceLink = $0.type { return true }; return false })
    }

    @Test func linkDefinitionRecognized() {
        #expect(tokens("[ref]: https://example.com").contains { $0.type == .linkDefinition })
    }

    @Test func footnoteReferenceRecognized() {
        let result = tokens("a claim[^1] here")
        #expect(result.contains { $0.type == .footnoteReference })
    }

    @Test func footnoteDefinitionRecognized() {
        #expect(tokens("[^1]: the note").contains { $0.type == .footnoteDefinition })
    }

    @Test func footnoteDefinitionNotAlsoReference() {
        let result = tokens("[^1]: the note")
        #expect(result.contains { $0.type == .footnoteDefinition })
        #expect(!result.contains { $0.type == .footnoteReference })
    }

    // MARK: - Review fixes: inline-math exemption, ReDoS, depth on paragraph path

    @Test func inlineMathExemptFromEmphasis() {
        // Content inside `$…$` is LaTeX, not markdown — no emphasis/strike/link.
        #expect(!tokens("a $a*b*c$ d").contains { $0.type == .italic })
        #expect(!tokens("a $a*b*c$ d").contains { $0.type == .bold })
        #expect(!tokens("a $a~~b~~c$ d").contains { $0.type == .strikethrough })
        #expect(!tokens("a $[x](y)$ d").contains { if case .link = $0.type { return true }; return false })
    }

    @Test func twoInlineMathSpansOnOneLine() {
        let result = tokens("$x$ and $y$").filter { $0.type == .inlineMath }
        #expect(result.count == 2)
    }

    @Test func cjkUnderscoreNotEmphasized() {
        // Intra-word underscore protection must be Unicode-aware, not ASCII-only.
        #expect(!tokens("一_字_二").contains { $0.type == .italic })
    }

    @Test func bracketHeavyInputDoesNotHang() {
        // Guard against quadratic backtracking on unclosed-bracket input. Bounded
        // regexes keep this near-instant; an unbounded `[^\]]+` would stall.
        let pathological = String(repeating: "[^", count: 20_000)
        let result = MarkdownTokenizer().tokenize(pathological)
        #expect(result.allSatisfy { $0.range.location >= 0 })
    }

    @Test func tokenizeParagraphPreservesIndentDepth() {
        // The paragraph-scoped entry point must not flatten nested-list depth.
        let para = "    - deeply nested"
        let result = MarkdownTokenizer().tokenizeParagraph(para, paragraphRange: NSRange(location: 0, length: (para as NSString).length))
        let item = result.first { $0.type == .listItem }
        #expect(item?.indentDepth == 2)
    }

    @Test func listDepthIsClamped() {
        // Pathological indentation must not produce unbounded depth.
        let item = tokens(String(repeating: " ", count: 400) + "- x").first { $0.type == .listItem }
        #expect(item?.indentDepth == 8)
    }

    // MARK: - Review fixes: styler-level assertions for new token types

    private func styleAttributes(_ token: MarkdownToken, _ key: NSAttributedString.Key) -> Any? {
        for run in MarkdownStyler().styleRuns(for: [token]) where run.attributes[key] != nil {
            return run.attributes[key]
        }
        return nil
    }

    @Test func autolinkStyledWithUnderline() {
        let token = tokens("see https://example.com x").first { if case .autolink = $0.type { return true }; return false }!
        #expect(styleAttributes(token, .underlineStyle) != nil)
    }

    @Test func inlineMathStyledWithCodeFont() {
        let token = tokens("a $x^2$ b").first { $0.type == .inlineMath }!
        #expect(styleAttributes(token, .font) != nil)
    }

    @Test func orderedListMarkerRangeIsTheNumber() {
        // Marker must cover "1. " so the styler colors the right glyphs.
        let token = tokens("1. item").first { $0.type == .orderedListItem }!
        #expect(token.markerRanges.count == 1)
        #expect(token.markerRanges.first?.length == 3)
        #expect(token.markerRanges.first?.location == 0)
    }
}
