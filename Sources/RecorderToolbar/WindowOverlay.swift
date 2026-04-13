import AppKit
import SwiftUI

// ── Window snapshot ───────────────────────────────────────────────────────────

struct DetectedWindow: Identifiable, Equatable {
    let id: Int           // CGWindowID — stable for the window's lifetime
    let appName: String
    let title: String
    let appIcon: NSImage?
    var bounds: CGRect    // CG screen coords: top-left origin, points
    let ownerPID: pid_t

    var displayLabel: String {
        title.isEmpty || title == appName ? appName : "\(appName) — \(title)"
    }

    // Equality includes bounds so onChange fires when the window moves.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.bounds == rhs.bounds
    }
}

// ── Shared state (written by tracker, observed by overlay views) ──────────────

@MainActor
class OverlayState: ObservableObject {
    @Published var hoveredWindow: DetectedWindow?
    /// Set when the user clicks a window; stable across any later hoveredWindow changes.
    @Published var frozenWindow: DetectedWindow?
    @Published var stackCount: Int = 0
    @Published var isSelected: Bool = false

    /// The window to render: frozen selection takes priority over live hover.
    var displayedWindow: DetectedWindow? { frozenWindow ?? hoveredWindow }
}

// ── Per-screen overlay window ─────────────────────────────────────────────────
//
// ignoresMouseEvents = true: all pointer events pass through to underlying
// windows. Hover and click are handled by OverlayController's global NSEvent
// monitors — no hit-testing through the panel is required.

@MainActor
class ScreenOverlayWindow {
    private var win: NSWindow?

    init(screen: NSScreen, state: OverlayState, level: NSWindow.Level) {
        let w = NSWindow.makeOverlay(frame: screen.frame, level: level)
        let hosting = NSHostingView(rootView: PerScreenOverlayView(screen: screen, state: state))
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        w.contentView = hosting
        self.win = w
    }

    func show() { win?.fadeIn(duration: 0.2) }

    func dismiss(animated: Bool = true) {
        win?.dismissOverlay(animated: animated)
    }
}

// ── Overlay controller ────────────────────────────────────────────────────────

@MainActor
final class OverlayController {
    private var screenOverlays: [ScreenOverlayWindow] = []
    private var allWindows:     [DetectedWindow]      = []
    private let state = OverlayState()

    // Event monitor tokens
    private var globalMoveToken:  Any?
    private var globalClickToken: Any?
    private var localMoveMonitor: Any?
    private var localClickMonitor: Any?
    private var localKeyMonitor:  Any?
    private var hoverTimer: Timer?

    // Hover / cycle state
    private var currentStack:      [DetectedWindow] = []
    private var cycleIndex:        Int              = 0
    private var manualCycleActive: Bool             = false
    private var lastMousePt:       CGPoint          = .zero

    var onSelect: (() -> Void)?
    var onCancel: (() -> Void)?

    /// CG-coordinate bounds of the frozen (clicked) window. Nil before any selection.
    var frozenWindowBounds: CGRect? { state.frozenWindow?.bounds }

    // MARK: – Public API

    func show(keepingAbove toolbar: NSPanel) {
        allWindows = enumerateWindows()

        screenOverlays = NSScreen.screens.map { screen in
            let overlay = ScreenOverlayWindow(screen: screen, state: state,
                                               level: toolbar.level)
            overlay.show()
            return overlay
        }

        toolbar.orderFrontRegardless()
        startTracking()
    }

    /// Stop tracking and keep the overlay frozen on the selected window.
    /// Saves hoveredWindow → frozenWindow FIRST so later updateHover tasks can't erase it.
    func freeze() {
        state.frozenWindow = state.hoveredWindow  // snapshot before stopTracking
        stopTracking()
        state.isSelected = true
    }

    func hide() {
        stopTracking()
        screenOverlays.forEach { $0.dismiss(animated: true) }
        screenOverlays.removeAll()
        state.hoveredWindow = nil
        state.frozenWindow  = nil
        state.isSelected    = false
        currentStack        = []
        cycleIndex          = 0
        manualCycleActive   = false
    }

    func selectCurrent() { if state.hoveredWindow != nil { onSelect?() } }
    func cancel()         { onCancel?() }

    // MARK: – Event tracking

    private func startTracking() {
        // Global monitors fire when events go to OTHER processes.
        // Required because ignoresMouseEvents = true routes events away from our windows.
        globalMoveToken = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.updateHover() } }

        globalClickToken = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.handleClick() } }

        // Local move monitor: keeps hover updated when the cursor is over our toolbar.
        // Note: localClickMonitor is intentionally omitted — clicks on the toolbar are
        // local events but must NOT be treated as window selections (they hit toolbar buttons).
        // Window selections only happen via globalClickToken (clicks that reach OTHER processes).
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor [weak self] in self?.updateHover() }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53:       Task { @MainActor [weak self] in self?.cancel() };               return nil
            case 124, 125: Task { @MainActor [weak self] in self?.cycleStack(forward: true) };  return nil
            case 123, 126: Task { @MainActor [weak self] in self?.cycleStack(forward: false) }; return nil
            default: return event
            }
        }

        // 100ms timer: keep the hole tracking even when the mouse is stationary
        // (handles windows that animate / move without cursor movement).
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

    // MARK: – Hover

    /// Current cursor position in CG screen coords (top-left origin).
    private func cgMouse() -> CGPoint {
        let m = NSEvent.mouseLocation   // AppKit: bottom-left origin
        let h = NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        return CGPoint(x: m.x, y: h - m.y)
    }

    private func updateHover() {
        // After freeze, hoveredWindow is locked; don't let queued tasks overwrite it.
        guard !state.isSelected else { return }

        let pt    = cgMouse()
        let moved = pt != lastMousePt

        guard let list = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID
        ) as? [[CFString: Any]] else { return }

        // Build live Z-order and bounds maps from the current window list
        var orderMap  = [Int: Int]()
        var boundsMap = [Int: CGRect]()
        for (pos, info) in list.enumerated() {
            guard let wid = info[kCGWindowNumber] as? Int else { continue }
            orderMap[wid] = pos
            if let d = info[kCGWindowBounds] as? [String: Any],
               let r = CGRect(dictionaryRepresentation: d as CFDictionary) {
                boundsMap[wid] = r
            }
        }

        if moved {
            lastMousePt = pt
            // Clear manual cycle when the cursor leaves the selected window
            if manualCycleActive {
                let wb = state.hoveredWindow.map { boundsMap[$0.id] ?? $0.bounds }
                if wb == nil || !wb!.contains(pt) { manualCycleActive = false }
            }
        }

        if !manualCycleActive {
            // Normal hover: find all windows whose live bounds contain the cursor
            let candidates = allWindows.filter { (boundsMap[$0.id] ?? $0.bounds).contains(pt) }
            // Sort front-to-back by live Z-order
            let newStack = candidates.sorted {
                (orderMap[$0.id] ?? .max) < (orderMap[$1.id] ?? .max)
            }
            if newStack.map(\.id) != currentStack.map(\.id) {
                currentStack = newStack
                cycleIndex   = 0
            }

            var hovered: DetectedWindow? = currentStack.isEmpty ? nil : currentStack[cycleIndex]
            if var h = hovered, let lb = boundsMap[h.id] { h.bounds = lb; hovered = h }
            if state.hoveredWindow != hovered { state.hoveredWindow = hovered }
        } else {
            // Manual cycle: only update live bounds of the pinned window
            if var h = state.hoveredWindow, let lb = boundsMap[h.id], h.bounds != lb {
                h.bounds = lb; state.hoveredWindow = h
            }
        }

        state.stackCount = currentStack.count
    }

    private func cycleStack(forward: Bool) {
        manualCycleActive = true
        if currentStack.count > 1 {
            cycleIndex = forward
                ? (cycleIndex + 1) % currentStack.count
                : (cycleIndex - 1 + currentStack.count) % currentStack.count
            state.hoveredWindow = currentStack[cycleIndex]
        } else if !allWindows.isEmpty {
            let idx  = allWindows.firstIndex(where: { $0.id == state.hoveredWindow?.id }) ?? -1
            let next = forward
                ? (idx + 1) % allWindows.count
                : (idx - 1 + allWindows.count) % allWindows.count
            state.hoveredWindow = allWindows[next]
        }
    }

    private func handleClick() {
        if state.hoveredWindow != nil { onSelect?() }
    }

    // MARK: – Window enumeration

    private func enumerateWindows() -> [DetectedWindow] {
        let skip: Set<String> = ["RecorderToolbar", "Dock", "Window Server",
                                  "SystemUIServer", "loginwindow"]
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements], kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        var result: [DetectedWindow] = []
        for info in list {
            guard
                let layer   = info[kCGWindowLayer]    as? Int,    layer == 0,
                let pid     = info[kCGWindowOwnerPID] as? pid_t,  pid != ownPID,
                let appName = info[kCGWindowOwnerName] as? String, !skip.contains(appName),
                let bd = info[kCGWindowBounds] as? [String: Any],
                let r  = CGRect(dictionaryRepresentation: bd as CFDictionary),
                r.width > 50, r.height > 50
            else { continue }

            let wid   = info[kCGWindowNumber] as? Int    ?? 0
            let title = info[kCGWindowName]   as? String ?? ""
            let icon  = NSRunningApplication(processIdentifier: pid)?.icon
            result.append(DetectedWindow(id: wid, appName: appName, title: title,
                                          appIcon: icon, bounds: r, ownerPID: pid))
        }

        // Deduplicate by window ID (CGWindowList can return duplicates in edge cases)
        var seen = Set<Int>()
        return result.filter { seen.insert($0.id).inserted }
    }
}

// ── Per-screen SwiftUI overlay view ──────────────────────────────────────────

struct PerScreenOverlayView: View {
    let screen: NSScreen
    @ObservedObject var state: OverlayState

    // Hole center + size — stored separately so they animate independently.
    // Collapse: size → 0 while center stays fixed (hole shrinks in-place).
    @State private var holeCX: CGFloat = 0
    @State private var holeCY: CGFloat = 0
    @State private var holeW:  CGFloat = 0
    @State private var holeH:  CGFloat = 0

    var body: some View {
        ZStack {
            // Dark dim layer with a canvas-masked hole at the hovered window
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .mask(dimMask)

            // Badge + orange border (frozenWindow when selected, hoveredWindow otherwise)
            if let w = state.displayedWindow {
                let f = adjustedFrame(for: w)
                if CGRect(origin: .zero, size: screen.frame.size).intersects(f) {
                    WindowBadgeView(window: w, frame: f, showBadge: !state.isSelected)
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .onChange(of: state.hoveredWindow) { _, window in
            guard !state.isSelected else { return }  // frozen: hole is pinned by frozenWindow
            let screenRect = CGRect(origin: .zero, size: screen.frame.size)
            if let w = window {
                let r = adjustedFrame(for: w)
                if screenRect.intersects(r) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        holeCX = r.midX; holeCY = r.midY
                        holeW  = r.width; holeH  = r.height
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.12)) { holeW = 0; holeH = 0 }
                }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { holeW = 0; holeH = 0 }
            }
        }
        .onChange(of: state.frozenWindow) { _, window in
            // When freeze() fires, pin the hole to the selected window's position.
            guard let w = window else { return }
            let screenRect = CGRect(origin: .zero, size: screen.frame.size)
            let r = adjustedFrame(for: w)
            guard screenRect.intersects(r) else { return }
            // No animation — hole is already at the right spot from hover.
            holeCX = r.midX; holeCY = r.midY
            holeW  = r.width; holeH  = r.height
        }
    }

    /// Even-odd canvas mask: full rect minus the hole rect → hole is transparent.
    /// White = show dim; transparent = reveal the window below.
    private var dimMask: some View {
        Canvas { ctx, size in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            if holeW > 0 {
                path.addRoundedRect(
                    in: CGRect(x: holeCX - holeW / 2, y: holeCY - holeH / 2,
                               width: holeW, height: holeH),
                    cornerRadii: .init(topLeading: 8, bottomLeading: 8,
                                       bottomTrailing: 8, topTrailing: 8)
                )
            }
            ctx.fill(path, with: .color(.white), style: FillStyle(eoFill: true))
        }
    }

    /// Converts a window's CG bounds (global top-left origin) to screen-local SwiftUI coords.
    ///
    /// CG and SwiftUI both use top-left origin — only this screen's position in the
    /// virtual desktop needs to be subtracted.
    ///
    /// The primary screen (frame.origin == .zero in AppKit coords) is the Y-flip reference:
    ///   CG Y of screen top = primaryH - screen.frame.origin.y - screen.frame.height
    private func adjustedFrame(for w: DetectedWindow) -> CGRect {
        let screenTopInCG  = NSScreen.primaryHeight - screen.frame.origin.y - screen.frame.height
        let screenLeftInCG = screen.frame.origin.x
        return CGRect(
            x:      w.bounds.origin.x - screenLeftInCG,
            y:      w.bounds.origin.y - screenTopInCG,
            width:  w.bounds.width,
            height: w.bounds.height
        )
    }
}

// ── Window badge + border ─────────────────────────────────────────────────────

struct WindowBadgeView: View {
    let window: DetectedWindow
    let frame: CGRect
    var showBadge: Bool = true

    var body: some View {
        ZStack {
            // Orange border drawn at the window's exact bounds
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.selectionOrange, lineWidth: 3)
                .frame(width: frame.width, height: frame.height)

            // Info card centered over the window — hidden when window is frozen/selected
            VStack(spacing: 6) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                Text(window.displayLabel)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: max(frame.width - 32, 100))
            .opacity(showBadge ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: showBadge)
        }
        .position(x: frame.midX, y: frame.midY)
    }
}
