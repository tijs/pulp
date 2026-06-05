#if canImport(AppKit)
import AppKit
@testable import Pulp
import Testing

/// Inline math must read as math, not as inline code. These assert the styler
/// produces a visually distinct treatment (no code font, no code background).
@Suite("Math styling")
@MainActor
struct MathStylingTests {
    private let styler = MarkdownStyler()
    private let tokenizer = MarkdownTokenizer()

    private func contentAttributes(_ text: String, type: MarkdownTokenType) -> [NSAttributedString.Key: Any]? {
        let tokens = tokenizer.tokenize(text)
        guard let token = tokens.first(where: { $0.type == type }) else { return nil }
        // The widest run for the token's content carries the visible styling.
        return styler.styleRuns(for: [token])
            .max(by: { $0.range.length < $1.range.length })?
            .attributes
    }

    @Test func inlineMathIsNotCodeFont() {
        let mathFont = contentAttributes("a $x^2$ b", type: .inlineMath)?[.font] as? PulpFont
        let codeFont = contentAttributes("a `x` b", type: .inlineCode)?[.font] as? PulpFont
        #expect(mathFont != nil)
        #expect(codeFont != nil)
        // Math is not the monospaced code font.
        #expect(mathFont?.fontName != codeFont?.fontName)
    }

    @Test func inlineMathFontIsItalic() {
        // Guards against a silent italic fallback making math read as prose again.
        let mathFont = contentAttributes("a $x^2$ b", type: .inlineMath)?[.font] as? PulpFont
        #expect(mathFont != nil)
        #expect(mathFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test func inlineMathHasNoCodeBackground() {
        let attrs = contentAttributes("a $x^2$ b", type: .inlineMath)
        #expect(attrs?[.backgroundColor] == nil)
    }

    @Test func inlineMathUsesAccentColor() {
        let color = contentAttributes("a $x^2$ b", type: .inlineMath)?[.foregroundColor] as? PulpColor
        #expect(color == MarkdownStyler().theme.accentColor)
    }

    @Test func blockMathShrinksWholeDelimiterLines() {
        // The opening `$$` line shrinks fully (delimiter + newline = 3 chars) so no
        // stray blank line remains; the closing marker covers at least the `$$`
        // (its trailing newline is clipped when it sits at the token's end).
        let doc = "x\n$$\na = b\n$$\ny"
        let token = tokenizer.tokenize(doc).first { $0.type == .blockMath }
        #expect(token != nil)
        #expect(token?.markerRanges.count == 2)
        // Opening marker covers the whole `$$\n` line (not just the 2 `$$` chars).
        #expect(token?.markerRanges.first?.length == 3)
        #expect(token?.markerRanges.allSatisfy { $0.length >= 2 } == true)
    }

    @Test func blockMathContentIsCenteredDisplay() {
        let doc = "$$\na = b\n$$"
        let token = tokenizer.tokenize(doc).first { $0.type == .blockMath }!
        let runs = styler.styleRuns(for: [token])
        let para = runs.compactMap { $0.attributes[.paragraphStyle] as? NSParagraphStyle }.first
        #expect(para?.alignment == .center)
    }

    @Test func singleLineBlockMathKeepsContentVisible() {
        // `$$a = b$$` on one line must NOT shrink its whole line (which would hide
        // the content); only the `$$` delimiters shrink.
        let doc = "$$a = b$$"
        let token = tokenizer.tokenize(doc).first { $0.type == .blockMath }
        #expect(token != nil)
        // Both markers are just the 2-char `$$` delimiters, not the whole line.
        #expect(token?.markerRanges.allSatisfy { $0.length == 2 } == true)
    }

    @Test func blockMathMarkersStayWithinToken() {
        // Markers must never extend past the token range into the next paragraph.
        let doc = "x\n$$\na = b\n$$\ny"
        let token = tokenizer.tokenize(doc).first { $0.type == .blockMath }!
        let tokenEnd = token.range.location + token.range.length
        for marker in token.markerRanges {
            #expect(marker.location >= token.range.location)
            #expect(marker.location + marker.length <= tokenEnd)
        }
    }

    @Test func multilineBlockMathKeepsAllContentLines() {
        // A genuinely multi-line $$ body must tokenize as one block spanning all
        // its lines (so every line renders, none dropped).
        let doc = "$$\na = b\nc = d\n$$"
        let token = tokenizer.tokenize(doc).first { $0.type == .blockMath }
        #expect(token != nil)
        let ns = doc as NSString
        let covered = ns.substring(with: token!.range)
        #expect(covered.contains("a = b"))
        #expect(covered.contains("c = d"))
    }
}
#endif
