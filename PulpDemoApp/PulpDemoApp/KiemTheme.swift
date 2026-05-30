import Pulp
import SwiftUI

/// Kiem's brand theme for the Pulp editor. This lives in the consuming app, not in
/// Pulp itself — Pulp ships a neutral default and accepts theming. The kiem-green
/// accent is Kiem's identity, supplied here.
enum KiemTheme {
    static let kiemGreen = PulpPalette.dynamicColor(
        light: (red: 0.20, green: 0.55, blue: 0.30, alpha: 1.0),
        dark: (red: 0.45, green: 0.85, blue: 0.55, alpha: 1.0)
    )

    static var theme: PulpTheme {
        PulpTheme(
            accentColor: kiemGreen,
            tableHeaderBackground: PulpPalette.accentWash(kiemGreen),
            checkboxTintColor: kiemGreen
        )
    }
}
