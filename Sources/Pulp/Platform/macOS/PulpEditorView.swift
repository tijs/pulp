#if canImport(AppKit)
import AppKit
import SwiftUI

public struct PulpEditorView: NSViewRepresentable {
    @Binding var text: String
    var theme: PulpTheme
    var delegate: PulpEditorDelegate?
    var isEditable: Bool

    public init(
        text: Binding<String>,
        theme: PulpTheme = .default,
        delegate: PulpEditorDelegate? = nil,
        isEditable: Bool = true
    ) {
        self._text = text
        self.theme = theme
        self.delegate = delegate
        self.isEditable = isEditable
    }

    public func makeNSView(context: Context) -> PulpNSTextView {
        let editor = PulpNSTextView(theme: theme)
        editor.delegate = context.coordinator
        editor.isEditable = isEditable
        editor.setText(text)
        context.coordinator.editor = editor
        context.coordinator.externalDelegate = delegate
        return editor
    }

    public func updateNSView(_ nsView: PulpNSTextView, context: Context) {
        context.coordinator.externalDelegate = delegate
        nsView.isEditable = isEditable

        if nsView.theme.bodySize != theme.bodySize ||
            nsView.theme.markerShrinkSize != theme.markerShrinkSize
        {
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
