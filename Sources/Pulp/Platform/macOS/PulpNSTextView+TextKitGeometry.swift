#if canImport(AppKit)
import AppKit

/// TextKit 2 geometry — the only place the editor reads layout coordinates.
///
/// Everything the editor custom-draws (code-block backgrounds, bullets,
/// checkboxes, tables, the frontmatter callout) needs just two measurements.
/// Both are returned in text-container coordinates; callers offset by
/// `textView.textContainerOrigin`, matching what TextKit 1 line-fragment
/// rects used to provide.
///
/// Nothing may touch `textView.layoutManager`: on a TextKit 2 text view that
/// getter silently swaps in a TextKit 1 compatibility stack for the life of
/// the view.
extension PulpNSTextView {
    /// Union of the rendered segment frames for a character range, in text
    /// container coordinates. Nil when the range has no laid-out content.
    /// Only the vertical extent is meaningful to callers — segment frames
    /// hug the text horizontally, where line fragments spanned the container.
    func segmentUnionRect(forCharacterRange range: NSRange) -> NSRect? {
        guard let tlm = textView.textLayoutManager,
              let textRange = textRange(from: range) else { return nil }
        tlm.ensureLayout(for: textRange)
        var union = NSRect.zero
        tlm.enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            union = union == .zero ? frame : union.union(frame)
            return true
        }
        return union == .zero ? nil : union
    }

    /// The rect of the (wrapped) line containing `characterIndex`, in text
    /// container coordinates — the first line of a token, for hanging a
    /// bullet/checkbox glyph or positioning a horizontal rule.
    func lineRect(forCharacterAt characterIndex: Int) -> NSRect? {
        segmentUnionRect(forCharacterRange: NSRange(location: characterIndex, length: 1))
    }

    /// Lay out the whole document now (test seam; normal drawing lays out
    /// per-range in `segmentUnionRect`).
    func ensureFullLayout() {
        guard let tlm = textView.textLayoutManager else { return }
        tlm.ensureLayout(for: tlm.documentRange)
    }

    private func textRange(from range: NSRange) -> NSTextRange? {
        guard let tcm = textView.textLayoutManager?.textContentManager,
              let start = tcm.location(tcm.documentRange.location, offsetBy: range.location),
              let end = tcm.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
#endif
