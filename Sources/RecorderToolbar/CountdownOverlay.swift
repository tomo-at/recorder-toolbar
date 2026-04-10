import AppKit
import SwiftUI

// ── Countdown overlay state ───────────────────────────────────────────────────

@MainActor
final class CountdownOverlayState: ObservableObject {
    @Published var currentNumber: Int = 3
}

// ── Per-screen countdown number view ─────────────────────────────────────────

private struct CountdownNumberView: View {
    let number: Int
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Text("\(number)")
            // .id forces SwiftUI to recreate the view on number change so
            // onAppear fires again and the pulse animation replays cleanly.
            .id(number)
            .font(.system(size: 280, weight: .bold))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 4)
            .scaleEffect(scale)
            .onAppear { animatePulse() }
    }

    private func animatePulse() {
        scale = 1.0
        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            scale = 1.18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.38)) {
                scale = 0.95
            }
        }
    }
}

struct CountdownOverlayView: View {
    @ObservedObject var state: CountdownOverlayState

    var body: some View {
        CountdownNumberView(number: state.currentNumber)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── Countdown overlay controller ──────────────────────────────────────────────

@MainActor
final class CountdownOverlayController {
    private var panels: [NSWindow] = []
    private let state  = CountdownOverlayState()

    /// Shows per-screen countdown panels above the toolbar and its overlays.
    func show(keepingAbove toolbar: NSPanel) {
        // One level above the selection overlays (which sit at toolbar.level).
        let level = NSWindow.Level(rawValue: toolbar.level.rawValue + 1)

        for screen in NSScreen.screens {
            let w = NSWindow.makeOverlay(frame: screen.frame, level: level)
            let hosting = NSHostingView(rootView: CountdownOverlayView(state: state))
            hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
            w.contentView = hosting
            w.fadeIn(duration: 0.2)
            panels.append(w)
        }
        toolbar.orderFrontRegardless()
    }

    /// Updates the displayed countdown digit.
    func setNumber(_ n: Int) {
        state.currentNumber = n
    }

    /// Fades out and removes all countdown panels.
    func hide() {
        panels.forEach { $0.fadeOut(duration: 0.15) }
        panels.removeAll()
    }
}
