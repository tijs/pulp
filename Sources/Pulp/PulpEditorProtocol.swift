import Foundation

public protocol PulpEditorProtocol: AnyObject {
    var delegate: PulpEditorDelegate? { get set }
    var text: String { get }
    var derivedTitle: String { get }
    var derivedTags: [String] { get }
    var hasUncheckedTodos: Bool { get }
    var selectedRange: NSRange { get set }
    var theme: PulpTheme { get set }
    var isEditable: Bool { get set }

    func setText(_ text: String)
    func applyRemoteEdit(_ edit: TextEdit)
}
