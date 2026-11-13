import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Pannello senza bordi che riceve la tastiera senza attivare Copy8:
/// l'app in cui stai lavorando resta in primo piano e riceve l'incolla.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate, PanelActions {
    let model: PanelModel
    var onOpenSettings: (() -> Void)?
    private(set) var isShown = false

    private let panel: ClipPanel
    private let settings: Settings
    private let history: History
    private let watcher: ClipboardWatcher
    private let toast: ToastController
    private weak var searchField: NSTextField?
    private var keyMonitor: Any?
    private var askedForTrust = false

    init(settings: Settings, history: History, watcher: ClipboardWatcher, toast: ToastController) {
        self.settings = settings
        self.history = history
        self.watcher = watcher
        self.toast = toast
        model = PanelModel(history: history, settings: settings)
        panel = ClipPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.wideWidth, height: PanelMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self

        model.actions = self
        let root = PanelView(model: model, settings: settings, history: history) { [weak self] field in
            self?.searchField = field
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.cornerRadius = PanelMetrics.radius
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
        applySize()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    // MARK: Mostra e nascondi

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        model.prepareForShow()
        position()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        if let searchField { panel.makeFirstResponder(searchField) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        if reduceMotion {
            model.appeared = true
        } else {
            withAnimation(.easeOut(duration: 0.12)) { model.appeared = true }
        }
        panel.invalidateShadow()
    }

    func hide(animated: Bool = true) {
        guard isShown else { return }
        isShown = false
        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    /// Disegna il pannello una volta all'avvio, fuori schermo, così la prima apertura è immediata.
    func warmUp() {
        model.refresh()
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    func applySize() {
        let size = NSSize(width: settings.showPreview ? PanelMetrics.wideWidth : PanelMetrics.narrowWidth,
                          height: PanelMetrics.height)
        guard panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.x += (frame.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: isShown)
        panel.invalidateShadow()
    }

    func historyChanged() {
        if isShown { model.refresh() }
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let top = visible.maxY - visible.height * 0.16
        let origin = NSPoint(x: (visible.midX - size.width / 2).rounded(),
                             y: max(visible.minY + 16, top - size.height).rounded())
        panel.setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: Azioni

    func paste(_ item: ClipItem, plain: Bool) {
        let screen = panel.screen
        watcher.ignoredChangeCount = Paster.write(item, plain: plain, history: history)
        history.touch(item)
        hide(animated: false)
        guard settings.pasteDirectly else {
            toast.show("Copiato: premi ⌘V per incollare", on: screen)
            return
        }
        if Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.sendPaste() }
            toast.show(plain ? "Incollato come testo semplice" : "Incollato nell’app attiva", on: screen)
        } else {
            if !askedForTrust {
                askedForTrust = true
                Paster.requestTrust()
            }
            toast.show("Copiato: premi ⌘V per incollare", on: screen)
        }
    }

    func copy(_ item: ClipItem) {
        let screen = panel.screen
        watcher.ignoredChangeCount = Paster.write(item, plain: false, history: history)
        history.touch(item)
        hide(animated: false)
        toast.show("Copiato negli appunti", on: screen)
    }

    func delete(_ item: ClipItem) {
        history.delete(item)
    }

    func openSettings() {
        hide(animated: false)
        onOpenSettings?()
    }

    func focusSearch() {
        if let searchField { panel.makeFirstResponder(searchField) }
    }

    // MARK: Tastiera

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isShown, event.window === panel else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        switch Int(event.keyCode) {
        case kVK_DownArrow: model.move(by: 1); return true
        case kVK_UpArrow: model.move(by: -1); return true
        case kVK_PageDown: model.move(by: 8); return true
        case kVK_PageUp: model.move(by: -8); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem { paste(item, plain: mods.contains(.option)) }
            return true
        case kVK_Escape:
            if model.query.isEmpty { hide() } else { model.query = "" }
            return true
        default:
            break
        }

        guard mods == .command else { return false }
        if Int(event.keyCode) == kVK_Delete {
            if let item = model.selectedItem { delete(item) }
            return true
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let digit = Int(key), (1...9).contains(digit) {
            if digit <= model.results.count { paste(model.results[digit - 1], plain: false) }
            return true
        }
        switch key {
        case ",": openSettings(); return true
        case "w": hide(); return true
        case "a": return send(#selector(NSText.selectAll(_:)))
        case "x": return send(#selector(NSText.cut(_:)))
        case "v": return send(#selector(NSText.paste(_:)))
        case "z": return send(Selector(("undo:")))
        case "c":
            if let editor = panel.firstResponder as? NSTextView, editor.selectedRange().length > 0 {
                return send(#selector(NSText.copy(_:)))
            }
            if let item = model.selectedItem { copy(item) }
            return true
        default:
            return false
        }
    }

    private func send(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: nil)
        return true
    }
}
