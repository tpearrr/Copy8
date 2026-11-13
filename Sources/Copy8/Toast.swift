import AppKit
import Observation
import SwiftUI

@Observable
final class ToastModel {
    var message = ""
}

/// Conferma breve in alto al centro dello schermo. Non prende mai il fuoco né i clic.
@MainActor
final class ToastController {
    private let panel: NSPanel
    private let model = ToastModel()
    private var hideWork: DispatchWorkItem?
    private let size = NSSize(width: 520, height: 96)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
    }

    func show(_ message: String, on screen: NSScreen?) {
        model.message = message
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        // La pillola è centrata nel pannello: il suo bordo superiore cade 32 pt sotto la barra dei menu.
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - 32 - 40 - (size.height - 40) / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    self.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated { self?.panel.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

struct ToastView: View {
    let model: ToastModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
            Text(model.message)
                .font(.system(size: 13))
        }
        .foregroundStyle(Color.white)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .frame(height: 40)
        .background(Capsule().fill(Palette.hud))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
