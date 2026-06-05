import Foundation

public enum MarkdownTokenType: Equatable, Sendable {
    case heading(level: Int)
    case bold
    case italic
    case boldItalic
    case strikethrough
    case highlight
    case inlineCode
    case codeBlock
    case link(url: String)
    case image(url: String)
    case autolink(url: String)
    case inlineMath
    case blockMath
    case hashtag
    case taskItem(checked: Bool)
    case orderedListItem
    case blockquote
    case listItem
    case horizontalRule
    case table(columns: Int)
    case tableHeaderRow
    case tableSeparatorRow
    case tableDataRow
    case referenceLink(url: String?)
    case linkDefinition
    case footnoteReference
    case footnoteDefinition
}

public struct MarkdownToken: Equatable, Sendable {
    public let type: MarkdownTokenType
    public let range: NSRange
    public let markerRanges: [NSRange]
    /// Nesting depth for list/task items (0 = top level). Derived from leading
    /// whitespace by the block parser; the styler maps it to indentation. Zero
    /// for every non-list token.
    public let indentDepth: Int

    public init(type: MarkdownTokenType, range: NSRange, markerRanges: [NSRange] = [], indentDepth: Int = 0) {
        self.type = type
        self.range = range
        self.markerRanges = markerRanges
        self.indentDepth = indentDepth
    }
}
