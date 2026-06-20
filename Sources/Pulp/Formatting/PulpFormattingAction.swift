import Foundation

/// A typed description of a single formatting command a host app can ask the
/// editor to perform. This is the host-facing contract: a SwiftUI toolbar,
/// menu, or floating bar holds a `PulpEditorController` and calls
/// `controller.perform(_:)` with one of these cases, instead of reaching for
/// individual `toggle…`/`insert…` methods. The editor library owns the actual
/// text mutation; the host owns the affordance.
public enum PulpFormattingAction: Equatable, Sendable {
    /// Inline emphasis toggles — wrap/unwrap the selection.
    case bold
    case italic
    case strikethrough
    case highlight
    case inlineCode

    /// Set the current line's heading to `level` (1...6); re-applying the same
    /// level removes it.
    case heading(Int)

    /// Block-level line-prefix toggles.
    case bulletList
    case numberList
    case taskList
    case blockquote

    /// Insert a Markdown link at the caret (wraps the selection if present).
    case link

    /// Insert a blank GFM table at the caret.
    case insertTable(rows: Int, columns: Int)
}
