import AppKit
import SwiftUI

// ── Detected window (already converted to SwiftUI view coords) ──

struct DisplayedWindow: Equatable {
    let appName: String
    let title: String
    let appIcon: NSImage?
    let viewBounds: CGRect   // In SwiftUI overlay-window coordinates

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.appName == rhs.appName && lhs.viewBounds == rhs.viewBounds
    }
}

// ── Overlay controller ──────────────────────────────────────────

@MainActor
final class OverlayController: ObservableObject {
    @Published var displayed: DisplayedWindow?

    private var win: NSWindow?
    private var pollTimer: Timer?
    private var escMonitor: Any?

    // Stored at show() time for coordinate conversion
    private var overlayFrame: NSRect = .zero   // AppKit frame of the overlay window
    private var primaryH: CGFloat = 0          // Height of primary screen (AppKit)

    var onSelect: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: – Public API

    func show(keepingAbove toolbar: NSPanel) {
        // Cover ALL connected screens
        let totalFrame = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
        primaryH = NSScreen.main?.frame.height ?? totalFrame.height
        overlayFrame = totalFrame

        let w = NSWindow(
            contentRect: totalFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = toolbar.level
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: OverlayView(ctrl: self))
        w.makeKeyAndOrderFront(nil)
        self.win = w

        // Ensure toolbar stays above overlay
        toolbar.orderFrontRegardless()

        // Poll mouse @ 30 fps
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        // Escape key
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.cancel() }; return nil }
            return event
        }
    }

    func hide() {
        pollTimer?.invalidate(); pollTimer = nil
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        win?.close(); win = nil
        displayed = nil
    }

    func selectCurrent() { if displayed != nil { onSelect?() } }
    func cancel()         { onCancel?() }

    // MARK: – Coordinate conversion

    /// Convert a CGWindow bounds rect (CG screen coords) to SwiftUI overlay-view coords.
    /// AppKit ↔ CG:  cgY = primaryH - appKitY  →  appKitY = primaryH - cgY
    /// AppKit → view: viewX = appKitX - overlayFrame.minX
    ///                viewY = overlayFrame.maxY - appKitY
    ///                     = overlayFrame.maxY - (primaryH - cgY)
    ///                     = overlayFrame.maxY - primaryH + cgY
    private func cgRectToView(_ r: CGRect) -> CGRect {
        let vx = r.origin.x - overlayFrame.minX
        let vy = overlayFrame.maxY - primaryH + r.origin.y
        return CGRect(x: vx, y: vy, width: r.width, height: r.height)
    }

    /// Convert NSEvent.mouseLocation (AppKit global) to CG screen point.
    private func mouseInCG() -> CGPoint {
        let pt = NSEvent.mouseLocation
        return CGPoint(x: pt.x, y: primaryH - pt.y)
    }

    // MARK: – Private

    private func refresh() {
        let cgPt  = mouseInCG()
        let raw   = detectWindow(at: cgPt)
        let next: DisplayedWindow? = raw.map { dw in
            DisplayedWindow(appName: dw.appName, title: dw.title,
                            appIcon: dw.appIcon,
                            viewBounds: cgRectToView(dw.bounds))
        }
        if next != displayed { displayed = next }
    }

    private func detectWindow(at cgPoint: CGPoint) -> (appName: String, title: String, appIcon: NSImage?, bounds: CGRect)? {
        let skip: Set<String> = ["RecorderToolbar", "Dock", "Window Server",
                                  "SystemUIServer", "loginwindow"]
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []

        for info in list {
            guard
                let bd      = info[kCGWindowBounds as String] as? [String: Any],
                let r       = CGRect(dictionaryRepresentation: bd as CFDictionary),
                r.width > 100, r.height > 100,
                r.contains(cgPoint),
                let pid     = info[kCGWindowOwnerPID as String] as? pid_t,
                let appName = info[kCGWindowOwnerName as String] as? String,
                !skip.contains(appName)
            else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let icon  = NSRunningApplication(processIdentifier: pid)?.icon
            return (appName, title, icon, r)
        }
        return nil
    }
}

// ── SwiftUI overlay view ────────────────────────────────────────

struct OverlayView: View {
    @ObservedObject var ctrl: OverlayController

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            if let w = ctrl.displayed {
                let f = w.viewBounds

                // Border around hovered window
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(red: 1.0, green: 0.427, blue: 0.298), lineWidth: 6)
                    .frame(width: f.width, height: f.height)
                    .position(x: f.midX, y: f.midY)

                // Frosted glass label centred in the window
                VStack(spacing: 8) {
                    if let icon = w.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 72, height: 72)
                    }
                    Text(w.appName)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    if !w.title.isEmpty {
                        Text(w.title)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 32))
                .environment(\.colorScheme, .dark)
                .position(x: f.midX, y: f.midY)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { ctrl.selectCurrent() }
    }
}
