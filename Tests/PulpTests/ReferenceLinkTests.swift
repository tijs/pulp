import Foundation
@testable import Pulp
import Testing

/// Reference links and their definitions must not leak the ref label or the bare
/// definition URL into the rendered text.
@Suite("Reference links & definitions")
struct ReferenceLinkTests {
    private let tokenizer = MarkdownTokenizer()

    private func token(_ text: String, _ predicate: (MarkdownTokenType) -> Bool) -> MarkdownToken? {
        tokenizer.tokenize(text).first { predicate($0.type) }
    }

    @Test func referenceLinkShrinksRefLabel() {
        // `[text][ref]` must shrink the `][ref]` tail so only `text` shows — the
        // bug rendered "the Swift forumsforums" because the ref leaked.
        let doc = "see [the Swift forums][forums] here"
        let ref = token(doc) { if case .referenceLink = $0 { return true }; return false }
        #expect(ref != nil)
        let ns = doc as NSString
        // The shrunk markers must together cover `[` and `][forums]`, leaving only
        // the visible text. Reconstruct the non-marker (visible) substring.
        let markers = ref!.markerRanges
        #expect(markers.count == 2)
        let visible = visibleContent(of: ref!, in: ns)
        #expect(visible == "the Swift forums")
        #expect(!visible.contains("forums]"))
    }

    @Test func linkDefinitionUrlNotAutolinked() {
        // The URL inside a `[ref]: url` definition line must NOT become a separate
        // autolink token (it was rendering as a green link).
        let doc = "see [t][ref]\n\n[ref]: https://forums.swift.org"
        let result = tokenizer.tokenize(doc)
        #expect(result.contains { $0.type == .linkDefinition })
        #expect(!result.contains { if case .autolink = $0.type { return true }; return false })
    }

    @Test func footnoteDefinitionBodyNotInlineParsed() {
        let doc = "a[^1]\n\n[^1]: see https://example.com for more"
        let result = tokenizer.tokenize(doc)
        #expect(result.contains { $0.type == .footnoteDefinition })
        #expect(!result.contains { if case .autolink = $0.type { return true }; return false })
    }

    /// Concatenate the parts of a token's range NOT covered by any marker range —
    /// i.e. what stays visible after marker-shrinking.
    private func visibleContent(of token: MarkdownToken, in ns: NSString) -> String {
        var result = ""
        var i = token.range.location
        let end = token.range.location + token.range.length
        while i < end {
            if let marker = token.markerRanges.first(where: { $0.location <= i && i < $0.location + $0.length }) {
                i = marker.location + marker.length
            } else {
                result += ns.substring(with: NSRange(location: i, length: 1))
                i += 1
            }
        }
        return result
    }
}
