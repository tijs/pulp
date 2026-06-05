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
}
#endif
