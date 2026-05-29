#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform semantic colors. Resolves to the correct `NSColor` / `UIColor`
/// per platform and adapts automatically to light/dark mode.
public enum PulpPalette {
    public static var label: PulpColor {
        #if canImport(AppKit)
        .labelColor
        #else
        .label
        #endif
    }

    public static var secondaryLabel: PulpColor {
        #if canImport(AppKit)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }

    public static var tertiaryLabel: PulpColor {
        #if canImport(AppKit)
        .tertiaryLabelColor
        #else
        .tertiaryLabel
        #endif
    }

    public static var editorBackground: PulpColor {
        #if canImport(AppKit)
        .textBackgroundColor
        #else
        .systemBackground
        #endif
    }

    public static var accent: PulpColor {
        #if canImport(AppKit)
        .controlAccentColor
        #else
        .tintColor
        #endif
    }

    /// Subtle fill for code/table backgrounds. Low-alpha label adapts to dark mode
    /// reliably on both platforms (avoids using foreground label colors as fills).
    public static func fill(_ alpha: CGFloat) -> PulpColor {
        label.withAlphaComponent(alpha)
    }

    /// Pear-green brand accent. A muted, natural green (not the vibrant system green),
    /// brighter in dark mode for contrast. Used for links, bullets, checkboxes.
    public static let pearGreen: PulpColor = dynamicColor(
        light: PulpColor(red: 0.36, green: 0.62, blue: 0.38, alpha: 1.0),
        dark: PulpColor(red: 0.50, green: 0.78, blue: 0.52, alpha: 1.0)
    )

    /// A faint pear-green wash for highlights / accents-as-background.
    public static let pearGreenSoft: PulpColor = dynamicColor(
        light: PulpColor(red: 0.36, green: 0.62, blue: 0.38, alpha: 0.18),
        dark: PulpColor(red: 0.50, green: 0.78, blue: 0.52, alpha: 0.24)
    )

    static func dynamicColor(light: PulpColor, dark: PulpColor) -> PulpColor {
        #if canImport(AppKit)
        return PulpColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }
        #else
        return PulpColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        #endif
    }
}
