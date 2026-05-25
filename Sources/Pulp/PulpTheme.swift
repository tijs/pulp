#if canImport(AppKit)
import AppKit

public typealias PulpColor = NSColor
public typealias PulpFont = NSFont
#elseif canImport(UIKit)
import UIKit

public typealias PulpColor = UIColor
public typealias PulpFont = UIFont
#endif

public struct PulpTheme: Sendable {
    public var fontFamily: String
    public var bodySize: CGFloat
    public var headingSizes: [CGFloat]
    public var codeFontFamily: String
    public var markerShrinkSize: CGFloat
    public var accentColor: PulpColor
    public var checkboxTintColor: PulpColor
    public var textColor: PulpColor
    public var secondaryTextColor: PulpColor
    public var codeBackgroundColor: PulpColor
    public var backgroundColor: PulpColor

    public init(
        fontFamily: String = ".AppleSystemUIFont",
        bodySize: CGFloat = 16,
        headingSizes: [CGFloat] = [28, 24, 20, 18, 16, 14],
        codeFontFamily: String = "Menlo",
        markerShrinkSize: CGFloat = 0.1,
        accentColor: PulpColor = .systemBlue,
        checkboxTintColor: PulpColor = .systemBlue,
        textColor: PulpColor = .labelColor,
        secondaryTextColor: PulpColor = .secondaryLabelColor,
        codeBackgroundColor: PulpColor = .quaternaryLabelColor,
        backgroundColor: PulpColor = .textBackgroundColor
    ) {
        self.fontFamily = fontFamily
        self.bodySize = bodySize
        self.headingSizes = headingSizes
        self.codeFontFamily = codeFontFamily
        self.markerShrinkSize = markerShrinkSize
        self.accentColor = accentColor
        self.checkboxTintColor = checkboxTintColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.codeBackgroundColor = codeBackgroundColor
        self.backgroundColor = backgroundColor
    }

    public static let `default` = PulpTheme()

    public func bodyFont() -> PulpFont {
        PulpFont.systemFont(ofSize: bodySize)
    }

    public func headingFont(level: Int) -> PulpFont {
        let idx = max(0, min(level - 1, headingSizes.count - 1))
        return PulpFont.boldSystemFont(ofSize: headingSizes[idx])
    }

    public func codeFont() -> PulpFont {
        PulpFont(name: codeFontFamily, size: bodySize) ?? PulpFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
    }

    public func markerFont() -> PulpFont {
        PulpFont.systemFont(ofSize: markerShrinkSize)
    }
}
