import AppKit
import Carbon.HIToolbox

/// Una combinazione di tasti globale.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt
    var key: String

    static let `default` = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        key: "V"
    )

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Una combinazione valida richiede almeno ⌘, ⌃ o ⌥.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = flags.rawValue
        key = KeyboardLayout.label(for: event.keyCode)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    /// Simboli nell'ordine standard di macOS: ⌃ ⌥ ⇧ ⌘ tasto.
    var symbols: [String] {
        var out: [String] = []
        if flags.contains(.control) { out.append("⌃") }
        if flags.contains(.option) { out.append("⌥") }
        if flags.contains(.shift) { out.append("⇧") }
        if flags.contains(.command) { out.append("⌘") }
        out.append(key)
        return out
    }

    var spokenDescription: String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("Controllo") }
        if flags.contains(.option) { parts.append("Opzione") }
        if flags.contains(.shift) { parts.append("Maiuscole") }
        if flags.contains(.command) { parts.append("Comando") }
        parts.append(key)
        return parts.joined(separator: " ")
    }
}

enum KeyboardLayout {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Spazio", 51: "⌫", 53: "esc", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func label(for keyCode: UInt16) -> String {
        if let name = special[keyCode] { return name }
        return character(for: keyCode)?.uppercased() ?? "?"
    }

    /// Il carattere che il tasto produce senza modificatori nel layout attivo.
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    /// Il codice del tasto che produce `char` nel layout attivo (per ⌘V su layout non QWERTY).
    static func keyCode(producing char: String) -> CGKeyCode? {
        for code in 0..<128 where special[UInt16(code)] == nil {
            if character(for: UInt16(code))?.lowercased() == char { return CGKeyCode(code) }
        }
        return nil
    }
}

/// Registra una scorciatoia globale con Carbon: non serve il permesso Accessibilità.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4350_5938), id: 1) // "CPY8"
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKeyCenter.shared.onPress?()
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
