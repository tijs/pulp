#if canImport(AppKit)
import AppKit

struct DrawingInfo {
    struct CheckboxItem {
        let rect: NSRect
        let checked: Bool
    }

    struct TableInfo {
        let backgroundRect: NSRect
        let headerRect: NSRect?
        let separatorY: CGFloat?
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
