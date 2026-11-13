import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Paster {
    /// Mette l'elemento negli appunti di sistema e restituisce il nuovo `changeCount`.
    @MainActor
    static func write(_ item: ClipItem, plain: Bool, history: History) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .image:
            if let url = history.imageURL(for: item), let png = try? Data(contentsOf: url) {
                let entry = NSPasteboardItem()
                entry.setData(png, forType: .png)
                if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                    entry.setData(tiff, forType: .tiff)
                }
                pasteboard.writeObjects([entry])
            }
        case .file:
            if plain {
                pasteboard.setString(item.text, forType: .string)
            } else {
                pasteboard.writeObjects(item.fileURLs as [NSURL])
            }
        default:
            let entry = NSPasteboardItem()
            if !plain {
                let rich = history.richData(for: item)
                if let rtf = rich.rtf { entry.setData(rtf, forType: .rtf) }
                if let html = rich.html { entry.setData(html, forType: .html) }
                if item.kind == .link { entry.setString(item.text, forType: .URL) }
            }
            entry.setString(item.text, forType: .string)
            pasteboard.writeObjects([entry])
        }
        return pasteboard.changeCount
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Mostra la richiesta di sistema per il permesso Accessibilità.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Simula ⌘V nell'app attiva. Richiede il permesso Accessibilità.
    static func sendPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let key = KeyboardLayout.keyCode(producing: "v") ?? CGKeyCode(kVK_ANSI_V)
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0000_0008)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
