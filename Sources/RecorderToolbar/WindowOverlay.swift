import AppKit
import SwiftUI

// ── Detected window data ────────────────────────────────────

struct DetectedWindow: Equatable {
    let pid: pid_t
    let appName: String
    let title: String
    let bounds: CGRect   // CG screen coords: (0,0) = top-left, y increases downward
    let appIcon: NSImage?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && lhs.bounds == rhs.bounds
    }
}

// ── Overlay controller ──────────────────────────────────────

@MainActor
final class OverlayController: ObservableObject {
    @Published var hovered: DetectedWindow?

    private var win: NSWindow?
    private var pollTimer: Timer?
    private var escMonitor: Any?

    var onSelect: (() -> Void)?
    var onCancel: (() -> Void)?

    func show(keepingAbove toolbar: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let w = NSWindow(
            contentRect: screen.frame,
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

        // Poll mouse position at ~30fps (capture frame, not NSScreen, for Sendable)
        let screenHeight = screen.frame.height
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(screenHeight: screenHeight) }
        }

        // Escape key monitor
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.cancel() }
                return nil
            }
            return event
        }
    }

    func hide() {
        pollTimer?.invalidate(); pollTimer = nil
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        win?.close(); win = nil
        hovered = nil
    }

    func selectCurrent() { if hovered != nil { onSelect?() } }
    func cancel()         { onCancel?() }

    private func refresh(screenHeight: CGFloat) {
        let pt = NSEvent.mouseLocation
        // AppKit y is from bottom; CG y is from top
        let cgPt = CGPoint(x: pt.x, y: screenHeight - pt.y)
        let next = detectWindow(at: cgPt)
        if next != hovered { hovered = next }
    }

    private func detectWindow(at cgPoint: CGPoint) -> DetectedWindow? {
        let skip: Set<String> = ["RecorderToolbar", "Dock", "Window Server",
                                  "SystemUIServer", "loginwindow"]
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []

        for info in list {
            guard
                let bd  = info[kCGWindowBounds as String] as? [String: Any],
                let r   = CGRect(dictionaryRepresentation: bd as CFDictionary),
                r.width > 100, r.height > 100,
                r.contains(cgPoint),
                let pid     = info[kCGWindowOwnerPID as String] as? pid_t,
                let appName = info[kCGWindowOwnerName as String] as? String,
                !skip.contains(appName)
            else { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let icon  = NSRunningApplication(processIdentifier: pid)?.icon
            return DetectedWindow(pid: pid, appName: appName,
                                  title: title, bounds: r, appIcon: icon)
        }
        return nil
    }
}

// ── SwiftUI overlay view ────────────────────────────────────

struct OverlayView: View {
    @ObservedObject var ctrl: OverlayController

    var body: some View {
        ZStack {
            // Full-screen dark dim
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            if let w = ctrl.hovered {
                // Border around hovered window
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(red: 1.0, green: 0.427, blue: 0.298), lineWidth: 6)
                    .frame(width: w.bounds.width, height: w.bounds.height)
                    .position(x: w.bounds.midX, y: w.bounds.midY)

                // Frosted glass label panel
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
                .position(x: w.bounds.midX, y: w.bounds.midY)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { ctrl.selectCurrent() }
    }
}
