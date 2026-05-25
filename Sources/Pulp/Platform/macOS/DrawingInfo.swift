#if canImport(AppKit)
import AppKit

struct DrawingInfo {
    struct CheckboxItem {
        let rect: NSRect
        let checked: Bool
    }

    var codeBlockRects: [NSRect] = []
    var bulletRects: [NSRect] = []
    var checkboxItems: [CheckboxItem] = []
    var horizontalRuleRects: [NSRect] = []
    var theme: PulpTheme = .default

    static let empty = DrawingInfo()
}
#endif
