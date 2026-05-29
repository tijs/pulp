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
    // Typography
    public var fontFamily: String
    public var bodySize: CGFloat
    public var headingSizes: [CGFloat]
    public var codeFontFamily: String
    public var markerShrinkSize: CGFloat

    // Text colors
    public var textColor: PulpColor
    public var secondaryTextColor: PulpColor
    public var tertiaryTextColor: PulpColor

    // Backgrounds
    public var backgroundColor: PulpColor
    public var codeBackgroundColor: PulpColor
    public var tableHeaderBackground: PulpColor
    public var tableRowStripeBackground: PulpColor

    // Lines
    public var borderColor: PulpColor
    public var strongBorderColor: PulpColor

    // Accent
    public var accentColor: PulpColor
    public var checkboxTintColor: PulpColor
    public var highlightColor: PulpColor

    public init(
        fontFamily: String = ".AppleSystemUIFont",
        bodySize: CGFloat = 16,
        headingSizes: [CGFloat] = [28, 24, 20, 18, 16, 14],
        codeFontFamily: String = "Menlo",
        markerShrinkSize: CGFloat = 0.1,
        textColor: PulpColor = PulpPalette.label,
        secondaryTextColor: PulpColor = PulpPalette.secondaryLabel,
        tertiaryTextColor: PulpColor = PulpPalette.tertiaryLabel,
        backgroundColor: PulpColor = PulpPalette.editorBackground,
        codeBackgroundColor: PulpColor = PulpPalette.fill(0.06),
        tableHeaderBackground: PulpColor = PulpPalette.pearGreenSoft,
        tableRowStripeBackground: PulpColor = PulpPalette.fill(0.04),
        borderColor: PulpColor = PulpPalette.fill(0.12),
        strongBorderColor: PulpColor = PulpPalette.fill(0.25),
        accentColor: PulpColor = PulpPalette.pearGreen,
        checkboxTintColor: PulpColor = PulpPalette.pearGreen,
        highlightColor: PulpColor = PulpColor.systemYellow.withAlphaComponent(0.3)
    ) {
        self.fontFamily = fontFamily
        self.bodySize = bodySize
        self.headingSizes = headingSizes
        self.codeFontFamily = codeFontFamily
        self.markerShrinkSize = markerShrinkSize
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.tertiaryTextColor = tertiaryTextColor
        self.backgroundColor = backgroundColor
        self.codeBackgroundColor = codeBackgroundColor
        self.tableHeaderBackground = tableHeaderBackground
        self.tableRowStripeBackground = tableRowStripeBackground
        self.borderColor = borderColor
        self.strongBorderColor = strongBorderColor
        self.accentColor = accentColor
        self.checkboxTintColor = checkboxTintColor
        self.highlightColor = highlightColor
    }

    public static let `default` = PulpTheme()

    // MARK: - Fonts

    public func bodyFont() -> PulpFont {
        PulpFont.systemFont(ofSize: bodySize)
    }

    public func headingFont(level: Int) -> PulpFont {
        let idx = max(0, min(level - 1, headingSizes.count - 1))
        let weight: PulpFont.Weight = level <= 3 ? .bold : .semibold
        return PulpFont.systemFont(ofSize: headingSizes[idx], weight: weight)
    }

    public func codeFont() -> PulpFont {
        PulpFont(name: codeFontFamily, size: bodySize) ?? PulpFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)
    }

    public func markerFont() -> PulpFont {
        PulpFont.systemFont(ofSize: markerShrinkSize)
    }

    public func tableFont() -> PulpFont {
        PulpFont.systemFont(ofSize: bodySize * 0.9)
    }

    public func tableHeaderFont() -> PulpFont {
        PulpFont.systemFont(ofSize: bodySize * 0.9, weight: .semibold)
    }
}
