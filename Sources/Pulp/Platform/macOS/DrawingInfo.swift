#if canImport(AppKit)
import AppKit

struct DrawingInfo {
    struct CheckboxItem {
        let rect: NSRect
        let checked: Bool
    }

    struct TableInfo {
        let backgroundRect: NSRect
        let rowHeight: CGFloat
        let columnWidths: [CGFloat]
        let rows: [TableRowData]
        let borderColor: PulpColor
        let strongBorderColor: PulpColor
        let headerBackground: PulpColor
        let rowStripeBackground: PulpColor
        let font: PulpFont
        let headerFont: PulpFont
        let textColor: PulpColor
        /// Display row/column whose text is suppressed because an inline editor
        /// covers it (avoids drawing the cell text twice). nil when not editing.
        var editingCell: (displayRow: Int, column: Int)?
    }

    struct TableRowData {
        let cells: [String]
        let isHeader: Bool
    }

    /// The control button shown in the active table cell (where the caret is).
    struct TableControl {
        let buttonRect: NSRect
        let accentColor: PulpColor
    }

    var codeBlockRects: [NSRect] = []
    var bulletRects: [NSRect] = []
    var checkboxItems: [CheckboxItem] = []
    var horizontalRuleRects: [NSRect] = []
    var tableInfos: [TableInfo] = []
    var tableControl: TableControl?
    var theme: PulpTheme = .default

    static let empty = DrawingInfo()
}
#endif
