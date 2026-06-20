import Foundation

/// Inline parsing: code spans, emphasis (bold/italic/strikethrough/highlight),
/// links, and hashtags. Inline elements are never matched inside fenced code
/// blocks, tables, or inline code spans.
extension MarkdownTokenizer {
    func parseInlineElements(_ text: NSString, excluding codeBlockRanges: [NSRange], into tokens: inout [MarkdownToken]) {
        // Inline code and inline math are "verbatim" spans: their content is not
        // markdown and must be exempt from all other inline parsing. Parse them
        // first and fold their ranges into the exclusion set so emphasis, links,
        // hashtags, etc. never fire inside `` `code` `` or `$math$`.
        parseInlineCode(text, excluding: codeBlockRanges, into: &tokens)

        // Math must not match inside inline code, so fold code ranges in first.
        var excluded = codeBlockRanges
        for token in tokens where token.type == .inlineCode {
            excluded.append(token.range)
        }
        parseInlineMath(text, excluding: excluded, into: &tokens)
        for token in tokens where token.type == .inlineMath {
            excluded.append(token.range)
        }

        parseBoldItalic(text, excluding: excluded, into: &tokens)
        parseBold(text, excluding: excluded, into: &tokens)
        parseItalic(text, excluding: excluded, into: &tokens)
        parseUnderscoreEmphasis(text, excluding: excluded, into: &tokens)
        parseStrikethrough(text, excluding: excluded, into: &tokens)
        parseHighlight(text, excluding: excluded, into: &tokens)
        parseImages(text, excluding: excluded, into: &tokens)
        parseFootnoteReferences(text, excluding: excluded, into: &tokens)
        parseReferenceLinks(text, excluding: excluded, into: &tokens)
        parseLinks(text, excluding: excluded, into: &tokens)
        parseAutolinks(text, excluding: excluded, into: &tokens)
        parseHashtags(text, excluding: excluded, into: &tokens)
    }

    /// Footnote reference `[^id]`. Runs before reference-link/link parsing so a
    /// `[^id]` isn't misread as a `[text]`. Skips a `[^id]:` definition (handled
    /// at block level) by requiring the match not to be immediately followed by `:`.
    private func parseFootnoteReferences(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.footnoteReferenceRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            let range = match.range
            if isExcluded(range, by: excluding) { continue }
            let after = range.location + range.length
            if after < text.length, text.character(at: after) == 0x3A { continue } // ':' → definition
            // Shrink the `[^` prefix and `]` suffix so only the id shows, raised
            // as a superscript by the styler.
            tokens.append(MarkdownToken(
                type: .footnoteReference,
                range: range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    /// Reference link `[text][ref]`. The visible text is styled as a link; the
    /// `[`, `][ref]`, `]` machinery shrinks.
    private func parseReferenceLinks(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.referenceLinkRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            if isOverlapping(match.range, with: tokens, types: [.footnoteReference]) { continue }
            // Shrink the `[` before the visible text and the whole `][ref]` tail
            // (connector + ref label + closing `]`) so only the visible text shows
            // — otherwise the ref label leaks (e.g. "the Swift forumsforums").
            // Group 2 is the visible text; groups 3..5 span `][`, ref, `]`.
            let openBracket = match.range(at: 1)
            let tailStart = match.range(at: 3).location
            let tailEnd = match.range(at: 5).location + match.range(at: 5).length
            let tail = NSRange(location: tailStart, length: tailEnd - tailStart)
            tokens.append(MarkdownToken(
                type: .referenceLink(url: nil),
                range: match.range,
                markerRanges: [openBracket, tail]
            ))
        }
    }

    /// Inline math `$…$`. Content (LaTeX) is rendered as a styled span, not typeset.
    private func parseInlineMath(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.inlineMathRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            tokens.append(MarkdownToken(
                type: .inlineMath,
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3)]
            ))
        }
    }

    /// Bare `http(s)` URLs. Runs after `parseLinks` so a markdown `[text](url)`
    /// is not also matched as an autolink (overlap suppression against `.link`).
    /// Trailing sentence punctuation is trimmed off the matched range.
    private func parseAutolinks(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.autolinkRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            var range = match.range(at: 1)
            range = trimmingTrailingURLPunctuation(range, in: text)
            if range.length == 0 { continue }
            if isExcluded(range, by: excluding) { continue }
            // Skip a URL already captured as the target of a markdown link. The
            // associated url value varies, so match the `.link` case by pattern.
            let insideLink = tokens.contains { token in
                if case .link = token.type {
                    return NSIntersectionRange(token.range, range).length > 0
                }
                return false
            }
            if insideLink { continue }
            let url = text.substring(with: range)
            tokens.append(MarkdownToken(
                type: .autolink(url: url),
                range: range,
                markerRanges: []
            ))
        }
    }

    /// Drop trailing characters that are almost always sentence punctuation rather
    /// than part of a URL: `.`, `,`, `;`, `:`, `!`, `?`, and an unbalanced `)`/`]`.
    private func trimmingTrailingURLPunctuation(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let last = text.character(at: range.location + length - 1)
            guard let scalar = Unicode.Scalar(last) else { break }
            let ch = Character(scalar)
            if ".,;:!?".contains(ch) {
                length -= 1
            } else if ch == ")" || ch == "]" {
                // Only trim a closing bracket if it isn't balanced within the URL.
                let sub = text.substring(with: NSRange(location: range.location, length: length))
                let open: Character = ch == ")" ? "(" : "["
                if sub.filter({ $0 == open }).count >= sub.filter({ $0 == ch }).count {
                    break
                }
                length -= 1
            } else {
                break
            }
        }
        return NSRange(location: range.location, length: length)
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

    /// Underscore emphasis (`_italic_`, `__bold__`, `___bolditalic___`). Emits the
    /// same token types as the asterisk forms — the rendered result is identical.
    /// Longest run first so `___` and `__` win before `_`. Intra-word underscores
    /// are excluded by the regex lookarounds, protecting `snake_case` and paths.
    /// One run-length of underscore emphasis (`___`/`__`/`_`) and the emphasis
    /// types it must not overlap with (the heavier rungs emitted before it).
    private struct EmphasisRung {
        let regex: NSRegularExpression
        let type: MarkdownTokenType
        let overlap: [MarkdownTokenType]
    }

    private func parseUnderscoreEmphasis(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        // Longest run first so `___`/`__` win before `_`.
        let rungs = [
            EmphasisRung(regex: Self.underscoreBoldItalicRegex, type: .boldItalic, overlap: [.boldItalic]),
            EmphasisRung(regex: Self.underscoreBoldRegex, type: .bold, overlap: [.boldItalic, .bold]),
            EmphasisRung(regex: Self.underscoreItalicRegex, type: .italic, overlap: [.boldItalic, .bold, .italic]),
        ]
        let fullRange = NSRange(location: 0, length: text.length)
        for rung in rungs {
            for match in rung.regex.matches(in: text as String, range: fullRange) {
                if isExcluded(match.range, by: excluding) { continue }
                if isOverlapping(match.range, with: tokens, types: rung.overlap) { continue }
                tokens.append(MarkdownToken(
                    type: rung.type,
                    range: match.range,
                    markerRanges: [match.range(at: 1), match.range(at: 3)]
                ))
            }
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

    /// Image syntax `![alt](url)`. Recognition + styling only — no inline thumbnail
    /// (deferred; see the plan). Runs before `parseLinks` and the link parser skips
    /// the `[alt](url)` inside an image so it isn't double-matched.
    private func parseImages(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.imageRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            let url = text.substring(with: match.range(at: 4))
            tokens.append(MarkdownToken(
                type: .image(url: url),
                range: match.range,
                markerRanges: [match.range(at: 1), match.range(at: 3), match.range(at: 4), match.range(at: 5)]
            ))
        }
    }

    private func parseLinks(_ text: NSString, excluding: [NSRange], into tokens: inout [MarkdownToken]) {
        let matches = Self.linkRegex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        for match in matches {
            if isExcluded(match.range, by: excluding) { continue }
            // Skip the `[alt](url)` that is part of an already-parsed image.
            let insideImage = tokens.contains { token in
                if case .image = token.type {
                    return NSIntersectionRange(token.range, match.range).length > 0
                }
                return false
            }
            if insideImage { continue }
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
            // Headings (`# `, `## `) are already excluded by the regex, which
            // requires a letter immediately after `#`. A `#tag` at the start of a
            // line is a real tag, so don't skip it.
            tokens.append(MarkdownToken(
                type: .hashtag,
                range: range,
                markerRanges: []
            ))
        }
    }
}
