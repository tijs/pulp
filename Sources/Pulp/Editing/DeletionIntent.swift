import Foundation

/// Which way a delete keypress runs: backspace (`.backward`) or forward-delete /
/// fn⌫ (`.forward`).
public enum DeletionDirection: Sendable {
    case backward
    case forward
}

/// What a single delete keypress should do.
///
/// - `.characterwise`: fall back to the platform's normal one-character delete.
/// - `.ranges`: delete exactly these ranges as one undoable edit. The ranges are
///   **descending by location and non-overlapping**, so a caller can apply them
///   in order without recomputing offsets.
public enum DeletionAction: Equatable, Sendable {
    case characterwise
    case ranges([NSRange])
}

/// The marker-atom deletion model: once Markdown renders as a *thing*, deletion
/// operates on the thing. Marker runs (from `MarkdownToken.markerRanges`) are
/// atoms; visible content stays character-by-character.
///
/// Pure, platform-agnostic logic — it reads token marker geometry and the caret
/// only, with no AppKit/UIKit. The macOS wiring (and a future iOS port) feed it
/// the current token snapshot and route the result. Implements R1–R5 from the
/// plan (block prefixes, inline pairs, bracketed inlines, whole-line markers,
/// and forward-delete mirrors).
public enum DeletionIntent {
    /// Resolve what a delete keypress should do at `caret` given `tokens`.
    ///
    /// - Parameters:
    ///   - text: the full document text (UTF-16 indexed, like every `NSRange` here).
    ///   - tokens: the current whole-document token snapshot.
    ///   - caret: the current selection. A non-empty selection is always
    ///     `.characterwise` — deleting a selection deletes the selection.
    ///   - direction: backspace or forward-delete.
    public static func resolve(
        text: NSString,
        tokens: [MarkdownToken],
        caret: NSRange,
        direction: DeletionDirection
    ) -> DeletionAction {
        // Selections are untouched. IME / marked-text safety is the caller's job
        // (it has the text view); here we only model caret-at-boundary intent.
        if caret.length > 0 { return .characterwise }

        let pos = caret.location
        switch direction {
        case .backward where pos == 0:
            return .characterwise
        case .forward where pos >= text.length:
            return .characterwise
        default:
            break
        }

        // Gather every atom whose trigger boundary is exactly at the caret, then
        // pick the most specific (smallest total span) — this disambiguates a
        // caret that sits on a boundary shared by nested tokens.
        var best: [NSRange]?
        var bestSpan = Int.max
        for token in tokens {
            for atom in atoms(for: token, in: text) {
                let trigger = direction == .backward ? atom.backwardTrigger : atom.forwardTrigger
                guard trigger == pos, !atom.ranges.isEmpty else { continue }
                let span = atom.ranges.reduce(0) { $0 + $1.length }
                if span < bestSpan {
                    bestSpan = span
                    best = atom.ranges
                }
            }
        }

        guard let ranges = best else { return .characterwise }
        return .ranges(ranges.sorted { $0.location > $1.location })
    }

    /// The caret position after applying `ranges` from `pos` in `direction`.
    ///
    /// Backward deletes whatever sits behind the caret, so the caret slides left
    /// by the deleted length that lay before it (content to the left is kept and
    /// shifts with the caret). Forward deletes whatever sits ahead of the caret,
    /// so the caret stays put.
    public static func caretAfterDeletion(
        ranges: [NSRange],
        from pos: Int,
        direction: DeletionDirection
    ) -> Int {
        switch direction {
        case .forward:
            return pos
        case .backward:
            let deletedBefore = ranges.reduce(0) { acc, range in
                acc + max(0, min(range.location + range.length, pos) - range.location)
            }
            return pos - deletedBefore
        }
    }

    // MARK: - Atoms

    /// A deletable atom: the ranges it removes, plus the caret boundary that
    /// triggers it for each direction. `backwardTrigger` is the position
    /// *after* the atom (where a backspace lands); `forwardTrigger` is the
    /// position *before* it (where a forward-delete lands) — the R5 mirror.
    private struct Atom {
        let backwardTrigger: Int
        let forwardTrigger: Int
        let ranges: [NSRange]
    }

    private static func atoms(for token: MarkdownToken, in text: NSString) -> [Atom] {
        switch token.type {
        // R1 — block prefixes: delete the whole prefix, keep the indent.
        case .heading, .taskItem, .orderedListItem, .blockquote, .listItem:
            return blockPrefixAtoms(token, in: text)

        // R2 — inline pairs: unwrap (delete both marker runs, keep content).
        case .bold, .italic, .boldItalic, .strikethrough, .highlight, .inlineCode, .inlineMath:
            return pairAtom(token)

        // R3 — bracketed inlines: unwrap to the visible label/alt text.
        case .link, .image, .referenceLink, .footnoteReference:
            return bracketAtom(token)

        // R3 — autolink: its text *is* the URL, so delete the whole token.
        case .autolink:
            return [Atom(
                backwardTrigger: token.range.location + token.range.length,
                forwardTrigger: token.range.location,
                ranges: [token.range]
            )]

        // R4 — whole-line markers.
        case .horizontalRule:
            return wholeLineAtoms(token.markerRanges, in: text)
        case .codeBlock:
            return wholeLineAtoms(token.markerRanges, in: text)
        case .blockMath:
            return blockMathAtoms(token, in: text)

        // Tables, hashtags, and definition lines have no atomic-deletion rule.
        default:
            return []
        }
    }

    /// R1. The prefix runs from the end of the line's leading indent to the end
    /// of the marker run, clamped to the line's content (never eating the
    /// trailing newline). The indent survives — the next press deletes it.
    private static func blockPrefixAtoms(_ token: MarkdownToken, in text: NSString) -> [Atom] {
        guard let marker = token.markerRanges.first else { return [] }
        let lineStart = token.range.location
        let deleteStart = lineStart + leadingIndentLength(token.range, in: text)
        let contentEnd = lineContentEnd(token.range, in: text)
        let markerEnd = min(marker.location + marker.length, contentEnd)
        guard markerEnd > deleteStart else { return [] }
        let prefix = NSRange(location: deleteStart, length: markerEnd - deleteStart)
        return [Atom(backwardTrigger: markerEnd, forwardTrigger: deleteStart, ranges: [prefix])]
    }

    /// R2. Unwrap an inline pair by deleting its opening and closing marker runs,
    /// keeping the content between them.
    private static func pairAtom(_ token: MarkdownToken) -> [Atom] {
        guard token.markerRanges.count == 2 else { return [] }
        return [Atom(
            backwardTrigger: token.range.location + token.range.length,
            forwardTrigger: token.range.location,
            ranges: token.markerRanges
        )]
    }

    /// R3. Unwrap a bracketed inline to its visible text by deleting all of its
    /// marker machinery (every range in `markerRanges`).
    private static func bracketAtom(_ token: MarkdownToken) -> [Atom] {
        guard !token.markerRanges.isEmpty else { return [] }
        return [Atom(
            backwardTrigger: token.range.location + token.range.length,
            forwardTrigger: token.range.location,
            ranges: token.markerRanges
        )]
    }

    /// R4. Each marker range is a full line (delimiter + newline). One press at
    /// the line's content end deletes the whole line; forward-delete at the
    /// line start mirrors it. Code fences and multi-line math have two such
    /// lines (open + close); the caret picks which one fires.
    private static func wholeLineAtoms(_ markers: [NSRange], in text: NSString) -> [Atom] {
        markers.compactMap { marker in
            guard marker.length > 0 else { return nil }
            return Atom(
                backwardTrigger: lineContentEnd(marker, in: text),
                forwardTrigger: marker.location,
                ranges: [marker]
            )
        }
    }

    /// Block math is whole-line (R4) when its `$$` delimiters sit on their own
    /// lines, but a single-line `$$a = b$$` keeps its content visible, so it
    /// unwraps as an inline pair (R2) instead.
    private static func blockMathAtoms(_ token: MarkdownToken, in text: NSString) -> [Atom] {
        guard token.markerRanges.count == 2 else { return [] }
        let openLine = text.lineRange(for: token.markerRanges[0])
        let closeLine = text.lineRange(for: token.markerRanges[1])
        if openLine.location == closeLine.location {
            return pairAtom(token)
        }
        return wholeLineAtoms(token.markerRanges, in: text)
    }

    // MARK: - Line geometry

    /// Number of leading space/tab characters on the line.
    private static func leadingIndentLength(_ lineRange: NSRange, in text: NSString) -> Int {
        let end = lineRange.location + lineRange.length
        var i = lineRange.location
        while i < end {
            let c = text.character(at: i)
            guard c == 0x20 || c == 0x09 else { break }
            i += 1
        }
        return i - lineRange.location
    }

    /// The end of a range's visible content — its upper bound with any trailing
    /// `\n` / `\r` excluded, so whole-line deletions trigger at the last visible
    /// character, not on the newline.
    private static func lineContentEnd(_ range: NSRange, in text: NSString) -> Int {
        var end = range.location + range.length
        while end > range.location {
            let c = text.character(at: end - 1)
            guard c == 0x0A || c == 0x0D else { break }
            end -= 1
        }
        return end
    }
}
