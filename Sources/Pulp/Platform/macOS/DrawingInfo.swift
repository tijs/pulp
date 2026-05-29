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
    }

    struct TableRowData {
        let cells: [String]
        let isHeader: Bool
    }

    var codeBlockRects: [NSRect] = []
    var bulletRects: [NSRect] = []
    var checkboxItems: [CheckboxItem] = []
    var horizontalRuleRects: [NSRect] = []
    var tableInfos: [TableInfo] = []
    var theme: PulpTheme = .default

    static let empty = DrawingInfo()
}
#endif
