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

    /// A subtle accent wash for header tints etc. — derived from any accent color.
    public static func accentWash(_ color: PulpColor, alpha: CGFloat = 0.18) -> PulpColor {
        color.withAlphaComponent(alpha)
    }

    /// Builds a light/dark adaptive color. Exposed so consumers can define brand
    /// colors that adapt to appearance without reimplementing the platform shim.
    public static func dynamicColor(light: PulpColor, dark: PulpColor) -> PulpColor {
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
