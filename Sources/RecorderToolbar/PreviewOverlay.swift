import AppKit
import SwiftUI

enum PreviewType { case display, window, area }

// ── Preview overlay controller ────────────────────────────────────────────────
//
// Shows a lightweight, non-interactive visual preview while the user hovers
// over the capture-type buttons (Display / Window / Area) in TypeSelectView.

@MainActor
final class PreviewOverlayController {
    private var windows:     [NSWindow]         = []
    private var shown:       PreviewType?       = nil
    private var pendingHide: Task<Void, Never>? = nil

    // MARK: – Public API

    func show(_ type: PreviewType, keepingAbove toolbar: NSPanel) {
        pendingHide?.cancel()
        pendingHide = nil
        guard type != shown else { return }
        dismissAll()     // instant remove of previous preview
        shown = type

        switch type {
        case .display: buildDisplayPreview(toolbar: toolbar)
        case .window:  buildWindowPreview(toolbar: toolbar)
        case .area:    buildAreaPreview(toolbar: toolbar)
        }
        toolbar.orderFrontRegardless()
    }

    /// Debounced hide (80 ms) — prevents flicker when moving between buttons.
    func hide() {
        pendingHide?.cancel()
        pendingHide = Task { @MainActor [weak self] in
            do    { try await Task.sleep(nanoseconds: 80_000_000) }
            catch { return }   // cancelled
            guard !Task.isCancelled else { return }
            self?.dismissAll(animated: true)
            self?.shown = nil
        }
    }

    /// Instant hide — called on state transitions (e.g., entering Window/Display select).
    func hideImmediate() {
        pendingHide?.cancel()
        pendingHide = nil
        dismissAll()
        shown = nil
    }

    // MARK: – Preview builders

    private func buildDisplayPreview(toolbar: NSPanel) {
        // Border on every screen, no dim — shows the screen content clearly.
        for screen in NSScreen.screens {
            addPreview(for: screen, level: toolbar.level,
                       view: DisplayHoverPreviewView(screenSize: screen.frame.size))
        }
    }

    private func buildWindowPreview(toolbar: NSPanel) {
        let cgBounds = frontmostWindowBounds()
        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0

        for screen in NSScreen.screens {
            // Convert CG (global, top-left origin) → screen-local SwiftUI coords.
            let screenTopCG  = primaryH - screen.frame.origin.y - screen.frame.height
            let screenLeftCG = screen.frame.origin.x
            let screenRect   = CGRect(origin: .zero, size: screen.frame.size)

            let localBounds: CGRect? = cgBounds.flatMap { cg in
                let r = CGRect(x: cg.origin.x - screenLeftCG,
                               y: cg.origin.y - screenTopCG,
                               width: cg.width, height: cg.height)
                return screenRect.intersects(r) ? r : nil
            }

            addPreview(for: screen, level: toolbar.level,
                       view: WindowHoverPreviewView(screenSize: screen.frame.size,
                                                    windowBounds: localBounds))
        }
    }

    private func buildAreaPreview(toolbar: NSPanel) {
        let screen = toolbar.screen ?? NSScreen.main ?? NSScreen.screens[0]
        addPreview(for: screen, level: toolbar.level,
                   view: AreaHoverPreviewView(screenSize: screen.frame.size))
    }

    // MARK: – Shared helpers

    private func addPreview<V: View>(for screen: NSScreen,
                                      level: NSWindow.Level,
                                      view: V) {
        let w = NSWindow.makeOverlay(frame: screen.frame, level: level)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
        w.contentView = hosting
        w.fadeIn(duration: 0.15)
        windows.append(w)
    }

    private func dismissAll(animated: Bool = false) {
        for w in windows {
            if animated { w.fadeOut(duration: 0.15) } else { w.orderOut(nil) }
        }
        windows.removeAll()
    }

    /// Returns CG bounds (global, top-left origin) of the topmost non-system window.
    private func frontmostWindowBounds() -> CGRect? {
        let skip: Set<String> = ["RecorderToolbar", "Dock", "Window Server",
                                  "SystemUIServer", "loginwindow"]
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        for info in list {
            guard
                let layer   = info[kCGWindowLayer]    as? Int,    layer == 0,
                let pid     = info[kCGWindowOwnerPID] as? pid_t,  pid != ownPID,
                let appName = info[kCGWindowOwnerName] as? String, !skip.contains(appName),
                let bd = info[kCGWindowBounds] as? [String: Any],
                let r  = CGRect(dictionaryRepresentation: bd as CFDictionary),
                r.width > 50, r.height > 50
            else { continue }
            _ = appName  // used in guard above
            return r
        }
        return nil
    }
}

// ── Display hover preview: border around all screens, no dim ─────────────────

struct DisplayHoverPreviewView: View {
    let screenSize: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Color(red: 1.0, green: 0.427, blue: 0.298), lineWidth: 3)
            .frame(width: screenSize.width, height: screenSize.height)
    }
}

// ── Window hover preview: dim + border on the frontmost window ───────────────

struct WindowHoverPreviewView: View {
    let screenSize:   CGSize
    /// Screen-local SwiftUI coords of the frontmost window; nil = not on this screen.
    let windowBounds: CGRect?

    var body: some View {
        ZStack {
            // Dim with an even-odd hole at the window position.
            Color.black.opacity(0.55)
                .mask(dimMask)

            // Orange border drawn at the window's bounds.
            if let b = windowBounds {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(red: 1.0, green: 0.427, blue: 0.298), lineWidth: 3)
                    .frame(width: b.width, height: b.height)
                    .position(x: b.midX, y: b.midY)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }

    private var dimMask: some View {
        Canvas { ctx, size in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            if let b = windowBounds {
                path.addRoundedRect(
                    in: b,
                    cornerRadii: .init(topLeading: 8, bottomLeading: 8,
                                       bottomTrailing: 8, topTrailing: 8)
                )
            }
            ctx.fill(path, with: .color(.white), style: FillStyle(eoFill: true))
        }
    }
}

// ── Area hover preview: centered dashed rect + dim outside ───────────────────

struct AreaHoverPreviewView: View {
    let screenSize: CGSize

    // 55 % width, 16:9 ratio
    private var rW: CGFloat { screenSize.width * 0.55 }
    private var rH: CGFloat { rW * (9.0 / 16.0) }

    var body: some View {
        let rX = (screenSize.width  - rW) / 2
        let rY = (screenSize.height - rH) / 2

        ZStack {
            // Dim outside the selection rectangle via even-odd Canvas.
            Canvas { ctx, size in
                var path = Path()
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(
                    in: CGRect(x: rX, y: rY, width: rW, height: rH),
                    cornerRadii: .init(topLeading: 4, bottomLeading: 4,
                                       bottomTrailing: 4, topTrailing: 4)
                )
                ctx.fill(path, with: .color(Color.black.opacity(0.55)),
                         style: FillStyle(eoFill: true))
            }

            // White dashed border.
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .frame(width: rW, height: rH)
                .position(x: screenSize.width / 2, y: screenSize.height / 2)
        }
        .frame(width: screenSize.width, height: screenSize.height)
    }
}
