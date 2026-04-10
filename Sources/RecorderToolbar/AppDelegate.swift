import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let state = ToolbarState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: ToolbarView(state: state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Ensure transparent corners so the panel shadow follows the rounded content shape.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel             = true
        panel.level                       = .floating
        panel.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor             = .clear
        panel.isOpaque                    = false
        panel.hasShadow                   = true
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)

        // Visual effect (vibrancy)
        let vfx = NSVisualEffectView()
        vfx.blendingMode       = .behindWindow
        vfx.material           = .underWindowBackground
        vfx.state              = .active
        vfx.wantsLayer         = true
        vfx.layer?.cornerRadius    = 10
        vfx.layer?.masksToBounds   = true

        vfx.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])

        panel.contentView = vfx
        panel.setContentSize(CGSize(width: 389, height: 56))

        // Position: horizontally centered, near bottom of screen
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let x  = screen.visibleFrame.minX + (sw - 389) / 2
            let y  = screen.visibleFrame.minY + 42
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        panel.invalidateShadow()   // recompute shadow from rounded content alpha

        // Give ToolbarState a reference to the panel for overlay positioning
        state.panel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}
