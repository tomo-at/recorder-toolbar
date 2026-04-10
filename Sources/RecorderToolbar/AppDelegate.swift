import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let toolbar = ToolbarView()
        let hosting  = NSHostingView(rootView: toolbar)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel       = true
        panel.level                 = .floating
        panel.collectionBehavior    = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor       = .clear
        panel.isOpaque              = false
        panel.hasShadow             = true
        panel.isMovableByWindowBackground = true

        // Force dark appearance
        panel.appearance = NSAppearance(named: .darkAqua)

        // Visual effect (vibrancy)
        let vfx = NSVisualEffectView()
        vfx.blendingMode  = .behindWindow
        vfx.material      = .underWindowBackground
        vfx.state         = .active
        vfx.wantsLayer    = true
        vfx.layer?.cornerRadius = 10
        vfx.layer?.masksToBounds = true

        vfx.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])

        panel.contentView = vfx
        panel.setContentSize(CGSize(width: 389, height: 68))

        // Center horizontally near bottom of screen
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let sy = screen.visibleFrame.minY
            let x  = screen.visibleFrame.minX + (sw - 389) / 2
            let y  = sy + 42
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false
    }
}
