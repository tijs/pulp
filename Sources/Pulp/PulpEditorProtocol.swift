import Foundation

/// The editor surface is UI: every requirement reads or drives view state.
@MainActor
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

    /// The table cell currently activated by a click (control button shown),
    /// independent of the text caret. Platform views that support in-cell editing
    /// provide this so structural table commands target the clicked cell.
    var activeTableCell: TableCellRef? { get }
}

public extension PulpEditorProtocol {
    var activeTableCell: TableCellRef? {
        nil
    }
}
