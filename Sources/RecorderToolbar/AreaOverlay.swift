import AppKit
import SwiftUI

// MARK: – Area selection overlay
//
// Shows a dim overlay with an even-odd "hole" at the dragged selection rect.
// Mouse tracking uses global NSEvent monitors (same pattern as WindowOverlay).

// MARK: – Shared state

@MainActor
final class AreaSelectionState: ObservableObject {
    /// Selection rect in screen-local SwiftUI coords (top-left origin, y↓).
    @Published var selRect: CGRect? = nil
}

// MARK: – Per-screen overlay window

@MainActor
final class AreaScreenOverlayWindow {
    private var win: NSWindow?
    let screenState = AreaSelectionState()
    let screen: NSScreen

    init(screen: NSScreen, level: NSWindow.Level) {
        self.screen = screen
        let w = NSWindow.makeOverlay(frame: screen.frame, level: level)
        let hosting = NSHostingView(
            rootView: AreaOverlayView(screenSize: screen.frame.size, state: screenState)
        )
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        w.contentView = hosting
        self.win = w
    }

    func show() { win?.fadeIn(duration: 0.15) }
    func hide(animated: Bool = true) {
        if animated { win?.fadeOut() } else { win?.orderOut(nil) }
    }
}

// MARK: – Overlay view

struct AreaOverlayView: View {
    let screenSize: CGSize
    @ObservedObject var state: AreaSelectionState

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                var path = Path()
                path.addRect(CGRect(origin: .zero, size: size))
                if let r = state.selRect, r.width > 2, r.height > 2 {
                    path.addRoundedRect(
                        in: r,
                        cornerRadii: .init(topLeading: 2, bottomLeading: 2,
                                           bottomTrailing: 2, topTrailing: 2)
                    )
                }
                ctx.fill(path, with: .color(Color.black.opacity(0.55)),
                         style: FillStyle(eoFill: true))
            }

            if let r = state.selRect, r.width > 4, r.height > 4 {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.selectionOrange,
                            style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
    }
}

// MARK: – Controller

@MainActor
final class AreaOverlayController {
    private var screenOverlays: [AreaScreenOverlayWindow] = []
    private var moveMonitor:    Any?
    private var downMonitor:    Any?
    private var dragMonitor:    Any?
    private var upMonitor:      Any?

    private var dragStart:  NSPoint? = nil
    private var dragScreen: NSScreen? = nil

    /// AppKit rect of the completed selection. Set on a valid mouseUp.
    private(set) var frozenRect: CGRect? = nil

    var onSelect: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    // MARK: – Lifecycle

    func show(keepingAbove panel: NSPanel) {
        hideImmediate()
        for screen in NSScreen.screens {
            let o = AreaScreenOverlayWindow(screen: screen, level: panel.level)
            o.show()
            screenOverlays.append(o)
        }
        startMonitors()
        panel.orderFrontRegardless()
    }

    func hide() {
        stopMonitors()
        for o in screenOverlays { o.hide(animated: true) }
        screenOverlays.removeAll()
        frozenRect = nil
        dragStart  = nil
        NSCursor.arrow.set()
    }

    func hideImmediate() {
        stopMonitors()
        for o in screenOverlays { o.hide(animated: false) }
        screenOverlays.removeAll()
        frozenRect = nil
        dragStart  = nil
        NSCursor.arrow.set()
    }

    /// Stop monitors but keep overlay visible with the frozen selection.
    func freeze() {
        stopMonitors()
        NSCursor.arrow.set()
    }

    // MARK: – Monitors

    private func startMonitors() {
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            Task { @MainActor in NSCursor.crosshair.set() }
        }
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMouseDown(at: NSEvent.mouseLocation) }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMouseDrag(to: NSEvent.mouseLocation) }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleMouseUp(at: NSEvent.mouseLocation) }
        }
        NSCursor.crosshair.set()
    }

    private func stopMonitors() {
        for token in [moveMonitor, downMonitor, dragMonitor, upMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(token)
        }
        moveMonitor = nil; downMonitor = nil; dragMonitor = nil; upMonitor = nil
    }

    // MARK: – Drag tracking

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// AppKit (bottom-left origin) → screen-local SwiftUI (top-left origin, y↓).
    private func toLocal(_ point: NSPoint, screen: NSScreen) -> CGPoint {
        CGPoint(x: point.x - screen.frame.minX,
                y: screen.frame.maxY - point.y)
    }

    private func handleMouseDown(at location: NSPoint) {
        dragStart  = location
        dragScreen = screen(containing: location)
        NSCursor.crosshair.set()
    }

    private func handleMouseDrag(to location: NSPoint) {
        guard let start = dragStart, let screen = dragScreen else { return }
        NSCursor.crosshair.set()
        let s = toLocal(start,    screen: screen)
        let e = toLocal(location, screen: screen)
        let rect = CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y))
        for o in screenOverlays {
            o.screenState.selRect = o.screen === screen ? rect : nil
        }
    }

    private func handleMouseUp(at location: NSPoint) {
        guard let start = dragStart, let screen = dragScreen else { return }
        dragStart = nil

        let dx = abs(location.x - start.x)
        let dy = abs(location.y - start.y)

        guard dx > 10, dy > 10 else {
            for o in screenOverlays { o.screenState.selRect = nil }
            onCancel?()
            return
        }

        frozenRect = CGRect(x: min(start.x, location.x), y: min(start.y, location.y),
                            width: dx, height: dy)
        onSelect?()
    }
}
