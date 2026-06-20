#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation

public extension PulpEditorProtocol {
    func toggleBold() {
        wrapSelection(prefix: "**", suffix: "**")
    }

    func toggleItalic() {
        wrapSelection(prefix: "*", suffix: "*")
    }

    func toggleStrikethrough() {
        wrapSelection(prefix: "~~", suffix: "~~")
    }

    func toggleHighlight() {
        wrapSelection(prefix: "==", suffix: "==")
    }

    func toggleInlineCode() {
        wrapSelection(prefix: "`", suffix: "`")
    }

    func setHeading(level: Int) {
        let prefix = String(repeating: "#", count: level) + " "
        replaceLinePrefix(with: prefix, pattern: "^#{1,6}\\s+")
    }

    func toggleTaskList() {
        toggleLinePrefix("- [ ] ")
    }

    func toggleUnorderedList() {
        toggleLinePrefix("- ")
    }

    func toggleOrderedList() {
        toggleLinePrefix("1. ")
    }

    func toggleBlockquote() {
        toggleLinePrefix("> ")
    }

    /// Insert a Markdown link at the caret. With no selection, inserts `[]()`
    /// and places the caret inside the `[]`. With a selection, wraps it as
    /// `[selected]()` and places the caret inside the `()` ready for the URL.
    func insertLink() {
        let sel = selectedRange
        let nsText = text as NSString
        guard sel.location != NSNotFound else { return }

        if sel.length == 0 {
            applyTextReplacement(range: sel, replacement: "[]()")
            // Caret between the brackets: just past the opening `[`.
            selectedRange = NSRange(location: sel.location + 1, length: 0)
            return
        }

        let selected = nsText.substring(with: sel)
        applyTextReplacement(range: sel, replacement: "[\(selected)]()")
        // Caret between the parens: past `[selected](`.
        selectedRange = NSRange(location: sel.location + selected.count + 3, length: 0)
    }
}

private extension PulpEditorProtocol {
    /// Toggle an inline emphasis marker (`**`, `*`, `~~`, `==`, `` ` ``) around the
    /// selection. The wrap is **structure-aware**: it only ever touches the
    /// *content* of the selection, never a block marker (`- `, `1. `, `- [ ] `,
    /// `> `, `# `) and never crosses a table-cell pipe. A selection that spans
    /// several list items or table cells wraps each one's content independently.
    func wrapSelection(prefix: String, suffix: String) {
        let sel = selectedRange
        let nsText = text as NSString
        guard sel.location != NSNotFound else { return }

        // Empty selection: insert the markers and place the caret between them.
        if sel.length == 0 {
            let preLen = (prefix as NSString).length
            applyTextReplacement(range: sel, replacement: "\(prefix)\(suffix)")
            selectedRange = NSRange(location: sel.location + preLen, length: 0)
            return
        }

        let segments = wrappableSegments(in: sel, text: nsText)
        // Selection covered only markers / pipes (nothing wrappable): no-op.
        guard !segments.isEmpty else { return }

        let preLen = (prefix as NSString).length
        let sufLen = (suffix as NSString).length

        // Toggle off only when every content segment is already wrapped.
        let allWrapped = segments.allSatisfy { seg in
            let s = nsText.substring(with: seg) as NSString
            return s.length >= preLen + sufLen
                && s.hasPrefix(prefix) && s.hasSuffix(suffix)
        }

        // Rebuild the whole selection in one edit, transforming each content
        // segment and copying the gaps (markers, pipes, inter-segment text)
        // verbatim. One edit keeps every offset stable.
        let result = NSMutableString()
        var cursor = sel.location
        let selEnd = sel.location + sel.length
        for seg in segments {
            if seg.location > cursor {
                result.append(nsText.substring(with: NSRange(location: cursor, length: seg.location - cursor)))
            }
            let segText = nsText.substring(with: seg) as NSString
            if allWrapped {
                result.append(segText.substring(with: NSRange(location: preLen, length: segText.length - preLen - sufLen)))
            } else {
                result.append(prefix)
                result.append(segText as String)
                result.append(suffix)
            }
            cursor = seg.location + seg.length
        }
        if cursor < selEnd {
            result.append(nsText.substring(with: NSRange(location: cursor, length: selEnd - cursor)))
        }

        applyTextReplacement(range: sel, replacement: result as String)

        // Keep the user's content selected so emphasis can be chained. For the
        // common single-segment case this matches the pre-existing behavior
        // (select the inner content, not the markers); multi-segment selects the
        // whole transformed span.
        if segments.count == 1 {
            let seg = segments[0]
            selectedRange = allWrapped
                ? NSRange(location: seg.location, length: seg.length - preLen - sufLen)
                : NSRange(location: seg.location + preLen, length: seg.length)
        } else {
            selectedRange = NSRange(location: sel.location, length: (result as NSString).length)
        }
    }

    /// The sub-ranges of `sel` that inline emphasis may wrap: the content of each
    /// covered line with any block marker stripped, and — inside a table — each
    /// covered cell's interior, never spanning a `|`.
    func wrappableSegments(in sel: NSRange, text nsText: NSString) -> [NSRange] {
        let tokens = MarkdownTokenizer().tokenize(text)
        let selEnd = sel.location + sel.length
        var segments: [NSRange] = []

        var idx = sel.location
        while idx < selEnd {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                                for: NSRange(location: idx, length: 0))

            if let row = tableRowToken(at: lineStart, tokens: tokens) {
                appendTableCellSegments(row: row, sel: sel, lineContentsEnd: contentsEnd,
                                        nsText: nsText, into: &segments)
            } else {
                let contentStart = blockContentStart(lineStart: lineStart, tokens: tokens)
                let segStart = max(sel.location, contentStart)
                let segEnd = min(selEnd, contentsEnd)
                if segEnd > segStart {
                    segments.append(NSRange(location: segStart, length: segEnd - segStart))
                }
            }

            idx = lineEnd > idx ? lineEnd : idx + 1
        }
        return segments
    }

    /// The offset where a line's wrappable content begins: just past the block
    /// marker for list / ordered-list / task / blockquote / heading lines, or the
    /// line start for a plain paragraph. Reuses each token's `markerRanges`, which
    /// already span indent + marker + trailing space.
    func blockContentStart(lineStart: Int, tokens: [MarkdownToken]) -> Int {
        for token in tokens where token.range.location == lineStart {
            switch token.type {
            case .listItem, .orderedListItem, .taskItem, .blockquote, .heading:
                if let marker = token.markerRanges.first {
                    return marker.location + marker.length
                }
            default:
                continue
            }
        }
        return lineStart
    }

    /// The table header/data row token whose line starts at `lineStart`, if any.
    /// Separator rows are intentionally excluded — there is nothing to emphasize.
    func tableRowToken(at lineStart: Int, tokens: [MarkdownToken]) -> MarkdownToken? {
        tokens.first { token in
            guard token.range.location == lineStart else { return false }
            switch token.type {
            case .tableHeaderRow, .tableDataRow: return true
            default: return false
            }
        }
    }

    /// Append one segment per table cell the selection touches, each clamped to
    /// the cell interior between consecutive pipes so emphasis never crosses a `|`.
    /// Cell-padding whitespace is trimmed so wrapping a cell yields `**a**`, not
    /// `** a **`.
    func appendTableCellSegments(row: MarkdownToken, sel: NSRange, lineContentsEnd: Int,
                                 nsText: NSString, into segments: inout [NSRange]) {
        let pipes = row.markerRanges.sorted { $0.location < $1.location }
        guard pipes.count >= 2 else { return }
        let selEnd = sel.location + sel.length
        for k in 0 ..< (pipes.count - 1) {
            let interiorStart = pipes[k].location + pipes[k].length
            let interiorEnd = min(pipes[k + 1].location, lineContentsEnd)
            var segStart = max(sel.location, interiorStart)
            var segEnd = min(selEnd, interiorEnd)
            while segStart < segEnd, isHorizontalSpace(nsText.character(at: segStart)) { segStart += 1 }
            while segEnd > segStart, isHorizontalSpace(nsText.character(at: segEnd - 1)) { segEnd -= 1 }
            if segEnd > segStart {
                segments.append(NSRange(location: segStart, length: segEnd - segStart))
            }
        }
    }

    func isHorizontalSpace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09
    }

    func replaceLinePrefix(with newPrefix: String, pattern: String) {
        let nsText = text as NSString
        let sel = selectedRange
        guard sel.location <= nsText.length else { return }

        let lineRange = nsText.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = nsText.substring(with: lineRange)

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let existingPrefix = (line as NSString).substring(with: match.range)
            if existingPrefix == newPrefix {
                let removeRange = NSRange(location: lineRange.location, length: newPrefix.count)
                applyTextReplacement(range: removeRange, replacement: "")
                return
            }
            let replaceRange = NSRange(location: lineRange.location + match.range.location, length: match.range.length)
            applyTextReplacement(range: replaceRange, replacement: newPrefix)
        } else {
            applyTextReplacement(range: NSRange(location: lineRange.location, length: 0), replacement: newPrefix)
        }
    }

    func toggleLinePrefix(_ prefix: String) {
        let nsText = text as NSString
        let sel = selectedRange
        guard sel.location <= nsText.length else { return }

        let lineRange = nsText.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = nsText.substring(with: lineRange)

        if line.hasPrefix(prefix) {
            let removeRange = NSRange(location: lineRange.location, length: prefix.count)
            applyTextReplacement(range: removeRange, replacement: "")
        } else {
            applyTextReplacement(range: NSRange(location: lineRange.location, length: 0), replacement: prefix)
        }
    }

    func applyTextReplacement(range: NSRange, replacement: String) {
        let edit = TextEdit(range: range, replacementText: replacement)
        applyRemoteEdit(edit)
    }
}
