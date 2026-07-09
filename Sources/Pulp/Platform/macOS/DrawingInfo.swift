#if canImport(AppKit)
import AppKit

struct DrawingInfo {
    struct CheckboxItem {
        let rect: NSRect
        let checked: Bool
    }

    /// Bullet glyph for an unordered-list item. The shape cycles by nesting depth,
    /// matching common editors (Bear): filled dot → hollow ring → filled diamond.
    enum BulletStyle {
        case filledDot
        case ring
        case diamond

        /// The glyph for a given nesting depth (depth 0 = filled dot).
        static func forDepth(_ depth: Int) -> BulletStyle {
            switch max(0, depth) % 3 {
            case 1: .ring
            case 2: .diamond
            default: .filledDot
            }
        }
    }

    struct BulletItem {
        let rect: NSRect
        let style: BulletStyle
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
    var frontmatterRects: [NSRect] = []
    var bulletItems: [BulletItem] = []
    var checkboxItems: [CheckboxItem] = []
    var horizontalRuleRects: [NSRect] = []
    var tableInfos: [TableInfo] = []
    var tableControl: TableControl?
    var theme: PulpTheme = .default

    @MainActor static let empty = DrawingInfo()
}
#endif
