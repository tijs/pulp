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
    case hashtag
    case taskItem(checked: Bool)
    case orderedListItem
    case blockquote
    case listItem
    case horizontalRule
}

public struct MarkdownToken: Equatable, Sendable {
    public let type: MarkdownTokenType
    public let range: NSRange
    public let markerRanges: [NSRange]

    public init(type: MarkdownTokenType, range: NSRange, markerRanges: [NSRange] = []) {
        self.type = type
        self.range = range
        self.markerRanges = markerRanges
    }
}
