#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

public final class MarkdownStyler {
    public var theme: PulpTheme

    public init(theme: PulpTheme = .default) {
        self.theme = theme
    }

    public struct StyleRun {
        public let range: NSRange
        public let attributes: [NSAttributedString.Key: Any]
    }

    public func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = theme.bodySize * 0.5
        return [
            .font: theme.bodyFont(),
            .foregroundColor: theme.textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    public func styleRuns(for tokens: [MarkdownToken]) -> [StyleRun] {
        var runs: [StyleRun] = []
        for token in tokens {
            runs.append(contentsOf: contentRuns(for: token))
            runs.append(contentsOf: markerRuns(for: token))
        }
        return runs
    }

    private func contentRuns(for token: MarkdownToken) -> [StyleRun] {
        if let inline = inlineEmphasisRuns(for: token) {
            return inline
        }
        if let linkFamily = linkFamilyRuns(for: token) {
            return linkFamily
        }
        switch token.type {
        case let .heading(level):
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacingBefore = theme.bodySize * 0.8
            paragraphStyle.paragraphSpacing = theme.bodySize * 0.3
            return [StyleRun(
                range: token.range,
                attributes: [
                    .font: theme.headingFont(level: level),
                    .foregroundColor: theme.textColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )]

        case .horizontalRule:
            return [StyleRun(
                range: token.range,
                attributes: [
                    .foregroundColor: PulpColor.clear,
                    .font: theme.markerFont(),
                ]
            )]

        case .orderedListItem:
            return orderedListRuns(token: token)

        case .inlineCode:
            return [StyleRun(
                range: token.range,
                attributes: [
                    .font: theme.codeFont(),
                    .backgroundColor: theme.codeBackgroundColor,
                ]
            )]

        case .codeBlock:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = 4
            return [StyleRun(
                range: token.range,
                attributes: [
                    .font: theme.codeFont(),
                    .paragraphStyle: paragraphStyle,
                ]
            )]

        case .hashtag:
            return [StyleRun(
                range: token.range,
                attributes: [.foregroundColor: theme.accentColor]
            )]

        case let .taskItem(checked):
            return taskItemRuns(token: token, checked: checked)

        case .blockquote:
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 20
            paragraphStyle.firstLineHeadIndent = 20
            return [StyleRun(
                range: token.range,
                attributes: [
                    .foregroundColor: theme.secondaryTextColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )]

        case .listItem:
            return listItemRuns(token: token)

        case .table:
            return [StyleRun(
                range: token.range,
                attributes: [.foregroundColor: PulpColor.clear]
            )]

        case .tableHeaderRow:
            return tableRowRuns(token: token, isHeader: true)

        case .tableSeparatorRow:
            return [StyleRun(
                range: token.range,
                attributes: [
                    .font: theme.markerFont(),
                    .foregroundColor: PulpColor.clear,
                ]
            )]

        case .tableDataRow:
            return tableRowRuns(token: token, isHeader: false)

        case .bold, .italic, .boldItalic, .strikethrough, .highlight,
             .link, .image, .autolink, .inlineMath, .blockMath,
             .referenceLink, .linkDefinition,
             .footnoteReference, .footnoteDefinition:
            return [] // handled by inlineEmphasisRuns / linkFamilyRuns
        }
    }

    /// Content styling for the link/media family and the reference/footnote
    /// forms. Returns nil for tokens it doesn't handle, so `contentRuns` falls
    /// through to its own switch. Split out of `contentRuns` to keep that method's
    /// complexity manageable as coverage grows.
    private func linkFamilyRuns(for token: MarkdownToken) -> [StyleRun]? {
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        switch token.type {
        case .link, .referenceLink:
            return [StyleRun(range: contentRange(token: token), attributes: linkAttributes)]

        case .autolink:
            // Whole span is the URL — no markers to shrink.
            return [StyleRun(range: token.range, attributes: linkAttributes)]

        case .image:
            // Recognition + styling only (no inline thumbnail — deferred). Alt
            // text is tinted; the `![`/`](url)` machinery shrinks as markers.
            // Distinguished from links by tint + no underline.
            return [StyleRun(range: contentRange(token: token), attributes: [.foregroundColor: theme.accentColor])]

        case .inlineMath:
            // Math is shown italic in the accent color — visually distinct from
            // inline code (which is monospace on a fill). Not typeset; the `$`
            // markers shrink like other inline markers.
            return [StyleRun(range: contentRange(token: token), attributes: [
                .font: italicized(theme.bodyFont()),
                .foregroundColor: theme.accentColor,
            ])]

        case .blockMath:
            // Block math styling is handled by blockMathRuns (multi-line block).
            return blockMathRuns(token: token)

        case .footnoteReference:
            // Only the id (between the shrunk `[^` / `]` markers) shows, raised as
            // a small superscript in the accent color, like Bear.
            return [StyleRun(range: contentRange(token: token), attributes: [
                .foregroundColor: theme.accentColor,
                .font: PulpFont.systemFont(ofSize: theme.bodySize * Self.footnoteReferenceScale),
                .baselineOffset: theme.bodySize * 0.35,
            ])]

        case .linkDefinition, .footnoteDefinition:
            // The marker (`[ref]:` / `[^id]:`) shrinks via markerRuns; the body
            // recedes to secondary so definitions don't compete with prose.
            return [StyleRun(range: token.range, attributes: [.foregroundColor: theme.secondaryTextColor])]

        default:
            return nil
        }
    }

    /// Style runs for a `$$…$$` block-math token. The LaTeX is not typeset; it is
    /// rendered as a distinct centered, italic, accent-tinted block so it reads as
    /// a math display rather than prose. The `$$` delimiter lines shrink to
    /// invisible via markerRuns.
    private func blockMathRuns(token: MarkdownToken) -> [StyleRun] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacingBefore = theme.bodySize * 0.6
        paragraphStyle.paragraphSpacing = theme.bodySize * 0.6
        return [StyleRun(
            range: token.range,
            attributes: [
                .font: italicized(theme.bodyFont()),
                .foregroundColor: theme.accentColor,
                .paragraphStyle: paragraphStyle,
            ]
        )]
    }

    /// Inline character emphasis applied to a token's content range. Returns nil
    /// for token types that aren't inline emphasis.
    private func inlineEmphasisRuns(for token: MarkdownToken) -> [StyleRun]? {
        let content = contentRange(token: token)
        switch token.type {
        case .bold:
            return [StyleRun(range: content, attributes: [.font: PulpFont.boldSystemFont(ofSize: theme.bodySize)])]

        case .italic:
            return [StyleRun(range: content, attributes: [.font: italicized(theme.bodyFont())])]

        case .boldItalic:
            return [StyleRun(range: content, attributes: [
                .font: italicized(PulpFont.boldSystemFont(ofSize: theme.bodySize)),
            ])]

        case .strikethrough:
            return [StyleRun(range: content, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: theme.secondaryTextColor,
            ])]

        case .highlight:
            return [StyleRun(range: content, attributes: [.backgroundColor: theme.highlightColor])]

        default:
            return nil
        }
    }

    /// Per-nesting-level indentation step, in points. Depth 0 keeps the original
    /// flat 28pt baseline so existing single-level lists are unchanged.
    static let listIndentStep: CGFloat = 24
    static let listBaseIndent: CGFloat = 28
    /// Hanging-indent gap reserved for an ordered-list number, in points.
    private static let orderedListMarkerGap: CGFloat = 20
    /// Font-size multiple for a footnote reference marker (smaller, superscript-ish).
    private static let footnoteReferenceScale: CGFloat = 0.85

    /// Text head-indent for a list/task item at the given nesting depth. Shared
    /// with the custom-drawn bullet/checkbox positioning (in PulpNSTextView) so
    /// the glyph and its text stay aligned at every depth.
    static func listIndent(depth: Int) -> CGFloat {
        listBaseIndent + CGFloat(max(0, depth)) * listIndentStep
    }

    private func listIndent(depth: Int) -> CGFloat { Self.listIndent(depth: depth) }

    private func listItemRuns(token: MarkdownToken) -> [StyleRun] {
        let indent = listIndent(depth: token.indentDepth)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = 2

        var runs: [StyleRun] = []

        runs.append(StyleRun(
            range: token.range,
            attributes: [.paragraphStyle: paragraphStyle]
        ))

        if let markerRange = token.markerRanges.first {
            runs.append(StyleRun(
                range: markerRange,
                attributes: [
                    .font: theme.markerFont(),
                    .foregroundColor: PulpColor.clear,
                ]
            ))
        }

        return runs
    }

    private func taskItemRuns(token: MarkdownToken, checked: Bool) -> [StyleRun] {
        let indent = listIndent(depth: token.indentDepth)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = 2

        var runs: [StyleRun] = []

        runs.append(StyleRun(
            range: token.range,
            attributes: [.paragraphStyle: paragraphStyle]
        ))

        guard let markerRange = token.markerRanges.first else { return runs }

        runs.append(StyleRun(
            range: markerRange,
            attributes: [
                .font: theme.markerFont(),
                .foregroundColor: PulpColor.clear,
            ]
        ))

        if checked {
            let contentStart = markerRange.location + markerRange.length
            let contentLength = token.range.length - (contentStart - token.range.location)
            if contentLength > 0 {
                runs.append(StyleRun(
                    range: NSRange(location: contentStart, length: contentLength),
                    attributes: [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: theme.secondaryTextColor,
                    ]
                ))
            }
        }

        return runs
    }

    private func tableRowRuns(token: MarkdownToken, isHeader: Bool) -> [StyleRun] {
        // Tall, fixed row height gives cells vertical breathing room. The overlay
        // draws cell text centered in this space; the invisible source occupies it.
        let rowHeight = theme.bodySize * 2.4
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.headIndent = 12
        paragraphStyle.firstLineHeadIndent = 12
        paragraphStyle.minimumLineHeight = rowHeight
        paragraphStyle.maximumLineHeight = rowHeight

        var runs: [StyleRun] = []

        let font = isHeader
            ? PulpFont.systemFont(ofSize: theme.bodySize * 0.9, weight: .semibold)
            : PulpFont.systemFont(ofSize: theme.bodySize * 0.9)

        runs.append(StyleRun(
            range: token.range,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle,
            ]
        ))

        for pipeRange in token.markerRanges {
            runs.append(StyleRun(
                range: pipeRange,
                attributes: [
                    .foregroundColor: PulpColor.clear,
                ]
            ))
        }

        return runs
    }

    private func orderedListRuns(token: MarkdownToken) -> [StyleRun] {
        let depthOffset = CGFloat(max(0, token.indentDepth)) * Self.listIndentStep
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = listIndent(depth: token.indentDepth)
        // The number hangs `orderedListMarkerGap` points left of the wrapped-text
        // indent and shifts right with depth, so the gap stays constant per level.
        paragraphStyle.firstLineHeadIndent =
            (Self.listBaseIndent - Self.orderedListMarkerGap) + depthOffset
        paragraphStyle.paragraphSpacing = 2

        var runs: [StyleRun] = []

        runs.append(StyleRun(
            range: token.range,
            attributes: [.paragraphStyle: paragraphStyle]
        ))

        if let markerRange = token.markerRanges.first {
            runs.append(StyleRun(
                range: markerRange,
                attributes: [
                    .foregroundColor: theme.accentColor,
                    .font: PulpFont.monospacedDigitSystemFont(ofSize: theme.bodySize, weight: .regular),
                ]
            ))
        }

        return runs
    }

    private func markerRuns(for token: MarkdownToken) -> [StyleRun] {
        switch token.type {
        case .listItem, .taskItem, .orderedListItem, .horizontalRule,
             .table, .tableHeaderRow, .tableDataRow, .tableSeparatorRow:
            []
        case .codeBlock:
            token.markerRanges.map { markerRange in
                StyleRun(
                    range: markerRange,
                    attributes: [
                        .font: theme.codeFont(),
                        .foregroundColor: PulpColor.clear,
                    ]
                )
            }
        default:
            token.markerRanges.map { markerRange in
                StyleRun(
                    range: markerRange,
                    attributes: [
                        .font: theme.markerFont(),
                        .foregroundColor: theme.secondaryTextColor,
                    ]
                )
            }
        }
    }

    private func contentRange(token: MarkdownToken) -> NSRange {
        guard let first = token.markerRanges.first,
              let last = token.markerRanges.last
        else {
            return token.range
        }
        let start = first.location + first.length
        let end = last.location
        guard end > start else { return token.range }
        return NSRange(location: start, length: end - start)
    }
}

private extension MarkdownStyler {
    /// Return an italic variant of `font`, preserving its other traits (e.g. bold).
    /// Falls back to the original font if the platform can't synthesize italics.
    func italicized(_ font: PulpFont) -> PulpFont {
        #if canImport(AppKit)
        let traits = font.fontDescriptor.symbolicTraits.union(.italic)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return PulpFont(descriptor: descriptor, size: font.pointSize) ?? font
        #elseif canImport(UIKit)
        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
        return PulpFont(descriptor: descriptor, size: font.pointSize)
        #else
        return font
        #endif
    }
}
