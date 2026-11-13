import AppKit
import Observation

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }
}

@Observable
final class Settings {
    enum Change { case days, theme, preview, hotKey, other }

    static let shared = Settings()
    static let dayRange = 1...365

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onChange: ((Change) -> Void)?

    var days: Int {
        didSet { defaults.set(days, forKey: Keys.days); onChange?(.days) }
    }
    var pasteDirectly: Bool {
        didSet { defaults.set(pasteDirectly, forKey: Keys.pasteDirectly); onChange?(.other) }
    }
    var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme); onChange?(.theme) }
    }
    var showPreview: Bool {
        didSet { defaults.set(showPreview, forKey: Keys.showPreview); onChange?(.preview) }
    }
    var glass: Bool {
        didSet { defaults.set(glass, forKey: Keys.glass); onChange?(.other) }
    }
    var glassIntensity: Double {
        didSet { defaults.set(glassIntensity, forKey: Keys.glassIntensity); onChange?(.other) }
    }
    var ignoreConfidential: Bool {
        didSet { defaults.set(ignoreConfidential, forKey: Keys.ignoreConfidential); onChange?(.other) }
    }
    var hotKey: KeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) { defaults.set(data, forKey: Keys.hotKey) }
            onChange?(.hotKey)
        }
    }

    /// Non salvato: vero quando il sistema rifiuta la scorciatoia scelta.
    var hotKeyUnavailable = false

    private enum Keys {
        static let days = "days"
        static let pasteDirectly = "pasteDirectly"
        static let theme = "theme"
        static let showPreview = "showPreview"
        static let glass = "glass"
        static let glassIntensity = "glassIntensity"
        static let ignoreConfidential = "ignoreConfidential"
        static let hotKey = "hotKey"
    }

    private init() {
        defaults.register(defaults: [
            Keys.days: 7,
            Keys.pasteDirectly: true,
            Keys.theme: ThemePreference.system.rawValue,
            Keys.showPreview: true,
            Keys.glass: true,
            Keys.glassIntensity: 60.0,
            Keys.ignoreConfidential: true,
        ])
        days = min(max(defaults.integer(forKey: Keys.days), Settings.dayRange.lowerBound), Settings.dayRange.upperBound)
        pasteDirectly = defaults.bool(forKey: Keys.pasteDirectly)
        theme = ThemePreference(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        showPreview = defaults.bool(forKey: Keys.showPreview)
        glass = defaults.bool(forKey: Keys.glass)
        glassIntensity = min(max(defaults.double(forKey: Keys.glassIntensity), 1), 100)
        ignoreConfidential = defaults.bool(forKey: Keys.ignoreConfidential)
        if let data = defaults.data(forKey: Keys.hotKey), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .default
        }
    }
}
