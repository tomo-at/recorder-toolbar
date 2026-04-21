import AppKit
import SwiftUI

// ── Display selection overlay state ──────────────────────────────────────────

@MainActor
class DisplayOverlayState: ObservableObject {
    @Published var hoveredScreen: NSScreen?
    /// Saved on freeze() — stable across any later hoveredScreen changes.
    @Published var frozenScreen:  NSScreen?
    @Published var isSelected:    Bool = false

    /// Active screen to render: frozen selection takes priority over live hover.
    var displayedScreen: NSScreen? { frozenScreen ?? hoveredScreen }
}

// ── Per-screen NSWindow for the display overlay ───────────────────────────────

@MainActor
class DisplayScreenOverlayWindow {
    private var win: NSWindow?

    init(screen: NSScreen, state: DisplayOverlayState, level: NSWindow.Level) {
        let w = NSWindow.makeOverlay(frame: screen.frame, level: level)
        let hosting = NSHostingView(rootView: DisplayPerScreenView(screen: screen, state: state))
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        w.contentView = hosting
        self.win = w
    }

    func show() { win?.fadeIn(duration: 0.2) }

    func dismiss(animated: Bool = true) {
        win?.dismissOverlay(animated: animated)
    }
}

// ── Display overlay controller ────────────────────────────────────────────────

@MainActor
final class DisplayOverlayController {
    private var screenOverlays:    [DisplayScreenOverlayWindow] = []
    private let state = DisplayOverlayState()

    private var globalMoveToken:   Any?
    private var globalClickToken:  Any?
    private var localMoveMonitor:  Any?
    private var localClickMonitor: Any?
    private var localKeyMonitor:   Any?
    private var hoverTimer:        Timer?

    var onSelect: (() -> Void)?
    var onCancel: (() -> Void)?

    /// The frozen (clicked) screen. Nil before any selection.
    var frozenScreen: NSScreen? { state.frozenScreen }

    // MARK: – Public API

    func show(keepingAbove toolbar: NSPanel) {
        screenOverlays = NSScreen.screens.map { screen in
            let overlay = DisplayScreenOverlayWindow(screen: screen, state: state,
                                                      level: toolbar.level)
            overlay.show()
            return overlay
        }
        toolbar.orderFrontRegardless()
        updateHover()   // set initial active screen immediately (no 100ms delay)
        startTracking()
    }

    /// Snapshot hoveredScreen → frozenScreen, then stop tracking.
    /// The border stays visible on the selected display through recording.
    func freeze() {
        state.frozenScreen = state.hoveredScreen
        stopTracking()
        state.isSelected = true
    }

    /// Directly freeze to a given screen without requiring a hover event.
    func freezeToScreen(_ screen: NSScreen) {
        state.hoveredScreen = screen
        freeze()
    }

    func hide() {
        stopTracking()
        screenOverlays.forEach { $0.dismiss(animated: true) }
        screenOverlays.removeAll()
        state.hoveredScreen = nil
        state.frozenScreen  = nil
        state.isSelected    = false
    }

    // MARK: – Tracking

    private func startTracking() {
        globalMoveToken = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.updateHover() } }

        globalClickToken = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleClick() } }

        // localClickMonitor intentionally omitted — same reason as OverlayController:
        // toolbar clicks are local events and must not trigger display selection.
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor [weak self] in self?.updateHover() }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor [weak self] in self?.onCancel?() }
                return nil
            }
            return event
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateHover() }
        }
    }

    private func stopTracking() {
        hoverTimer?.invalidate(); hoverTimer = nil
        for token in [globalMoveToken, globalClickToken, localMoveMonitor,
                      localClickMonitor, localKeyMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(token)
        }
        globalMoveToken   = nil; globalClickToken  = nil
        localMoveMonitor  = nil; localClickMonitor = nil; localKeyMonitor = nil
    }

    private func updateHover() {
        guard !state.isSelected else { return }
        let ml  = NSEvent.mouseLocation  // AppKit bottom-left origin, same as NSScreen.frame
        let hit = NSScreen.screens.first { NSMouseInRect(ml, $0.frame, false) }
        if state.hoveredScreen !== hit { state.hoveredScreen = hit }
    }

    private func handleClick() {
        guard state.hoveredScreen != nil else { return }
        freeze()
        onSelect?()
    }
}

// ── Per-screen SwiftUI overlay view ──────────────────────────────────────────

struct DisplayPerScreenView: View {
    let screen: NSScreen
    @ObservedObject var state: DisplayOverlayState

    /// True when this screen is the active (hovered or frozen) selection.
    private var isActive: Bool { state.displayedScreen === screen }

    var body: some View {
        ZStack {
            // Dim: opaque on inactive screens, transparent on the active one.
            Color.black.opacity(isActive ? 0 : 0.65)

            // Orange border around the active screen.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.selectionOrange, lineWidth: 3)
                .opacity(isActive ? 1 : 0)

            // Display-name card — visible when active, fades out after selection.
            VStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                Text(screen.localizedName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, .dark)
            .opacity(isActive && !state.isSelected ? 1 : 0)
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .animation(.easeOut(duration: 0.2), value: state.isSelected)
    }
}
