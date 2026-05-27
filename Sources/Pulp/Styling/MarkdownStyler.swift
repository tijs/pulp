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

        case .bold:
            let contentRange = contentRange(token: token)
            return [StyleRun(
                range: contentRange,
                attributes: [.font: PulpFont.boldSystemFont(ofSize: theme.bodySize)]
            )]

        case .italic:
            let contentRange = contentRange(token: token)
            let descriptor = theme.bodyFont().fontDescriptor.adding(symbolicTraits: .italic)
            let font = PulpFont(descriptor: descriptor, size: theme.bodySize) ?? theme.bodyFont()
            return [StyleRun(
                range: contentRange,
                attributes: [.font: font]
            )]

        case .boldItalic:
            let contentRange = contentRange(token: token)
            let descriptor = PulpFont.boldSystemFont(ofSize: theme.bodySize).fontDescriptor.adding(symbolicTraits: .italic)
            let font = PulpFont(descriptor: descriptor, size: theme.bodySize) ?? PulpFont.boldSystemFont(ofSize: theme.bodySize)
            return [StyleRun(
                range: contentRange,
                attributes: [.font: font]
            )]

        case .strikethrough:
            let contentRange = contentRange(token: token)
            return [StyleRun(
                range: contentRange,
                attributes: [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: theme.secondaryTextColor,
                ]
            )]

        case .highlight:
            let contentRange = contentRange(token: token)
            return [StyleRun(
                range: contentRange,
                attributes: [
                    .backgroundColor: PulpColor.systemYellow.withAlphaComponent(0.3),
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

        case .link:
            let contentRange = contentRange(token: token)
            return [StyleRun(
                range: contentRange,
                attributes: [
                    .foregroundColor: theme.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
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
            return []

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
        }
    }

    private func listItemRuns(token: MarkdownToken) -> [StyleRun] {
        let indent: CGFloat = 28
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
        let indent: CGFloat = 28
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.headIndent = 12
        paragraphStyle.firstLineHeadIndent = 12

        var runs: [StyleRun] = []

        let font = isHeader
            ? PulpFont.systemFont(ofSize: theme.bodySize, weight: .semibold)
            : PulpFont.systemFont(ofSize: theme.bodySize)

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
                    .font: PulpFont.systemFont(ofSize: 1),
                ]
            ))
        }

        return runs
    }

    private func orderedListRuns(token: MarkdownToken) -> [StyleRun] {
        let indent: CGFloat = 28
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = 8
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

#if canImport(AppKit)
private extension NSFontDescriptor {
    func adding(symbolicTraits traits: NSFontDescriptor.SymbolicTraits) -> NSFontDescriptor {
        let combined = self.symbolicTraits.union(traits)
        return self.withSymbolicTraits(combined)
    }
}
#endif
