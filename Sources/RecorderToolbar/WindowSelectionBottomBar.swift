import AppKit
import SwiftUI

// MARK: – Full-width bottom bar for selection (window / display)
//
// Shown instead of the toolbar when selectionMode is active on styles that
// have both camera and mic controls visible (revealedAll, revealedAllCompact).
// Mimics the macOS native screen-capture bottom hint bar.

struct WindowSelectionBottomBarView: View {
    let message: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 4) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                HStack(spacing: 5) {
                    Text("esc")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Text("to exit")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
        }
    }
}

@MainActor
final class WindowSelectionBottomBarController {
    private var panel: NSPanel?

    func show(screen: NSScreen, level: NSWindow.Level, message: String) {
        panel?.orderOut(nil)

        let barH: CGFloat = 64
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: barH
        )

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel    = true
        p.level              = level
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance         = NSAppearance(named: .darkAqua)

        let hosting = NSHostingView(rootView: WindowSelectionBottomBarView(message: message))
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        p.contentView = hosting

        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        panel = p
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}
