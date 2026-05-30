import Foundation

/// Block-level parsing: tables and per-line block elements (headings, task items,
/// blockquotes, horizontal rules, ordered and unordered list items).
extension MarkdownTokenizer {
    // MARK: - Table Parsing

    func parseTables(
        lines: [Line],
        codeBlockRanges: [NSRange],
        into tokens: inout [MarkdownToken],
        tableRanges: inout [NSRange]
    ) {
        var i = 0
        while i < lines.count {
            if isInside(lines[i].range, anyOf: codeBlockRanges) {
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
            var pipeRanges: [NSRange] = []

            collectPipeRanges(line: lines[i], into: &pipeRanges)
            tokens.append(MarkdownToken(
                type: .tableHeaderRow,
                range: lines[i].range,
                markerRanges: pipeRanges
            ))

            // The whole separator line is its own marker (it shrinks entirely).
            tokens.append(MarkdownToken(
                type: .tableSeparatorRow,
                range: lines[i + 1].range,
                markerRanges: [lines[i + 1].range]
            ))

            var lastLineIndex = i + 1
            var j = i + 2
            while j < lines.count,
                  !isInside(lines[j].range, anyOf: codeBlockRanges),
                  isTableRow(lines[j].content) {
                var rowPipes: [NSRange] = []
                collectPipeRanges(line: lines[j], into: &rowPipes)
                tokens.append(MarkdownToken(
                    type: .tableDataRow,
                    range: lines[j].range,
                    markerRanges: rowPipes
                ))
                lastLineIndex = j
                j += 1
            }

            // The .table range must NOT include the trailing newline of the last
            // row. Structural rewrites replace this range with canonical markdown
            // that has no trailing newline; including it would delete the blank
            // line / separator after the table and merge it into the next block.
            let tableEnd = lines[lastLineIndex].range.location
                + contentLengthExcludingTrailingNewlines(lines[lastLineIndex])
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

    /// UTF-16 length of a line's content with any trailing newline characters removed.
    private func contentLengthExcludingTrailingNewlines(_ line: Line) -> Int {
        let ns = line.content as NSString
        var length = ns.length
        while length > 0 {
            let c = ns.character(at: length - 1)
            guard c == 0x0A || c == 0x0D else { break }
            length -= 1
        }
        return length
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
        let pipe = Character("|").asciiValue.map(UInt16.init) ?? 0x7C
        for i in 0 ..< content.length where content.character(at: i) == pipe {
            ranges.append(NSRange(location: line.range.location + i, length: 1))
        }
    }

    // MARK: - Setext Headings

    /// A non-blank text line immediately followed by a line of only `=` (H1) or
    /// only `-` (H2) is a setext heading. The title line becomes a `.heading` and
    /// the underline a `.setextUnderline` (shrinkable). Both line ranges are
    /// recorded in `consumed` so the per-line block pass skips them — critically,
    /// so a `-` underline is not mistaken for a horizontal rule. Table separator
    /// lines and lines inside excluded regions are not eligible.
    func parseSetextHeadings(
        lines: [Line],
        excluding: [NSRange],
        into tokens: inout [MarkdownToken],
        consumed: inout [NSRange]
    ) {
        var i = 0
        while i + 1 < lines.count {
            let titleLine = lines[i]
            let underlineLine = lines[i + 1]

            guard !isExcluded(titleLine.range, by: excluding),
                  !isExcluded(underlineLine.range, by: excluding),
                  isSetextTitleCandidate(titleLine.content),
                  let level = setextLevel(of: underlineLine.content)
            else {
                i += 1
                continue
            }

            tokens.append(MarkdownToken(
                type: .heading(level: level),
                range: titleLine.range,
                markerRanges: []
            ))
            tokens.append(MarkdownToken(
                type: .setextUnderline,
                range: underlineLine.range,
                markerRanges: [underlineLine.range]
            ))
            consumed.append(titleLine.range)
            consumed.append(underlineLine.range)
            i += 2
        }
    }

    /// A line that can carry a setext underline: has visible text and is not
    /// itself structural markup. Excludes ATX-heading/list/blockquote/table
    /// prefixes (keep in sync with the prefixes recognized in `parseBlockLevel`)
    /// and link/footnote definition lines — a `[ref]: url` or `[^1]: …` line must
    /// stay a definition rather than being swallowed as a setext title.
    private func isSetextTitleCandidate(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let structuralPrefixes = ["#", ">", "-", "*", "+", "|"]
        if structuralPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return false }
        let fullRange = NSRange(location: 0, length: (content as NSString).length)
        if Self.linkDefinitionRegex.firstMatch(in: content, range: fullRange) != nil { return false }
        if Self.footnoteDefinitionRegex.firstMatch(in: content, range: fullRange) != nil { return false }
        return true
    }

    /// 1 for an `=` underline, 2 for a `-` underline, nil otherwise. A `-`
    /// underline must be a pure run (no spaces between dashes) so a `- item`
    /// list line is never read as an underline.
    private func setextLevel(of content: String) -> Int? {
        let range = NSRange(location: 0, length: (content as NSString).length)
        if Self.setextH1Regex.firstMatch(in: content, range: range) != nil { return 1 }
        if Self.setextH2Regex.firstMatch(in: content, range: range) != nil { return 2 }
        return nil
    }

    // MARK: - Block-Level Parsing

    /// Columns of leading whitespace that make up one nesting level. Two spaces
    /// is the common agent/editor convention (e.g. Claude output); a tab counts
    /// as one level.
    static let listSpacesPerLevel = 2
    /// Upper bound on rendered nesting depth. Caps the indent so pathological
    /// leading whitespace (e.g. a pasted 1000-space line) can't blow up
    /// `headIndent` or push text off-screen.
    static let maxListDepth = 8

    /// Nesting depth of a list/task line from its leading whitespace. Spaces count
    /// one column each; a tab counts as one full level. Rounded down, so a
    /// top-level item is depth 0, and clamped to `maxListDepth`.
    func listDepth(of content: String) -> Int {
        var columns = 0
        for ch in content {
            if ch == " " {
                columns += 1
            } else if ch == "\t" {
                columns += Self.listSpacesPerLevel
            } else {
                break
            }
        }
        return min(columns / Self.listSpacesPerLevel, Self.maxListDepth)
    }

    func parseBlockLevel(_ text: NSString, line: Line, into tokens: inout [MarkdownToken]) {
        // Definition lines are exclusive: a line that is a link/footnote
        // definition is not also a list item or other block.
        if parseFootnoteDefinition(line, into: &tokens) { return }
        if parseLinkDefinition(line, into: &tokens) { return }
        parseHeading(line, into: &tokens)
        parseHorizontalRule(line, into: &tokens)
        parseTaskItem(line, into: &tokens)
        parseBlockquote(line, into: &tokens)
        parseOrderedListItem(line, into: &tokens)
        parseListItem(line, into: &tokens)
    }

    /// `[^id]: definition text` — the marker (`[^id]:`) shrinks; the rest is
    /// styled as a secondary definition body. Returns true if it matched.
    private func parseFootnoteDefinition(_ line: Line, into tokens: inout [MarkdownToken]) -> Bool {
        let nsContent = line.content as NSString
        guard let match = Self.footnoteDefinitionRegex.firstMatch(
            in: line.content, range: NSRange(location: 0, length: nsContent.length)
        ) else { return false }
        let markerInDoc = NSRange(location: line.range.location + match.range(at: 1).location,
                                  length: match.range(at: 1).length)
        tokens.append(MarkdownToken(
            type: .footnoteDefinition,
            range: line.range,
            markerRanges: [markerInDoc]
        ))
        return true
    }

    /// `[ref]: url` — the whole line is a reference link definition; the `[ref]:`
    /// machinery shrinks. Returns true if it matched.
    private func parseLinkDefinition(_ line: Line, into tokens: inout [MarkdownToken]) -> Bool {
        let nsContent = line.content as NSString
        guard let match = Self.linkDefinitionRegex.firstMatch(
            in: line.content, range: NSRange(location: 0, length: nsContent.length)
        ) else { return false }
        // Marker = `[` + ref + `]: ` (groups 1–3); the URL (group 4) stays visible.
        let markerStart = match.range(at: 1).location
        let markerEnd = match.range(at: 3).location + match.range(at: 3).length
        let markerInDoc = NSRange(location: line.range.location + markerStart, length: markerEnd - markerStart)
        tokens.append(MarkdownToken(
            type: .linkDefinition,
            range: line.range,
            markerRanges: [markerInDoc]
        ))
        return true
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
            markerRanges: [markerRange],
            indentDepth: listDepth(of: line.content)
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
            markerRanges: [markerInDoc],
            indentDepth: listDepth(of: line.content)
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
            markerRanges: [markerInDoc],
            indentDepth: listDepth(of: line.content)
        ))
    }
}
