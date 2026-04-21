import AppKit
import SwiftUI

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

// NSViewRepresentable providing behindWindow backdrop blur without extra color tint.
private struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material     = .hudWindow
        v.state        = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// Ghost button (Remove): BackdropBlur + dark base + highlightPrimary tint
// Black base is needed because BackdropBlur (.behindWindow) samples real screen
// pixels — over a white window it turns gray without an explicit dark floor.
private struct DSGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            BackdropBlur()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Color.black.opacity(0.45)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Color.highlightPrimary
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            configuration.label
        }
        .frame(width: 108, height: 28)
        .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// Primary button (Add window): solid teal fill, black text
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

// Shared container: BackdropBlur + modelessOverlay tint + highlight border
private struct DSDialogContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack {
            BackdropBlur()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.modelessOverlay)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.highlightPrimary, lineWidth: 1)
            content
        }
    }
}

/// Hover-during-recording dialog: Add window (teal only). 124×44px content.
struct WindowMultiDialogView: View {
    let onAdd: () -> Void

    var body: some View {
        DSDialogContainer {
            Button(action: onAdd) {
                Text("Add window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.modelessBlack)
            }
            .buttonStyle(DSPrimaryButtonStyle())
        }
        .frame(width: 124, height: 44)
        .shadow(color: Color.shadowMedium, radius: 8, x: 0, y: 8)
        .padding(20)
    }
}

/// Content: Switch (top, optional) + Remove (bottom), vertically stacked.
private struct WindowToolbarActionView: View {
    let onDismiss: () -> Void
    let onRemove: () -> Void
    let onSwitch: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            if let onSwitch {
                Button(action: { onDismiss(); onSwitch() }) {
                    Text("Switch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.contentPrimary)
                }
                .buttonStyle(DSGhostButtonStyle())
            }
            Button(action: { onDismiss(); onRemove() }) {
                Text("Remove")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentDestructive)
            }
            .buttonStyle(DSGhostButtonStyle())
        }
        .padding(8)
    }
}

/// DSDialogContainer-styled popup for toolbar controls window buttons.
private struct WindowToolbarPopupView: View {
    let onDismiss: () -> Void
    let onRemove: () -> Void
    let onSwitch: (() -> Void)?

    var body: some View {
        DSDialogContainer {
            WindowToolbarActionView(onDismiss: onDismiss, onRemove: onRemove, onSwitch: onSwitch)
        }
        .frame(width: 124, height: onSwitch != nil ? 76 : 44)
        .shadow(color: Color.shadowMedium, radius: 8, x: 0, y: 8)
        .padding(20)
    }
}

/// Captures the containing NSView's screen-space rect on demand.
@MainActor
final class ButtonFrameReader: ObservableObject {
    fileprivate weak var capturedView: NSView?

    var screenFrame: CGRect? {
        guard let v = capturedView, let w = v.window else { return nil }
        return w.convertToScreen(v.convert(v.bounds, to: nil))
    }
}

struct ButtonFrameCaptureView: NSViewRepresentable {
    let reader: ButtonFrameReader
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        reader.capturedView = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { reader.capturedView = nsView }
}

/// Floating DSDialogContainer popup shown above a toolbar window button on click.
@MainActor
final class ToolbarWindowPopupController {
    private var panel: NSPanel?
    private var mouseMonitor: Any?

    func show(at buttonFrame: CGRect, above toolbar: NSPanel,
              onRemove: @escaping () -> Void, onSwitch: (() -> Void)?) {
        panel?.orderOut(nil)
        panel = nil
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }

        let contentH: CGFloat = onSwitch != nil ? 76 : 44
        let content  = CGSize(width: 124, height: contentH)
        let pad: CGFloat = 20
        let size    = CGSize(width: content.width + 2*pad, height: content.height + 2*pad)
        let view    = WindowToolbarPopupView(
            onDismiss: { [weak self] in self?.hide() },
            onRemove: onRemove,
            onSwitch: onSwitch
        )
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

        // Centered above the button's top edge
        let x = buttonFrame.midX - content.width / 2 - pad
        let y = buttonFrame.maxY + 6 - pad
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        panel = p

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let p = self.panel else { return }
            if !p.frame.contains(NSEvent.mouseLocation) {
                DispatchQueue.main.async { self.hide() }
            }
        }
    }

    func hide() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

/// Hover-during-recording dialog: Switch only (1-window) or Remove + Switch (multi-window).
/// Content: 124×44 (Switch only) or 240×44 (Remove + Switch).
struct WindowHoverDialogView: View {
    let onRemove: (() -> Void)?
    let onSwitch: () -> Void

    var body: some View {
        DSDialogContainer {
            HStack(spacing: 8) {
                if let onRemove {
                    Button(action: onRemove) {
                        Text("Remove")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentDestructive)
                    }
                    .buttonStyle(DSGhostButtonStyle())
                }
                Button(action: onSwitch) {
                    Text("Switch")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.contentPrimary)
                }
                .buttonStyle(DSGhostButtonStyle())
            }
        }
        .frame(width: onRemove != nil ? 240 : 124, height: 44)
        .shadow(color: Color.shadowMedium, radius: 8, x: 0, y: 8)
        .padding(20)
    }
}

@MainActor
final class WindowMultiDialogController {
    private var panel: NSPanel?

    func show(for window: DetectedWindow, above toolbar: NSPanel,
              onAdd: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let content  = CGSize(width: 124, height: 44)
        let pad: CGFloat = 20
        let size    = CGSize(width: content.width + 2*pad, height: content.height + 2*pad)
        let view    = WindowMultiDialogView(onAdd: onAdd)
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

/// Floating hover dialog shown above a recorded window: Switch only (1 window) or Remove + Switch (2 windows).
@MainActor
final class WindowHoverDialogController {
    private var panel: NSPanel?

    func show(for window: DetectedWindow, above toolbar: NSPanel,
              onRemove: (() -> Void)?, onSwitch: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let contentW: CGFloat = onRemove != nil ? 240 : 124
        let content  = CGSize(width: contentW, height: 44)
        let pad: CGFloat = 20
        let size    = CGSize(width: content.width + 2*pad, height: content.height + 2*pad)
        let view    = WindowHoverDialogView(onRemove: onRemove, onSwitch: onSwitch)
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

// MARK: – Cam-only panel

final class CamOnlyPanelController {
    private var panel: NSPanel?
    private var eventMonitors: [Any] = []
    private var isDragging = false
    private var startMouse: CGPoint = .zero
    private var startOrigin: CGPoint = .zero

    /// Show a large camera preview with Cancel/Cam/Mic/Settings/Record controls.
    func showConfirm(origin: NSPoint, above toolbar: NSPanel, state: ToolbarState,
                     onCancel: @escaping () -> Void,
                     onRecord: @escaping () -> Void) {
        dismissImmediate()
        let p = NSPanel.makeFloating(level: toolbar.level)
        let hosting = NSHostingView(rootView: CamOnlyConfirmView(
            state: state, onCancel: onCancel, onRecord: onRecord
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        p.contentView = hosting
        p.setContentSize(ToolbarState.PanelDimensions.camOnlyConfirmSize)
        p.setFrameOrigin(origin)
        p.fadeIn()
        p.invalidateShadow()
        panel = p
        toolbar.orderFrontRegardless()
        installDragMonitor(panel: p)
    }

    /// Show a large camera preview with no controls (toolbar handles recording).
    func showPreview(origin: NSPoint, above toolbar: NSPanel, deviceId: String?) {
        dismissImmediate()
        let p = NSPanel.makeFloating(level: toolbar.level)
        let hosting = NSHostingView(rootView: CamOnlyPreviewView(deviceId: deviceId))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        p.contentView = hosting
        p.setContentSize(ToolbarState.PanelDimensions.camOnlyPreviewSize)
        p.setFrameOrigin(origin)
        p.fadeIn()
        p.invalidateShadow()
        panel = p
        toolbar.orderFrontRegardless()
        installDragMonitor(panel: p)
    }

    private func installDragMonitor(panel: NSPanel) {
        removeMonitors()

        // Local monitors intercept THIS app's events — needed for clicks on our own nonactivatingPanel.
        // Global monitors only receive events targeted at OTHER applications.
        let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak panel] event in
            guard let self, let panel else { return event }
            let mouse = NSEvent.mouseLocation
            guard panel.frame.contains(mouse) else { self.isDragging = false; return event }
            self.startMouse = mouse
            self.startOrigin = panel.frame.origin
            self.isDragging = true
            return event
        }

        let dragged = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self, weak panel] event in
            guard let self, self.isDragging, let panel else { return event }
            let mouse = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: self.startOrigin.x + mouse.x - self.startMouse.x,
                                         y: self.startOrigin.y + mouse.y - self.startMouse.y))
            return event
        }

        let up = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.isDragging = false
            return event
        }

        eventMonitors = [down, dragged, up].compactMap { $0 }
    }

    private func removeMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        isDragging = false
    }

    private func dismissImmediate() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    func dismiss() {
        removeMonitors()
        guard let p = panel else { return }
        panel = nil
        p.fadeOut(resetAlpha: true)
    }
}

// MARK: – Selection confirm panel

final class SelectionConfirmPanelController {
    private var panel: NSPanel?

    /// Show the confirm panel with its bottom-left at `origin` (AppKit screen coords).
    func show(origin: NSPoint, above toolbar: NSPanel, state: ToolbarState,
              onCancel: @escaping () -> Void,
              onRecord: @escaping () -> Void) {
        panel?.orderOut(nil)
        panel = nil

        let p = NSPanel.makeFloating(level: toolbar.level)

        let hosting = NSHostingView(rootView: SelectionConfirmView(
            state: state,
            onCancel: onCancel,
            onRecord: onRecord
        ))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        p.contentView = hosting
        p.setContentSize(ToolbarState.PanelDimensions.selectionConfirmSize)
        p.setFrameOrigin(origin)
        p.fadeIn()
        p.invalidateShadow()
        panel = p
        toolbar.orderFrontRegardless()
    }

    func dismiss() {
        guard let p = panel else { return }
        panel = nil
        p.fadeOut(resetAlpha: true)
    }
}
