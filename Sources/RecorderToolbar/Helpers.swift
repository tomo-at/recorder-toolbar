import AppKit
import AVFoundation
import SwiftUI

// MARK: – Airtime Design System トークン
//
// ソース: ~/workspace/airtime-design-system-main/tokens/colors.json
// ツールバーは常に darkAqua なので dark mode 値を使用。

extension Color {
    // ── Modeless（テーマ非依存）────────────────────────────
    static let modelessWhite        = Color.white                                                // #FFFFFF
    static let modelessWhite24      = Color.white.opacity(0.24)                                  // #FFFFFF3D
    static let modelessBlack        = Color.black                                                // #000000
    static let modelessBlack24      = Color.black.opacity(0.24)                                  // #0000003D
    static let modelessOverlay      = Color.black.opacity(0.50)                                  // #00000080
    static let modelessTeal         = Color(red: 0x79/255, green: 0xDD/255, blue: 0xE8/255)      // #79DDE8
    static let modelessDestructive  = Color(red: 0xFF/255, green: 0x6D/255, blue: 0x4C/255)      // #FF6D4C
    static let modelessSilhouette   = Color(red: 0x8A/255, green: 0x90/255, blue: 0x97/255)      // #8A9097

    // ── Dark mode ──────────────────────────────────────────
    static let bgPrimary            = Color(red: 0x0A/255, green: 0x0D/255, blue: 0x0E/255)      // #0A0D0E
    static let bgSecondary          = Color(red: 0x12/255, green: 0x18/255, blue: 0x1A/255)      // #12181A
    static let bgTertiary           = Color(red: 0x1B/255, green: 0x23/255, blue: 0x26/255)      // #1B2326
    static let contentPrimary       = Color.white                                                // #FFFFFF
    static let contentSecondary     = Color(red: 0xD2/255, green: 0xD5/255, blue: 0xD6/255)      // #D2D5D6
    static let contentTertiary      = Color(red: 0xB0/255, green: 0xB1/255, blue: 0xB2/255)      // #B0B1B2
    static let highlightPrimary     = Color.white.opacity(0x14/255)                              // #FFFFFF14 ≈ 8%
    static let highlightSecondary   = Color.white.opacity(0x29/255)                              // #FFFFFF29 ≈ 16%
    static let accentTeal           = Color(red: 0x79/255, green: 0xDD/255, blue: 0xE8/255)      // #79DDE8 (= modelessTeal)
    static let accentDestructive    = Color(red: 0xFF/255, green: 0x6D/255, blue: 0x4C/255)      // #FF6D4C (= modelessDestructive)
    static let shadowSmall          = Color.black.opacity(0x3D/255)                              // #0000003D
    static let shadowMedium         = Color.black.opacity(0x7A/255)                              // #0000007A
    static let shadowLarge          = Color.black.opacity(0xB8/255)                              // #000000B8

    // ── UI surface colors ──────────────────────────────────
    static let bgTooltip       = Color(red: 0.22, green: 0.22, blue: 0.22)              // #383838 (tooltip / menu popup bg)

    // ── Legacy aliases（旧名、DS 正式名へ移行予定）─────────
    static let selectionOrange = modelessDestructive                    // 旧 #FF6D4C
    static let recordRed       = Color(red: 0xD6/255, green: 0x40/255, blue: 0x2F/255)  // #D6402F (DS light accent-destructive)
    static let selectedGreen   = Color(red: 0.188, green: 0.820, blue: 0.345)           // DS 外
    static let subtitleGray    = contentTertiary                       // 旧 #B0B1B2 へ統合
    static let deviceMenuBg    = bgSecondary                           // 旧値を DS #12181A へ統合
}

// MARK: – KeyablePanel (non-activating but accepts key events for Esc handling)

/// NSPanel subclass that can become key window while remaining non-activating.
/// Allows local key event monitoring (e.g., Esc to cancel overlay selection).
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: – NSPanel factory

extension NSPanel {
    /// Standard floating panel used throughout the app: borderless, nonactivating,
    /// clear background, dark appearance, shadow enabled.
    static func makeFloating(level: NSWindow.Level = .floating) -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel    = true
        p.level              = level
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = true
        p.appearance         = NSAppearance(named: .darkAqua)
        return p
    }
}

// MARK: – Primary screen height (CG ↔ AppKit Y-flip reference)

extension NSScreen {
    /// Height of the primary screen (frame.origin == .zero).
    /// Used as the Y-flip reference when converting CoreGraphics coords to AppKit/SwiftUI.
    static var primaryHeight: CGFloat {
        screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 800
    }
}

// MARK: – NSWindow factory for full-screen overlays

extension NSWindow {
    /// Transparent passthrough overlay window: ignoresMouseEvents, covers all spaces,
    /// no shadow, not released when closed.
    static func makeOverlay(frame: NSRect, level: NSWindow.Level) -> NSWindow {
        let w = NSWindow(contentRect: frame,
                         styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.level                = level
        w.backgroundColor      = .clear
        w.isOpaque             = false
        w.hasShadow            = false
        w.ignoresMouseEvents   = true
        w.collectionBehavior   = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        return w
    }
}

// MARK: – Fade animations (NSWindow + NSPanel via inheritance)

extension NSWindow {
    func fadeIn(duration: TimeInterval = 0.15) {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            animator().alphaValue = 1
        }
    }

    /// Fades out, orders the window out, then optionally resets alphaValue to 1 for reuse.
    func fadeOut(duration: TimeInterval = 0.1,
                 resetAlpha: Bool = false,
                 completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            if resetAlpha { self.alphaValue = 1 }
            completion?()
        })
    }
}

// MARK: – Overlay dismiss helper

extension NSWindow {
    /// Dismiss an overlay window: animated fade-out (resetting alpha for reuse) or instant order-out.
    func dismissOverlay(animated: Bool) {
        if animated { fadeOut(duration: 0.2, resetAlpha: true) }
        else        { orderOut(nil) }
    }
}

// MARK: – AV device discovery

extension AVCaptureDevice {
    static func cameraDevices() -> [AVCaptureDevice] {
        DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified
        ).devices
    }

    static func micDevices() -> [AVCaptureDevice] {
        DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio, position: .unspecified
        ).devices
    }
}
