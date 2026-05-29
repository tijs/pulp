import Foundation

public final class MarkdownTokenizer: Sendable {
    // swiftlint:disable force_try
    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: "(?m)^(`{3,}|~{3,})([^\\n]*)\\n([\\s\\S]*?)^\\1\\s*$",
        options: .anchorsMatchLines
    )
    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+")
    private static let taskItemRegex = try! NSRegularExpression(pattern: "^(\\s*- \\[)([ xX])(\\]\\s)")
    private static let blockquoteRegex = try! NSRegularExpression(pattern: "^(>+\\s)")
    private static let hrRegex = try! NSRegularExpression(pattern: "^\\s*([-*_]){3,}\\s*$")
    private static let orderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.\\s)")
    private static let listItemRegex = try! NSRegularExpression(pattern: "^(\\s*[-*+]\\s)")
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: "(`+)(.+?)(\\1)", options: .dotMatchesLineSeparators)
    private static let boldItalicRegex = try! NSRegularExpression(pattern: "(\\*{3})(.+?)(\\*{3})")
    private static let boldRegex = try! NSRegularExpression(pattern: "(\\*{2})(.+?)(\\*{2})")
    private static let italicRegex = try! NSRegularExpression(pattern: "(?<![*])(\\*)(?![*])(.+?)(?<![*])(\\*)(?![*])")
    private static let strikethroughRegex = try! NSRegularExpression(pattern: "(~~)(.+?)(~~)")
    private static let highlightRegex = try! NSRegularExpression(pattern: "(==)(.+?)(==)")
    private static let linkRegex = try! NSRegularExpression(pattern: "(\\[)([^\\]]+)(\\]\\()([^)]+)(\\))")
    private static let hashtagRegex = try! NSRegularExpression(
        pattern: "(?<=\\s|^)(#[a-zA-Z][a-zA-Z0-9_/]*)",
        options: .anchorsMatchLines
    )
    private static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: "^\\|?[\\s-]*\\|[\\s:|-]+\\|?\\s*$"
    )
    private static let tableRowRegex = try! NSRegularExpression(
        pattern: "^\\|.+\\|\\s*$"
    )
    // swiftlint:enable force_try

    public init() {}

    public func tokenize(_ text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        let nsText = text as NSString

        var codeBlockRanges: [NSRange] = []
        parseFencedCodeBlocks(nsText, into: &tokens, codeBlockRanges: &codeBlockRanges)

        let lines = splitLines(nsText)
        var tableRanges: [NSRange] = []
        parseTables(lines: lines, codeBlockRanges: codeBlockRanges, into: &tokens, tableRanges: &tableRanges)

        for line in lines {
            if isInsideCodeBlock(line.range, codeBlockRanges: codeBlockRanges) { continue }
            if isInsideTable(line.range, tableRanges: tableRanges) { continue }
            parseBlockLevel(nsText, line: line, into: &tokens)
        }

        parseInlineElements(nsText, excluding: codeBlockRanges + tableRanges, into: &tokens)

        tokens.sort { $0.range.location < $1.range.location }
        return tokens
    }

    public func tokenizeParagraph(_ text: String, paragraphRange: NSRange) -> [MarkdownToken] {
        let nsText = text as NSString
        let paragraph = nsText.substring(with: paragraphRange)
        let tokens = tokenize(paragraph)
        return tokens.map { token in
            let shiftedRange = NSRange(location: token.range.location + paragraphRange.location, length: token.range.length)
            let shiftedMarkers = token.markerRanges.map {
                NSRange(location: $0.location + paragraphRange.location, length: $0.length)
            }
            return MarkdownToken(type: token.type, range: shiftedRange, markerRanges: shiftedMarkers)
        }
    }

    // MARK: - Fenced Code Blocks

    private func parseFencedCodeBlocks(_ text: NSString, into tokens: inout [MarkdownToken], codeBlockRanges: inout [NSRange]) {
        let matches = Self.codeBlockRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            let fullRange = match.range

            let openLineDocRange = text.lineRange(for: NSRange(location: fullRange.location, length: 0))

            let closeEnd = fullRange.location + fullRange.length
            let closeLineDocRange = text.lineRange(for: NSRange(location: max(0, closeEnd - 1), length: 0))

            tokens.append(MarkdownToken(
                type: .codeBlock,
                range: fullRange,
                markerRanges: [openLineDocRange, closeLineDocRange]
            ))
            codeBlockRanges.append(fullRange)
        }
    }

    // MARK: - Line Splitting

    private struct Line {
        let range: NSRange
        let content: String
    }

    private func splitLines(_ text: NSString) -> [Line] {
        var lines: [Line] = []
        var start = 0
        while start < text.length {
            let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
            let content = text.substring(with: lineRange)
            lines.append(Line(range: lineRange, content: content))
            start = lineRange.location + lineRange.length
        }
        return lines
    }

    private func isInsideCodeBlock(_ range: NSRange, codeBlockRanges: [NSRange]) -> Bool {
        codeBlockRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private func isInsideTable(_ range: NSRange, tableRanges: [NSRange]) -> Bool {
        tableRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    // MARK: - Table Parsing

    private func parseTables(
        lines: [Line],
        codeBlockRanges: [NSRange],
        into tokens: inout [MarkdownToken],
        tableRanges: inout [NSRange]
    ) {
        var i = 0
        while i < lines.count {
            if isInsideCodeBlock(lines[i].range, codeBlockRanges: codeBlockRanges) {
                i += 1
                continue
            }

            guard i + 1 < lines.count,
                  isTableRow(lines[i].content),
                  isTableSeparator(lines[i + 1].content)
            else {
                i += 1
                continue
            }

            let columns = countColumns(lines[i].content)
            let tableStart = lines[i].range.location
            var tableEnd = lines[i + 1].range.location + lines[i + 1].range.length
            var pipeRanges: [NSRange] = []

            collectPipeRanges(line: lines[i], into: &pipeRanges)
            tokens.append(MarkdownToken(
                type: .tableHeaderRow,
                range: lines[i].range,
                markerRanges: pipeRanges
            ))

            let sepPipes = collectSeparatorMarkers(line: lines[i + 1])
            tokens.append(MarkdownToken(
                type: .tableSeparatorRow,
                range: lines[i + 1].range,
                markerRanges: sepPipes
            ))

            var j = i + 2
            while j < lines.count,
                  !isInsideCodeBlock(lines[j].range, codeBlockRanges: codeBlockRanges),
                  isTableRow(lines[j].content)
            {
                var rowPipes: [NSRange] = []
                collectPipeRanges(line: lines[j], into: &rowPipes)
                tokens.append(MarkdownToken(
                    type: .tableDataRow,
                    range: lines[j].range,
                    markerRanges: rowPipes
                ))
                tableEnd = lines[j].range.location + lines[j].range.length
                j += 1
            }

            let fullRange = NSRange(location: tableStart, length: tableEnd - tableStart)
            tokens.append(MarkdownToken(
                type: .table(columns: columns),
                range: fullRange,
                markerRanges: []
            ))
            tableRanges.append(fullRange)

            i = j
        }
    }

    private func isTableRow(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 2
    }

    private func isTableSeparator(_ content: String) -> Bool {
        let range = NSRange(location: 0, length: (content as NSString).length)
        return Self.tableSeparatorRegex.firstMatch(in: content, range: range) != nil
    }

    private func countColumns(_ content: String) -> Int {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let inner = trimmed.dropFirst().dropLast()
        return inner.components(separatedBy: "|").count
    }

    private func collectPipeRanges(line: Line, into ranges: inout [NSRange]) {
        let content = line.content as NSString
        for i in 0 ..< content.length {
            if content.character(at: i) == Character("|").asciiValue.map(UInt16.init) ?? 0x7C {
                ranges.append(NSRange(location: line.range.location + i, length: 1))
            }
        }
    }

    private func collectSeparatorMarkers(line: Line) -> [NSRange] {
        [line.range]
    }

    // MARK: - Block-Level Parsing

    private func parseBlockLevel(_ text: NSString, line: Line, into tokens: inout [MarkdownToken]) {
        parseHeading(line, into: &tokens)
        parseHorizontalRule(line, into: &tokens)
        parseTaskItem(line, into: &tokens)
        parseBlockquote(line, into: &tokens)
        parseOrderedListItem(line, into: &tokens)
        parseListItem(line, into: &tokens)
    }

    private func parseHeading(_ line: Line, into tokens: inout [MarkdownToken]) {
        guard let match = Self.headingRegex.firstMatch(in: line.content, range: NSRange(location: 0, length: (line.content as NSString).length))
        else { return }
        let markerRange = match.range(at: 1)
        let level = markerRange.length
        let markerInDoc = NSRange(location: line.range.location + markerRange.location, length: markerRange.length + 1)
        tokens.append(MarkdownToken(
            type: .heading(level: level),
            range: line.range,
            markerRanges: [markerInDoc]
        ))
    }

    private func parseTaskItem(_ line: Line, into tokens: inout [MarkdownToken]) {
        guard let match = Self.taskItemRegex.firstMatch(in: line.content, range: NSRange(location: 0, length: (line.content as NSString).length))
        else { return }
        let checkChar = (line.content as NSString).substring(with: match.range(at: 2))
        let checked = checkChar == "x" || checkChar == "X"
        let markerRange = NSRange(location: line.range.location, length: match.range.length)
        tokens.append(MarkdownToken(
            type: .taskItem(checked: checked),
            range: line.range,
            markerRanges: [markerRange]
        ))
    }

    private func parseBlockquote(_ line: Line, into tokens: inout [MarkdownToken]) {
        guard let match = Self.blockquoteRegex.firstMatch(in: line.content, range: NSRange(location: 0, length: (line.content as NSString).length))
        else { return }
        let markerInDoc = NSRange(location: line.range.location + match.range.location, length: match.range.length)
        tokens.append(MarkdownToken(
            type: .blockquote,
            range: line.range,
            markerRanges: [markerInDoc]
        ))
    }

    private func parseHorizontalRule(_ line: Line, into tokens: inout [MarkdownToken]) {
        guard Self.hrRegex.firstMatch(in: line.content, range: NSRange(location: 0, length: (line.content as NSString).length)) != nil else { return }
        tokens.append(MarkdownToken(
            type: .horizontalRule,
            range: line.range,
            markerRanges: [line.range]
        ))
    }

    private func parseOrderedListItem(_ line: Line, into tokens: inout [MarkdownToken]) {
        guard let match = Self.orderedListRegex.firstMatch(in: line.content, range: NSRange(location: 0, length: (line.content as NSString).length))
        else { return }
        let markerRange = match.range(at: 2)
        let markerInDoc = NSRange(location: line.range.location + markerRange.location, length: markerRange.length)
        tokens.append(MarkdownToken(
            type: .orderedListItem,
            range: line.range,
            markerRanges: [markerInDoc]
        ))
    }

    private func parseListItem(_ line: Line, into tokens: inout [MarkdownToken]) {
        guard let match = Self.listItemRegex.firstMatch(in: line.content, range: NSRange(location: 0, length: (line.content as NSString).length))
        else { return }
        // Don't double-count task items
        if line.content.contains("- [") { return }
        let markerInDoc = NSRange(location: line.range.location + match.range.location, length: match.range.length)
        tokens.append(MarkdownToken(
            type: .listItem,
            range: line.range,
            markerRanges: [markerInDoc]
        ))
    }

    // MARK: - Inline Parsing

    private func parseInlineElements(_ text: NSString, excluding codeBlockRanges: [NSRange], into tokens: inout [MarkdownToken]) {
        parseInlineCode(text, excluding: codeBlockRanges, into: &tokens)

        var inlineCodeRanges = codeBlockRanges
        for token in tokens where token.type == .inlineCode {
            inlineCodeRanges.append(token.range)
        }

        parseBoldItalic(text, excluding: inlineCodeRanges, into: &tokens)
        parseBold(text, excluding: inlineCodeRanges, into: &tokens)
        parseItalic(text, excluding: inlineCodeRanges, into: &tokens)
        parseStrikethrough(text, excluding: inlineCodeRanges, into: &tokens)
        parseHighlight(text, excluding: inlineCodeRanges, into: &tokens)
        parseLinks(text, excluding: inlineCodeRanges, into: &tokens)
        parseHashtags(text, excluding: inlineCodeRanges, into: &tokens)
    }

    private func parseInlineCode(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.inlineCodeRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            let range = match.range
            if isExcluded(range, by: excluding) { continue }
            let openTick = match.range(at: 1)
            let closeTick = match.range(at: 3)
            tokens.append(MarkdownToken(
                type: .inlineCode,
                range: range,
                markerRanges: [openTick, closeTick]
            ))
        }
    }

    private func parseBoldItalic(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.boldItalicRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            tokens.append(MarkdownToken(
                type: .boldItalic,
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    private func parseBold(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.boldRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            if isOverlapping(match.range, with: tokens, types: [.boldItalic]) { continue }
            tokens.append(MarkdownToken(
                type: .bold,
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    private func parseItalic(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.italicRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            if isOverlapping(match.range, with: tokens, types: [.bold, .boldItalic]) { continue }
            tokens.append(MarkdownToken(
                type: .italic,
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    private func parseStrikethrough(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.strikethroughRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            tokens.append(MarkdownToken(
                type: .strikethrough,
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    private func parseHighlight(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.highlightRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            tokens.append(MarkdownToken(
                type: .highlight,
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    private func parseLinks(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.linkRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            let url = text.substring(with: match.range(at: 4))
            let openBracket = match.range(at: 1)
            let closeBracketParen = match.range(at: 3)
            let urlRange = match.range(at: 4)
            let closeParen = match.range(at: 5)
            let markerRanges = [openBracket, closeBracketParen, urlRange, closeParen]
            tokens.append(MarkdownToken(
                type: .link(url: url),
                range: match.range,
                markerRanges: markerRanges
            ))
        }
    }

    private func parseHashtags(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.hashtagRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            let range = match.range(at: 1)
            if isExcluded(range, by: excluding) { continue }
            // Don't match heading markers
            let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
            if range.location == lineStart { continue }
            tokens.append(MarkdownToken(
                type: .hashtag,
                range: range,
                markerRanges: []
            ))
        }
    }

    // MARK: - Helpers

    private func isExcluded(_ range: NSRange, by excludedRanges: [NSRange]) -> Bool {
        excludedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private func isOverlapping(_ range: NSRange, with tokens: [MarkdownToken], types: [MarkdownTokenType]) -> Bool {
        tokens.contains { token in
            types.contains(token.type) && NSIntersectionRange(token.range, range).length > 0
        }
    }
}
