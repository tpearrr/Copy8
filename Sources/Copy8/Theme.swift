import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// Token del design system Copy8, aspetto chiaro e scuro.
enum Tokens {
    static let window = NSColor.adaptive(light: NSColor(hex: 0xF5F5F7), dark: NSColor(hex: 0x1E1E20))
    static let surface = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x2A2A2D))
    static let fill = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.05), dark: NSColor(hex: 0xFFFFFF, alpha: 0.08))
    static let separator = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.10), dark: NSColor(hex: 0xFFFFFF, alpha: 0.10))
    static let text = NSColor.adaptive(light: NSColor(hex: 0x1D1D1F), dark: NSColor(hex: 0xF5F5F7))
    static let text2 = NSColor.adaptive(light: NSColor(hex: 0x636368), dark: NSColor(hex: 0xAEAEB2))
    static let accent = NSColor.adaptive(light: NSColor(hex: 0x0064E1), dark: NSColor(hex: 0x1A6FE0))
    static let accentText = NSColor.adaptive(light: NSColor(hex: 0x0064E1), dark: NSColor(hex: 0x4C9BFF))
    static let highlight = NSColor.adaptive(light: NSColor(hex: 0xFFE58A), dark: NSColor(hex: 0x74661F))
    static let danger = NSColor.adaptive(light: NSColor(hex: 0xD70015), dark: NSColor(hex: 0xFF6961))
    static let iconForeground = NSColor.adaptive(light: NSColor(hex: 0x48484D), dark: NSColor(hex: 0xD1D1D6))
    static let keyEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.14), dark: NSColor(hex: 0xFFFFFF, alpha: 0.14))
    static let field = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0xFFFFFF, alpha: 0.06))
    static let fieldEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.18), dark: NSColor(hex: 0xFFFFFF, alpha: 0.16))
    static let groupEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.07), dark: NSColor(hex: 0xFFFFFF, alpha: 0.06))
    static let button = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x4A4A4E))
    static let buttonEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.16), dark: NSColor(hex: 0x000000, alpha: 0.50))
    static let hud = NSColor.adaptive(light: NSColor(hex: 0x1C1C1E, alpha: 0.86), dark: NSColor(hex: 0x3A3A3E, alpha: 0.92))
    static let modalEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.14), dark: NSColor(hex: 0x000000, alpha: 0.60))
    static let modalInnerEdge = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0), dark: NSColor(hex: 0xFFFFFF, alpha: 0.10))
    static let glassInnerEdge = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.55), dark: NSColor(hex: 0xFFFFFF, alpha: 0.12))
    /// Alone dietro il testo quando il vetro è trasparente: opposto al colore del testo.
    static let halo = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x000000))
}

enum Palette {
    static let window = Color(nsColor: Tokens.window)
    static let surface = Color(nsColor: Tokens.surface)
    static let fill = Color(nsColor: Tokens.fill)
    static let separator = Color(nsColor: Tokens.separator)
    static let text = Color(nsColor: Tokens.text)
    static let text2 = Color(nsColor: Tokens.text2)
    static let accent = Color(nsColor: Tokens.accent)
    static let accentText = Color(nsColor: Tokens.accentText)
    static let highlight = Color(nsColor: Tokens.highlight)
    static let danger = Color(nsColor: Tokens.danger)
    static let iconForeground = Color(nsColor: Tokens.iconForeground)
    static let keyEdge = Color(nsColor: Tokens.keyEdge)
    static let field = Color(nsColor: Tokens.field)
    static let fieldEdge = Color(nsColor: Tokens.fieldEdge)
    static let groupEdge = Color(nsColor: Tokens.groupEdge)
    static let button = Color(nsColor: Tokens.button)
    static let buttonEdge = Color(nsColor: Tokens.buttonEdge)
    static let hud = Color(nsColor: Tokens.hud)
    static let modalEdge = Color(nsColor: Tokens.modalEdge)
    static let modalInnerEdge = Color(nsColor: Tokens.modalInnerEdge)
    static let glassInnerEdge = Color(nsColor: Tokens.glassInnerEdge)
    static let halo = Color(nsColor: Tokens.halo)
}

/// Effetto vetro: un solo valore (1–100) va dalla superficie quasi piena al vetro lucido.
/// Strati: brina (sfocatura) e tinta sotto il contenuto, riflessi sopra.
enum Glass {
    /// L'intensità 100 corrisponde al 75 della scala precedente: oltre, il vetro diventava troppo trasparente.
    private static let maxProgress = 74.0 / 99.0

    private static func progress(_ intensity: Double) -> Double {
        (min(max(intensity, 1), 100) - 1) / 99 * maxProgress
    }

    private static func smoothstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let u = min(1, max(0, (x - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }

    /// Opacità della tinta di superficie: 94% a intensità 1, circa 24% a intensità 100.
    static func tint(_ intensity: Double) -> Double {
        0.94 * (1 - progress(intensity))
    }

    /// Quanto resta della sfocatura: piena fino a circa 40, circa 30% a intensità 100.
    static func frost(_ intensity: Double) -> Double {
        1 - smoothstep(0.3, 1, progress(intensity))
    }

    /// Forza di riflessi e alone del testo: compaiono da circa 54, circa 62% a intensità 100.
    static func gloss(_ intensity: Double) -> Double {
        smoothstep(0.4, 1, progress(intensity))
    }
}

enum PanelMetrics {
    static let wideWidth: CGFloat = 780
    static let narrowWidth: CGFloat = 520
    static let height: CGFloat = 540
    static let listWidth: CGFloat = 340
    static let radius: CGFloat = 18
}
