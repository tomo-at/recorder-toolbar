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

// MARK: – Shortcut tooltip panel

@MainActor
final class ShortcutTooltipController {
    private var panel: NSPanel?

    /// Show a label + shortcut tooltip above `toolbar`, horizontally centered on `buttonCenterX`
    /// (measured from the toolbar's left edge).
    func show(label: String, shortcut: String, buttonCenterX: CGFloat, above toolbar: NSPanel) {
        panel?.orderOut(nil)
        panel = nil

        let hosting = NSHostingView(rootView: ShortcutTooltipView(label: label, shortcut: shortcut))
        let size    = hosting.fittingSize
        hosting.setFrameSize(size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel    = true
        p.level              = toolbar.level
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance         = NSAppearance(named: .darkAqua)
        p.contentView        = hosting
        p.setContentSize(size)

        let x = toolbar.frame.minX + buttonCenterX - size.width / 2
        let y = toolbar.frame.maxY + 4
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            p.animator().alphaValue = 1
        }
        panel = p
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

// MARK: – Window multi-recording dialog (Airtime DS, dark mode)
//
// Figma source nodes (Airtime Screen Recorder file):
//   11262:7200  Click dialog  — 240×44px, 8px padding, 8px gap
//   11262:7229  Remove dialog — 124×44px, 8px padding
//   Buttons: 108×28px, radius-15 (6px), space-10 gap (4px), space-20/space-15 padding (8px/6px)
//
// DS tokens: --color-highlight-primary (rgba(255,255,255,0.08)) + backdrop-blur 8px
//            --color-modeless-teal (#79dde8) / --color-modeless-black (#000000)
//            --color-accent-destructive (#ff6d4c)

// Ghost button (secondary): highlightPrimary fill, no blur (container provides backdrop blur)
private struct DSGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 108, height: 28)
            .background(Color.highlightPrimary,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// Primary button: teal fill, black text
private struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 108, height: 28)
            .background(
                Color.modelessTeal.opacity(configuration.isPressed ? 0.75 : 1.0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

// Shared container background for DS dialogs: modelessOverlay fill + highlight border.
// Blur and shadow removed temporarily for color verification.
private struct DSDialogContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.modelessOverlay)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.highlightPrimary, lineWidth: 1)
            content
        }
    }
}

/// Click-during-recording dialog: Cancel (ghost) + Add window (teal). 240×44px content.
struct WindowMultiDialogView: View {
    let onAdd:    () -> Void
    let onCancel: () -> Void

    var body: some View {
        DSDialogContainer {
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
                .buttonStyle(DSGhostButtonStyle())

                Button(action: onAdd) {
                    Text("Add window")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.modelessBlack)
                }
                .buttonStyle(DSPrimaryButtonStyle())
            }
        }
        .frame(width: 240, height: 44)
        .shadow(color: Color.shadowMedium, radius: 8, x: 0, y: 8)
        .padding(20)
    }
}

/// Hover-during-recording dialog: Remove (ghost, destructive text). 124×44px content.
struct WindowRemoveDialogView: View {
    let onRemove: () -> Void

    var body: some View {
        DSDialogContainer {
            Button(action: onRemove) {
                Text("Remove")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentDestructive)
            }
            .buttonStyle(DSGhostButtonStyle())
        }
        .frame(width: 124, height: 44)
        .shadow(color: Color.shadowMedium, radius: 8, x: 0, y: 8)
        .padding(20)
    }
}

@MainActor
final class WindowMultiDialogController {
    private var panel: NSPanel?

    func show(for window: DetectedWindow, above toolbar: NSPanel,
              onAdd: @escaping () -> Void,
              onCancel: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let content  = CGSize(width: 240, height: 44)
        let pad: CGFloat = 20
        let size    = CGSize(width: content.width + 2*pad, height: content.height + 2*pad)
        let view    = WindowMultiDialogView(onAdd: onAdd, onCancel: onCancel)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer             = true
        hosting.layer?.backgroundColor = .clear
        hosting.setFrameSize(size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel    = true
        p.level              = toolbar.level
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance         = NSAppearance(named: .darkAqua)
        p.contentView        = hosting
        p.setContentSize(size)

        // Centered on the window, 12 px inside from the top edge; shift by pad for shadow space
        let windowTopY = NSScreen.primaryHeight - window.bounds.minY
        let x = window.bounds.midX - content.width / 2 - pad
        let y = windowTopY - 12 - content.height - pad
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        panel = p
    }

    func dismiss(completion: (() -> Void)? = nil) {
        guard let p = panel else { completion?(); return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
            completion?()
        })
    }
}

/// Floating "Remove window" dialog shown above a recorded window on hover (multi-recording only).
@MainActor
final class WindowRemoveDialogController {
    private var panel: NSPanel?

    func show(for window: DetectedWindow, above toolbar: NSPanel,
              onRemove: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let content  = CGSize(width: 124, height: 44)
        let pad: CGFloat = 20
        let size    = CGSize(width: content.width + 2*pad, height: content.height + 2*pad)
        let view    = WindowRemoveDialogView(onRemove: onRemove)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer             = true
        hosting.layer?.backgroundColor = .clear
        hosting.setFrameSize(size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel    = true
        p.level              = toolbar.level
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance         = NSAppearance(named: .darkAqua)
        p.contentView        = hosting
        p.setContentSize(size)

        // Centered above the window's top edge (outside, to not block window clicks)
        let windowTopY = NSScreen.primaryHeight - window.bounds.minY
        let x = window.bounds.midX - content.width / 2 - pad
        let y = windowTopY + 6 - pad
        p.setFrameOrigin(NSPoint(x: x, y: y))
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

// MARK: – Upload complete banner (V5: Toolbar + Complete message style)

/// Pill-shaped banner that floats above the toolbar after upload completes.
struct UploadCompleteBannerView: View {
    let onViewVideo: () -> Void
    let onDismiss:   () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                Text("Upload complete")
                    .font(.system(size: 11))
            }
            .foregroundColor(.contentSecondary)

            Button(action: onViewVideo) {
                Text("View video")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.modelessTeal)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.contentTertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)  // 6 (HStack spacing) + 10 = 16px gap from "View video"
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgTertiary))
    }
}

@MainActor
final class UploadCompleteBannerController {
    private var panel: NSPanel?

    func show(above toolbar: NSPanel, onViewVideo: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let view    = UploadCompleteBannerView(onViewVideo: onViewVideo, onDismiss: onDismiss)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer              = true
        hosting.layer?.backgroundColor  = .clear
        let size = hosting.fittingSize
        hosting.setFrameSize(size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel    = true
        p.level              = toolbar.level
        p.backgroundColor    = .clear
        p.isOpaque           = false
        p.hasShadow          = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance         = NSAppearance(named: .darkAqua)
        p.contentView        = hosting
        p.setContentSize(size)

        let x = toolbar.frame.midX - size.width / 2
        let y = toolbar.frame.maxY + 8
        p.setFrameOrigin(NSPoint(x: x, y: y))
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

// MARK: – Selection confirm panel (V4: preview + Cancel/Record at window bottom-left)

@MainActor
final class SelectionConfirmPanelController {
    private var panel: NSPanel?

    /// Show the confirm panel with its bottom-left at `origin` (AppKit screen coords).
    /// Panel: 172×216 px, solid #12181a background, 12 px corner radius.
    func show(origin: NSPoint, above toolbar: NSPanel,
              onCancel: @escaping () -> Void,
              onRecord: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let p = NSPanel.makeFloating(level: toolbar.level)

        let hosting = NSHostingView(rootView: SelectionConfirmView(
            onCancel: onCancel,
            onRecord: onRecord
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        p.contentView = hosting
        p.setContentSize(CGSize(width: 172, height: 216))
        p.setFrameOrigin(origin)
        p.fadeIn()
        p.invalidateShadow()   // shadow follows rounded rect alpha
        panel = p
        toolbar.orderFrontRegardless()
    }

    func dismiss() {
        guard let p = panel else { return }
        panel = nil
        p.fadeOut(resetAlpha: true)
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
