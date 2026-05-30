import Pulp
import SwiftUI

/// Kiem's brand theme for the Pulp editor. This lives in the consuming app, not in
/// Pulp itself — Pulp ships a neutral default and accepts theming. The kiem-green
/// accent is Kiem's identity, supplied here.
enum KiemTheme {
    static let kiemGreen = PulpPalette.dynamicColor(
        light: PulpColor(red: 0.36, green: 0.62, blue: 0.38, alpha: 1.0),
        dark: PulpColor(red: 0.50, green: 0.78, blue: 0.52, alpha: 1.0)
    )

    static var theme: PulpTheme {
        PulpTheme(
            tableHeaderBackground: PulpPalette.accentWash(kiemGreen),
            accentColor: kiemGreen,
            checkboxTintColor: kiemGreen
        )
    }
}
