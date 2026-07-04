import Foundation

/// Paragraph-scoped GFM tokenizer. The parsing logic is split across this core
/// file (entry points, line splitting, fenced code, shared helpers and the regex
/// table) plus two extensions: `MarkdownTokenizer+Block.swift` (headings, lists,
/// tasks, blockquotes, rules, tables) and `MarkdownTokenizer+Inline.swift` (code,
/// emphasis, links, hashtags). Members shared across those files are `internal`
/// rather than `private` because Swift scopes `private` per file.
public final class MarkdownTokenizer: Sendable {
    // swiftlint:disable force_try
    static let codeBlockRegex = try! NSRegularExpression(
        pattern: "(?m)^(`{3,}|~{3,})([^\\n]*)\\n([\\s\\S]*?)^\\1\\s*$",
        options: .anchorsMatchLines
    )
    static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+")
    static let taskItemRegex = try! NSRegularExpression(pattern: "^(\\s*- \\[)([ xX])(\\]\\s)")
    static let blockquoteRegex = try! NSRegularExpression(pattern: "^(>+\\s)")
    static let hrRegex = try! NSRegularExpression(pattern: "^\\s*([-*_]){3,}\\s*$")
    static let orderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+\\.\\s)")
    static let listItemRegex = try! NSRegularExpression(pattern: "^(\\s*[-*+]\\s)")
    static let inlineCodeRegex = try! NSRegularExpression(pattern: "(`+)(.+?)(\\1)", options: .dotMatchesLineSeparators)
    static let boldItalicRegex = try! NSRegularExpression(pattern: "(\\*{3})(.+?)(\\*{3})")
    static let boldRegex = try! NSRegularExpression(pattern: "(\\*{2})(.+?)(\\*{2})")
    // CommonMark flanking: a `*` only opens emphasis when NOT followed by
    // whitespace and only closes when NOT preceded by whitespace. This is what
    // stops a list bullet (`* item`) or a stray `* foo *` from being read as
    // italic — the asterisk adjacent to the space can't be a delimiter. (The
    // `(?<![*])`/`(?![*])` guards still keep it from biting into `**bold**`.)
    static let italicRegex = try! NSRegularExpression(pattern: "(?<![*])(\\*)(?![*\\s])(.+?)(?<![*\\s])(\\*)(?![*])")
    static let strikethroughRegex = try! NSRegularExpression(pattern: "(~~)(.+?)(~~)")
    static let highlightRegex = try! NSRegularExpression(pattern: "(==)(.+?)(==)")
    // Bracket/paren content bounded and newline-free to keep the per-keystroke
    // scan linear on bracket-heavy input.
    static let linkRegex = try! NSRegularExpression(pattern: "(\\[)([^\\]\\n]{1,256})(\\]\\()([^)\\n]{1,2048})(\\))")
    static let imageRegex = try! NSRegularExpression(pattern: "(!\\[)([^\\]\\n]{0,256})(\\]\\()([^)\\n]{1,2048})(\\))")
    // Underscore emphasis with CommonMark-style intra-word protection: an
    // underscore is only a delimiter when its outer side is NOT a letter, digit,
    // or underscore (Unicode-aware via `\p{L}`/`\p{N}`, so CJK and accented text
    // are covered too, not just ASCII). That outer-boundary rule is what keeps a
    // *word-internal* `_` — as in `snake_case`, `path/to_file`, `#v2_release`, or
    // `漢_字` — from opening emphasis. The inner `\S` anchors forbid whitespace
    // just inside the delimiters. Note: like CommonMark, a *leading* `_word_more_`
    // where the run starts at a word boundary is still emphasis — the protection
    // is against intra-word delimiters, not against spans that happen to contain
    // underscores in their content.
    static let underscoreBoldItalicRegex = try! NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}_])(_{3})(?=\\S)(.+?)(?<=\\S)(_{3})(?![\\p{L}\\p{N}_])"
    )
    static let underscoreBoldRegex = try! NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}_])(_{2})(?=\\S)(.+?)(?<=\\S)(_{2})(?![\\p{L}\\p{N}_])"
    )
    static let underscoreItalicRegex = try! NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}_])(_)(?=\\S)(.+?)(?<=\\S)(_)(?![\\p{L}\\p{N}_])"
    )
    static let hashtagRegex = try! NSRegularExpression(
        pattern: "(?<=\\s|^)(#[a-zA-Z][a-zA-Z0-9_/]*)",
        options: .anchorsMatchLines
    )
    // Bare autolink: an http(s) URL not already part of a markdown link. The
    // lookbehind avoids matching the `](https://…)` inside a markdown link;
    // trailing sentence punctuation is trimmed by the parser, not the pattern.
    static let autolinkRegex = try! NSRegularExpression(
        pattern: "(?<![\\w/(])(https?://[^\\s<>]+)"
    )
    // Block math `$$…$$`, possibly spanning lines (rendered as text, not typeset).
    static let blockMathRegex = try! NSRegularExpression(
        pattern: "(\\$\\$)([\\s\\S]+?)(\\$\\$)"
    )
    // A leading frontmatter fence: `---`, any content, a closing `---` line.
    // `\A` anchors to the very start of the document — a `---` fence anywhere
    // else in the body is an ordinary horizontal rule, not frontmatter. `\r?\n`
    // (not a plain `\n`) at each line break so a CRLF-saved fence still
    // matches — this runs directly on the untouched text (offsets must stay
    // valid for NSRange styling), so it can't normalize newlines up front the
    // way `ContentAnalyzer.parseFrontmatterStatus` does.
    static let frontmatterRegex = try! NSRegularExpression(
        pattern: "\\A---\\r?\\n([\\s\\S]*?)\\r?\\n(---)[ \\t]*(?:\\r?\\n|\\z)"
    )
    // Inline math `$…$`: single dollars, non-space just inside, no `$`/newline in
    // the content. Guards against currency such as `$5 and $10`.
    static let inlineMathRegex = try! NSRegularExpression(
        pattern: "(?<!\\$)(\\$)(?=\\S)([^$\\n]+?)(?<=\\S)(\\$)(?!\\$)"
    )
    // Reference link `[text][ref]` and its definition line `[ref]: url`. The
    // bracket-content classes are bounded ({1,N}) and newline-free so that
    // bracket-heavy input (e.g. an unclosed `[[[[…`) cannot trigger quadratic
    // backtracking on the per-keystroke parse path.
    static let referenceLinkRegex = try! NSRegularExpression(pattern: "(\\[)([^\\]\\n]{1,256})(\\]\\[)([^\\]\\n]{0,256})(\\])")
    static let linkDefinitionRegex = try! NSRegularExpression(pattern: "^(\\[)([^\\]\\n]{1,256})(\\]:\\s*)(\\S+)\\s*$")
    // Footnote reference `[^id]` and definition `[^id]: text`. Ids are bounded.
    // Footnote definition `[^id]: …` — group 1 `[^`, group 2 id, group 3 `]:`.
    static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: "^(\\[\\^)([^\\]\\n]{1,64})(\\]:)\\s")
    // Footnote reference `[^id]` — group 1 `[^`, group 2 id, group 3 `]`.
    static let footnoteReferenceRegex = try! NSRegularExpression(pattern: "(\\[\\^)([^\\]\\n]{1,64})(\\])")
    static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: "^\\|?[\\s-]*\\|[\\s:|-]+\\|?\\s*$"
    )
    static let tableRowRegex = try! NSRegularExpression(
        pattern: "^\\|.+\\|\\s*$"
    )
    // swiftlint:enable force_try

    public init() {}

    public func tokenize(_ text: String) -> [MarkdownToken] {
        var tokens: [MarkdownToken] = []
        let nsText = text as NSString

        var codeBlockRanges: [NSRange] = []
        parseFencedCodeBlocks(nsText, into: &tokens, codeBlockRanges: &codeBlockRanges)

        // Block math is excluded from block-level and inline parsing so its
        // contents (LaTeX, which may contain `_`, `*`, `#`, etc.) render as-is.
        var mathBlockRanges: [NSRange] = []
        parseBlockMath(nsText, excluding: codeBlockRanges, into: &tokens, mathBlockRanges: &mathBlockRanges)

        var frontmatterRanges: [NSRange] = []
        parseFrontmatter(nsText, into: &tokens, frontmatterRanges: &frontmatterRanges)

        let lines = splitLines(nsText)
        var tableRanges: [NSRange] = []
        parseTables(lines: lines, codeBlockRanges: codeBlockRanges, into: &tokens, tableRanges: &tableRanges)

        // A line is skipped by the per-line block pass if it falls inside any
        // already-claimed region: fenced code, a table, block math, or a leading
        // frontmatter fence.
        let blockExcluded = codeBlockRanges + tableRanges + mathBlockRanges + frontmatterRanges
        for line in lines where !isInside(line.range, anyOf: blockExcluded) {
            parseBlockLevel(nsText, line: line, into: &tokens)
        }

        // Definition lines (`[ref]: url`, `[^id]: …`) own their whole line and
        // must be exempt from inline parsing — otherwise the URL/body inside them
        // gets autolinked or emphasized on top of the definition styling.
        let definitionRanges = tokens
            .filter { $0.type == .linkDefinition || $0.type == .footnoteDefinition }
            .map(\.range)

        parseInlineElements(nsText, excluding: blockExcluded + definitionRanges, into: &tokens)

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
            return MarkdownToken(type: token.type, range: shiftedRange, markerRanges: shiftedMarkers, indentDepth: token.indentDepth)
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

    // MARK: - Block Math

    private func parseBlockMath(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken], mathBlockRanges: inout [NSRange]) {
        let matches = Self.blockMathRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            let fullRange = match.range
            if isExcluded(fullRange, by: excluding) { continue }
            let openDelim = match.range(at: 1)
            let closeDelim = match.range(at: 3)
            let openLine = text.lineRange(for: openDelim)
            let closeLine = text.lineRange(for: closeDelim)
            let markerRanges: [NSRange]
            if openLine.location == closeLine.location {
                // Single-line form `$$a = b$$`: the open and close delimiters share
                // one line. Shrinking the whole line would hide the content too, so
                // shrink only the `$$` delimiters and leave the body visible.
                markerRanges = [openDelim, closeDelim]
            } else {
                // Multi-line form: shrink the ENTIRE opening and closing `$$` lines
                // (delimiter plus newline) so the collapsed markers leave no stray
                // blank lines — mirroring how fenced code blocks shrink fence lines.
                // Clip each marker to the token so it never bleeds into the next
                // paragraph's separator.
                markerRanges = [
                    NSIntersectionRange(openLine, fullRange),
                    NSIntersectionRange(closeLine, fullRange),
                ]
            }
            tokens.append(MarkdownToken(
                type: .blockMath,
                range: fullRange,
                markerRanges: markerRanges
            ))
            mathBlockRanges.append(fullRange)
        }
    }

    // MARK: - Frontmatter

    /// A leading `---`/`key: value`/`---` fence, tokenized as one block so the
    /// styler can render it as a single callout instead of two separate
    /// horizontal rules with plain paragraph text between them. Only the
    /// fence lines themselves are markers (hidden); the content between stays
    /// visible — mirrors kiem-core's `parse_frontmatter_status`, a display-only
    /// concern here (Pulp never extracts `status` itself).
    private func parseFrontmatter(_ text: NSString, into tokens: inout [MarkdownToken], frontmatterRanges: inout [NSRange]) {
        guard let match = Self.frontmatterRegex.firstMatch(
            in: text as String, range: NSRange(location: 0, length: text.length)
        ) else { return }
        let fullRange = match.range
        let openLine = text.lineRange(for: NSRange(location: 0, length: 0))
        // Anchor on the captured closing `---` itself (group 2), not on an
        // assumed single-character gap after the content — the gap is `\n`
        // for an LF-saved fence but `\r\n` for a CRLF-saved one.
        let closeLine = text.lineRange(for: NSRange(location: match.range(at: 2).location, length: 0))
        tokens.append(MarkdownToken(
            type: .frontmatter,
            range: fullRange,
            markerRanges: [
                NSIntersectionRange(openLine, fullRange),
                NSIntersectionRange(closeLine, fullRange),
            ]
        ))
        frontmatterRanges.append(fullRange)
    }

    // MARK: - Line Splitting

    struct Line {
        let range: NSRange
        let content: String
    }

    func splitLines(_ text: NSString) -> [Line] {
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

    // MARK: - Shared Helpers

    /// Whether `range` intersects any range in the set. The single membership
    /// primitive used for every "is this position inside an already-claimed
    /// region" test — code fences, tables, block math, definition lines, and
    /// the inline exclusion set all funnel through here.
    func isInside(_ range: NSRange, anyOf ranges: [NSRange]) -> Bool {
        ranges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    /// Alias of `isInside(_:anyOf:)` read at the inline-parser call sites, where
    /// "excluded from parsing" is the natural phrasing.
    func isExcluded(_ range: NSRange, by excludedRanges: [NSRange]) -> Bool {
        isInside(range, anyOf: excludedRanges)
    }

    func isOverlapping(_ range: NSRange, with tokens: [MarkdownToken], types: [MarkdownTokenType]) -> Bool {
        tokens.contains { token in
            types.contains(token.type) && NSIntersectionRange(token.range, range).length > 0
        }
    }
}
