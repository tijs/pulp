import Foundation

/// Editor callbacks fire from view/layout work, always on the main actor.
@MainActor
public protocol PulpEditorDelegate: AnyObject {
    func editor(_ editor: PulpEditorProtocol, didApplyEdit edit: TextEdit)
    func editor(_ editor: PulpEditorProtocol, didUpdateTitle title: String)
    func editor(_ editor: PulpEditorProtocol, didUpdateTags tags: [String])
    func editor(_ editor: PulpEditorProtocol, didUpdateHasUncheckedTodos hasUncheckedTodos: Bool)
    func editor(_ editor: PulpEditorProtocol, didToggleCheckboxAtLine line: Int, checked: Bool)
    func editor(_ editor: PulpEditorProtocol, didTapLink url: URL)
    func editor(_ editor: PulpEditorProtocol, didTapHashtag tag: String)
}

public extension PulpEditorDelegate {
    func editor(_ editor: PulpEditorProtocol, didUpdateTitle title: String) {}
    func editor(_ editor: PulpEditorProtocol, didUpdateTags tags: [String]) {}
    func editor(_ editor: PulpEditorProtocol, didUpdateHasUncheckedTodos hasUncheckedTodos: Bool) {}
    func editor(_ editor: PulpEditorProtocol, didToggleCheckboxAtLine line: Int, checked: Bool) {}
    func editor(_ editor: PulpEditorProtocol, didTapLink url: URL) {}
    func editor(_ editor: PulpEditorProtocol, didTapHashtag tag: String) {}
}
