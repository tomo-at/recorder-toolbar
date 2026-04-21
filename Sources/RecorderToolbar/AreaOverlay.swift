import AppKit
import SwiftUI

// MARK: – Area selection overlay (macOS screen recording style)
//
// Shows a default 55%-width 16:9 selection rect on open.
// Drag handles (corners + edge midpoints) allow resize; drag interior to move;
// drag outside to start a fresh selection.
// Confirm with Enter key. Cancel with Esc (ToolbarState).

// MARK: – Drag handle

private enum AreaDragHandle {
    case topLeft, topCenter, topRight
    case midLeft, midRight
    case bottomLeft, bottomCenter, bottomRight
    case interior   // drag to move
    case newRect    // drag from outside → fresh selection
}

private let kHandleSize:  CGFloat = 8
private let kHandleHitR:  CGFloat = 10
private let kMinRectSize: CGFloat = 30

// MARK: – Shared state (controller → view)

@MainActor
final class AreaSelectionState: ObservableObject {
    /// Selection rect in screen-local SwiftUI coords (top-left origin, y↓).
    @Published var selRect: CGRect

    init(screenSize: CGSize) {
        let w = screenSize.width * 0.55
        let h = w * (9.0 / 16.0)
        selRect = CGRect(
            x: (screenSize.width  - w) / 2,
            y: (screenSize.height - h) / 2,
            width: w, height: h
        )
    }
}

// MARK: – Per-screen overlay window

@MainActor
final class AreaScreenOverlayWindow {
    private var win: NSWindow?
    let screenState: AreaSelectionState
    let screen: NSScreen

    init(screen: NSScreen, level: NSWindow.Level, state: AreaSelectionState) {
        self.screen = screen
        self.screenState = state

        // Use NSPanel with .nonactivatingPanel so the overlay absorbs mouse events
        // (blocking interaction with underlying apps) without stealing keyboard focus.
        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level                   = level
        p.backgroundColor         = .clear
        p.isOpaque                = false
        p.hasShadow               = false
        p.ignoresMouseEvents      = false   // block underlying-app interaction
        p.isFloatingPanel         = false
        p.collectionBehavior      = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.isReleasedWhenClosed    = false
        p.acceptsMouseMovedEvents = true    // needed for local mouseMoved monitor

        let hosting = NSHostingView(
            rootView: AreaOverlayView(screenSize: screen.frame.size, state: state)
        )
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        p.contentView = hosting
        self.win = p
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
        let r = state.selRect
        ZStack {
            Canvas { ctx, size in
                var path = Path()
                path.addRect(CGRect(origin: .zero, size: size))
                if r.width > 2, r.height > 2 {
                    path.addRoundedRect(
                        in: r,
                        cornerRadii: .init(topLeading: 2, bottomLeading: 2,
                                           bottomTrailing: 2, topTrailing: 2)
                    )
                }
                ctx.fill(path, with: .color(Color.black.opacity(0.55)),
                         style: FillStyle(eoFill: true))
            }

            if r.width > kHandleSize * 2, r.height > kHandleSize * 2 {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.selectionOrange,
                            style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)

                handle(at: CGPoint(x: r.minX, y: r.minY))
                handle(at: CGPoint(x: r.midX, y: r.minY))
                handle(at: CGPoint(x: r.maxX, y: r.minY))
                handle(at: CGPoint(x: r.minX, y: r.midY))
                handle(at: CGPoint(x: r.maxX, y: r.midY))
                handle(at: CGPoint(x: r.minX, y: r.maxY))
                handle(at: CGPoint(x: r.midX, y: r.maxY))
                handle(at: CGPoint(x: r.maxX, y: r.maxY))
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func handle(at pt: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white)
            .frame(width: kHandleSize, height: kHandleSize)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.selectionOrange, lineWidth: 1)
            )
            .position(pt)
    }
}

// MARK: – Controller

@MainActor
final class AreaOverlayController {
    private var overlayWin:     AreaScreenOverlayWindow? = nil
    private var activeScreen:   NSScreen? = nil
    private var selectionState: AreaSelectionState? = nil

    private var moveMonitor:        Any?
    private var downMonitor:        Any?
    private var dragMonitor:        Any?
    private var upMonitor:          Any?
    private var enterGlobalMonitor: Any?
    private var enterLocalMonitor:  Any?

    private struct ActiveDrag {
        let handle:    AreaDragHandle
        let startPt:   CGPoint  // screen-local SwiftUI at drag-start
        let startRect: CGRect   // selRect at drag-start
    }
    private var activeDrag: ActiveDrag? = nil

    /// AppKit rect of the frozen selection (set in freeze()).
    private(set) var frozenRect: CGRect? = nil

    var onSelect: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    // MARK: – Lifecycle

    func show(keepingAbove panel: NSPanel) {
        hideImmediate()
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        activeScreen = screen

        let state = AreaSelectionState(screenSize: screen.frame.size)
        selectionState = state

        let overlay = AreaScreenOverlayWindow(screen: screen, level: panel.level, state: state)
        overlay.show()
        overlayWin = overlay

        startMonitors()
        panel.orderFrontRegardless()
        updateCursor(at: NSEvent.mouseLocation)
    }

    func hide() {
        stopMonitors()
        overlayWin?.hide(animated: true)
        reset()
        NSCursor.arrow.set()
    }

    func hideImmediate() {
        stopMonitors()
        overlayWin?.hide(animated: false)
        reset()
        NSCursor.arrow.set()
    }

    /// Stop monitors but keep overlay visible with the current selection.
    func freeze() {
        stopMonitors()
        if let state = selectionState, let screen = activeScreen {
            let r = state.selRect
            // Convert screen-local SwiftUI → AppKit for callers that need screen coords.
            frozenRect = CGRect(
                x: r.minX + screen.frame.minX,
                y: screen.frame.maxY - r.maxY,
                width: r.width, height: r.height
            )
        }
        NSCursor.arrow.set()
    }

    private func reset() {
        overlayWin    = nil
        activeScreen  = nil
        selectionState = nil
        frozenRect    = nil
        activeDrag    = nil
    }

    // MARK: – Monitors
    //
    // The overlay panel has ignoresMouseEvents = false, so all mouse events over the
    // overlay area are delivered to our app — local monitors fire, global monitors do not.
    // Global monitors are kept only for the Enter key (keyboard focus may be elsewhere).

    private func startMonitors() {
        // Mouse events: local monitors since the overlay absorbs them from other apps.
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            Task { @MainActor [weak self] in self?.updateCursor(at: NSEvent.mouseLocation) }
            return e
        }
        downMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            let pt = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handleMouseDown(at: pt) }
            return e
        }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] e in
            let pt = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handleMouseDrag(to: pt) }
            return e
        }
        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] e in
            let pt = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handleMouseUp(at: pt) }
            return e
        }
        // Enter key: keep both global + local since keyboard focus may be in another app.
        enterGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 36 || e.keyCode == 76 else { return }
            Task { @MainActor [weak self] in self?.onSelect?() }
        }
        enterLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 36 || e.keyCode == 76 else { return e }
            Task { @MainActor [weak self] in self?.onSelect?() }
            return nil
        }
    }

    private func stopMonitors() {
        for token in [moveMonitor, downMonitor, dragMonitor, upMonitor,
                      enterGlobalMonitor, enterLocalMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(token)
        }
        moveMonitor = nil; downMonitor = nil; dragMonitor = nil; upMonitor = nil
        enterGlobalMonitor = nil; enterLocalMonitor = nil
    }

    // MARK: – Coordinate helpers

    /// AppKit (bottom-left origin) → screen-local SwiftUI (top-left origin, y↓).
    private func toLocal(_ pt: NSPoint, screen: NSScreen) -> CGPoint {
        CGPoint(x: pt.x - screen.frame.minX, y: screen.frame.maxY - pt.y)
    }

    // MARK: – Hit testing

    private func hitHandle(at pt: CGPoint, in r: CGRect) -> AreaDragHandle {
        let handles: [(AreaDragHandle, CGPoint)] = [
            (.topLeft,      CGPoint(x: r.minX, y: r.minY)),
            (.topCenter,    CGPoint(x: r.midX, y: r.minY)),
            (.topRight,     CGPoint(x: r.maxX, y: r.minY)),
            (.midLeft,      CGPoint(x: r.minX, y: r.midY)),
            (.midRight,     CGPoint(x: r.maxX, y: r.midY)),
            (.bottomLeft,   CGPoint(x: r.minX, y: r.maxY)),
            (.bottomCenter, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomRight,  CGPoint(x: r.maxX, y: r.maxY)),
        ]
        for (handle, hp) in handles {
            let dx = pt.x - hp.x, dy = pt.y - hp.y
            if dx*dx + dy*dy <= kHandleHitR * kHandleHitR { return handle }
        }
        if r.contains(pt) { return .interior }
        return .newRect
    }

    // MARK: – Cursor

    private func updateCursor(at apkPt: NSPoint) {
        guard let screen = activeScreen, let state = selectionState else {
            NSCursor.crosshair.set(); return
        }
        guard screen.frame.contains(apkPt) else { NSCursor.arrow.set(); return }
        setCursor(for: hitHandle(at: toLocal(apkPt, screen: screen), in: state.selRect),
                  pressed: false)
    }

    private func setCursor(for handle: AreaDragHandle, pressed: Bool) {
        switch handle {
        case .interior:
            (pressed ? NSCursor.closedHand : NSCursor.openHand).set()
        case .midLeft, .midRight:
            NSCursor.resizeLeftRight.set()
        case .topCenter, .bottomCenter:
            NSCursor.resizeUpDown.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    // MARK: – Mouse handlers

    private func handleMouseDown(at apkPt: NSPoint) {
        guard let screen = activeScreen, let state = selectionState,
              screen.frame.contains(apkPt) else { return }
        let localPt = toLocal(apkPt, screen: screen)
        let handle = hitHandle(at: localPt, in: state.selRect)
        activeDrag = ActiveDrag(handle: handle, startPt: localPt, startRect: state.selRect)
        setCursor(for: handle, pressed: true)
    }

    private func handleMouseDrag(to apkPt: NSPoint) {
        guard let drag = activeDrag,
              let screen = activeScreen,
              let state  = selectionState else { return }
        let localPt = toLocal(apkPt, screen: screen)
        let bounds  = CGRect(origin: .zero, size: screen.frame.size)
        state.selRect = applyDrag(drag: drag, to: localPt, bounds: bounds)
        setCursor(for: drag.handle, pressed: true)
    }

    private func handleMouseUp(at apkPt: NSPoint) {
        guard let drag = activeDrag, let state = selectionState else { return }
        // Restore previous rect if a newRect drag resulted in a tiny selection.
        if drag.handle == .newRect,
           (state.selRect.width < kMinRectSize || state.selRect.height < kMinRectSize) {
            state.selRect = drag.startRect
        }
        activeDrag = nil
        updateCursor(at: apkPt)
    }

    // MARK: – Drag math

    private func applyDrag(drag: ActiveDrag, to pt: CGPoint, bounds: CGRect) -> CGRect {
        let dx = pt.x - drag.startPt.x
        let dy = pt.y - drag.startPt.y
        let s  = drag.startRect
        var r: CGRect

        switch drag.handle {
        case .topLeft:
            r = CGRect(x: s.minX + dx, y: s.minY + dy,
                       width: s.width - dx, height: s.height - dy)
        case .topCenter:
            r = CGRect(x: s.minX, y: s.minY + dy,
                       width: s.width, height: s.height - dy)
        case .topRight:
            r = CGRect(x: s.minX, y: s.minY + dy,
                       width: s.width + dx, height: s.height - dy)
        case .midLeft:
            r = CGRect(x: s.minX + dx, y: s.minY,
                       width: s.width - dx, height: s.height)
        case .midRight:
            r = CGRect(x: s.minX, y: s.minY,
                       width: s.width + dx, height: s.height)
        case .bottomLeft:
            r = CGRect(x: s.minX + dx, y: s.minY,
                       width: s.width - dx, height: s.height + dy)
        case .bottomCenter:
            r = CGRect(x: s.minX, y: s.minY,
                       width: s.width, height: s.height + dy)
        case .bottomRight:
            r = CGRect(x: s.minX, y: s.minY,
                       width: s.width + dx, height: s.height + dy)
        case .interior:
            r = CGRect(x: s.minX + dx, y: s.minY + dy,
                       width: s.width, height: s.height)
        case .newRect:
            r = CGRect(x: min(drag.startPt.x, pt.x), y: min(drag.startPt.y, pt.y),
                       width: abs(pt.x - drag.startPt.x), height: abs(pt.y - drag.startPt.y))
        }

        // Normalize negative dims (e.g. dragging a corner past the opposite side).
        r = r.standardized
        // Enforce minimum size.
        if r.width  < kMinRectSize { r.size.width  = kMinRectSize }
        if r.height < kMinRectSize { r.size.height = kMinRectSize }
        // Clamp to screen.
        r.origin.x = max(bounds.minX, min(r.origin.x, bounds.maxX - r.width))
        r.origin.y = max(bounds.minY, min(r.origin.y, bounds.maxY - r.height))
        return r
    }
}
