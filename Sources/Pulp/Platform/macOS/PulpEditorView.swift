#if canImport(AppKit)
import AppKit
import SwiftUI

/// A handle a SwiftUI host can hold to drive editor commands (formatting, table
/// insertion, etc.) from its own chrome — a toolbar, menu, or floating bar. The
/// editor library stays neutral; the host owns the affordance.
public final class PulpEditorController: ObservableObject {
    public weak var editor: PulpEditorProtocol?
    public init() {}

    public var isReady: Bool {
        editor != nil
    }

    /// Insert a blank table at the caret. Defaults to a 3-column, 2-row table.
    public func insertTable(rows: Int = 2, columns: Int = 3) {
        editor?.insertTable(rows: rows, columns: columns)
    }

    public func insertTableRowBelow() {
        editor?.insertTableRowBelow()
    }

    public func insertTableRowAbove() {
        editor?.insertTableRowAbove()
    }

    public func insertTableColumnRight() {
        editor?.insertTableColumnRight()
    }

    public func insertTableColumnLeft() {
        editor?.insertTableColumnLeft()
    }

    public func deleteTableRow() {
        editor?.deleteTableRow()
    }

    public func deleteTableColumn() {
        editor?.deleteTableColumn()
    }

    /// Whether the caret currently sits inside a table (host can enable/disable
    /// table-editing affordances accordingly).
    public var isCaretInTable: Bool {
        editor?.tableCaretContext() != nil
    }
}

public struct PulpEditorView: NSViewRepresentable {
    @Binding var text: String
    var theme: PulpTheme
    var delegate: PulpEditorDelegate?
    var isEditable: Bool
    var controller: PulpEditorController?

    public init(
        text: Binding<String>,
        theme: PulpTheme = .default,
        delegate: PulpEditorDelegate? = nil,
        isEditable: Bool = true,
        controller: PulpEditorController? = nil
    ) {
        self._text = text
        self.theme = theme
        self.delegate = delegate
        self.isEditable = isEditable
        self.controller = controller
    }

    public func makeNSView(context: Context) -> PulpNSTextView {
        let editor = PulpNSTextView(theme: theme)
        editor.delegate = context.coordinator
        editor.isEditable = isEditable
        editor.setText(text)
        context.coordinator.editor = editor
        context.coordinator.externalDelegate = delegate
        controller?.editor = editor
        return editor
    }

    public func updateNSView(_ nsView: PulpNSTextView, context: Context) {
        context.coordinator.externalDelegate = delegate
        controller?.editor = nsView
        nsView.isEditable = isEditable

        let themeChanged = nsView.theme.bodySize != theme.bodySize ||
            nsView.theme.markerShrinkSize != theme.markerShrinkSize
        if themeChanged {
            nsView.theme = theme
        }

        if nsView.text != text, !context.coordinator.isUpdatingText {
            nsView.setText(text)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    public final class Coordinator: PulpEditorDelegate {
        @Binding var text: String
        var isUpdatingText = false
        weak var editor: PulpNSTextView?
        weak var externalDelegate: PulpEditorDelegate?

        init(text: Binding<String>) {
            _text = text
        }

        public func editor(_ editor: PulpEditorProtocol, didApplyEdit edit: TextEdit) {
            isUpdatingText = true
            text = editor.text
            isUpdatingText = false
            externalDelegate?.editor(editor, didApplyEdit: edit)
        }

        public func editor(_ editor: PulpEditorProtocol, didUpdateTitle title: String) {
            externalDelegate?.editor(editor, didUpdateTitle: title)
        }

        public func editor(_ editor: PulpEditorProtocol, didUpdateTags tags: [String]) {
            externalDelegate?.editor(editor, didUpdateTags: tags)
        }

        public func editor(_ editor: PulpEditorProtocol, didUpdateHasUncheckedTodos hasUncheckedTodos: Bool) {
            externalDelegate?.editor(editor, didUpdateHasUncheckedTodos: hasUncheckedTodos)
        }

        public func editor(_ editor: PulpEditorProtocol, didToggleCheckboxAtLine line: Int, checked: Bool) {
            externalDelegate?.editor(editor, didToggleCheckboxAtLine: line, checked: checked)
        }

        public func editor(_ editor: PulpEditorProtocol, didTapLink url: URL) {
            externalDelegate?.editor(editor, didTapLink: url)
        }

        public func editor(_ editor: PulpEditorProtocol, didTapHashtag tag: String) {
            externalDelegate?.editor(editor, didTapHashtag: tag)
        }
    }
}
#endif
