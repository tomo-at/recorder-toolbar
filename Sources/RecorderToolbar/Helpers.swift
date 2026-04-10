import AppKit
import AVFoundation

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
