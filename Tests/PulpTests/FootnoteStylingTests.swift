#if canImport(AppKit)
import AppKit
@testable import Pulp
import Testing

/// Footnote markers should not render their `[^…]` brackets: the reference shows
/// just the id as a raised superscript; the definition reads "id: …".
@Suite("Footnote styling")
@MainActor
struct FootnoteStylingTests {
    private let styler = MarkdownStyler()
    private let tokenizer = MarkdownTokenizer()

    private func token(_ text: String, _ type: MarkdownTokenType) -> MarkdownToken? {
        tokenizer.tokenize(text).first { $0.type == type }
    }

    @Test func footnoteReferenceShrinksBrackets() {
        // `[^1]` keeps only `1` visible (the `[^` and `]` shrink).
        let ref = token("a claim[^1] here", .footnoteReference)
        #expect(ref != nil)
        #expect(ref?.markerRanges.count == 2)
        let ns = "a claim[^1] here" as NSString
        // First marker is `[^` (len 2), last is `]` (len 1).
        #expect(ref.map { ns.substring(with: $0.markerRanges[0]) } == "[^")
        #expect(ref.map { ns.substring(with: $0.markerRanges[1]) } == "]")
    }

    @Test func footnoteReferenceIsSuperscript() {
        let ref = token("a[^1]", .footnoteReference)!
        let run = styler.styleRuns(for: [ref]).first { $0.attributes[.baselineOffset] != nil }
        #expect(run != nil)
        let offset = run?.attributes[.baselineOffset] as? CGFloat
        #expect((offset ?? 0) > 0)
    }

    @Test func footnoteDefinitionKeepsIdAndColon() {
        // `[^1]: text` shrinks `[^` and the `]`, leaving "1: text" visible.
        let doc = "[^1]: the note"
        let def = token(doc, .footnoteDefinition)
        #expect(def != nil)
        #expect(def?.markerRanges.count == 2)
        let ns = doc as NSString
        #expect(def.map { ns.substring(with: $0.markerRanges[0]) } == "[^")
        #expect(def.map { ns.substring(with: $0.markerRanges[1]) } == "]")
    }

    @Test func footnoteDefinitionMarkersCorrectWhenNotFirstLine() {
        // Locks the document-coordinate offset (line.range.location + group) for a
        // definition that is not at the document start.
        let doc = "intro\n\n[^1]: the note"
        let def = token(doc, .footnoteDefinition)
        #expect(def != nil)
        let ns = doc as NSString
        #expect(def.map { ns.substring(with: $0.markerRanges[0]) } == "[^")
        #expect(def.map { ns.substring(with: $0.markerRanges[1]) } == "]")
    }
}
#endif
