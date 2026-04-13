import Foundation
import Combine
import AppKit
import SwiftUI

enum AppState {
    case typeSelect
    case windowSelect
    case displaySelect
    case countdown
    case recording
}

/// Tracks which overlay is currently being shown while the toolbar stays in typeSelect.
/// Cleared when the user confirms a selection (appState → windowSelect/displaySelect)
/// or cancels (Esc / same-button re-click).
enum SelectionMode {
    case window
    case display
}

@MainActor
class ToolbarState: ObservableObject {
    @Published var appState: AppState = .typeSelect {
        didSet { handleStateChange(to: appState) }
    }
    @Published var selectionMode: SelectionMode? = nil {
        didSet { updateEscMonitor() }
    }
    @Published var paused = false
    @Published var seconds: Int = 0
    @Published var countdownSeconds: Int = 3

    // Set by AppDelegate after panel creation
    weak var panel: NSPanel?
    let overlay          = OverlayController()
    let displayOverlay   = DisplayOverlayController()
    let previewOverlay   = PreviewOverlayController()
    let countdownOverlay = CountdownOverlayController()
    let settingsPanel    = SettingsPanelController()
    let shortcutTooltip  = ShortcutTooltipController()

    private var timer:              AnyCancellable?
    private var countdownTask:      Task<Void, Never>?
    private var cameraPreviewPanel: NSPanel?
    private var escKeyMonitor:      Any?

    init() {
        // Window selected: freeze overlay, then switch toolbar to Record-button state.
        overlay.onSelect = { [weak self] in
            guard let self else { return }
            self.overlay.freeze()
            self.appState     = .windowSelect   // handleStateChange fires first
            self.selectionMode = nil            // updateEscMonitor sees appState=.windowSelect → keeps monitor
        }
        overlay.onCancel = { [weak self] in self?.exitSelecting() }

        // Display selected: same pattern.
        displayOverlay.onSelect = { [weak self] in
            guard let self else { return }
            self.displayOverlay.freeze()
            self.appState      = .displaySelect
            self.selectionMode = nil
        }
        displayOverlay.onCancel = { [weak self] in self?.exitSelecting() }
    }

    // MARK: – Selection mode (overlay visible, toolbar still in typeSelect)

    /// Toggle the overlay for the given mode.
    /// - Same mode re-click → cancel selection.
    /// - Different mode → switch overlay.
    func toggleSelecting(_ mode: SelectionMode) {
        if selectionMode == mode {
            exitSelecting()
        } else {
            enterSelecting(mode)
        }
    }

    private func enterSelecting(_ mode: SelectionMode) {
        // Hide the other overlay if switching modes.
        switch mode {
        case .window:  displayOverlay.hide()
        case .display: overlay.hide()
        }

        selectionMode = mode

        guard let panel else { return }
        switch mode {
        case .window:  overlay.show(keepingAbove: panel)
        case .display: displayOverlay.show(keepingAbove: panel)
        }
    }

    func exitSelecting() {
        selectionMode = nil
        overlay.hide()
        displayOverlay.hide()
    }

    // MARK: – State change handler

    private func handleStateChange(to state: AppState) {
        // Cancel any in-progress countdown when leaving the countdown state.
        if state != .countdown {
            countdownTask?.cancel()
            countdownTask = nil
            countdownOverlay.hide()
        }

        previewOverlay.hideImmediate()
        shortcutTooltip.hide()
        hideCameraPreview()

        updateEscMonitor()

        switch state {
        case .typeSelect:
            // Hide overlays when returning from a confirmed selection or stopping recording.
            overlay.hide()
            displayOverlay.hide()
        case .windowSelect, .displaySelect, .countdown, .recording:
            break  // overlays are managed by selectionMode / freeze()
        }
        resizePanel(for: state)
    }

    // MARK: – Esc monitor

    private func updateEscMonitor() {
        let needsMonitor = selectionMode != nil
            || appState == .windowSelect
            || appState == .displaySelect
            || appState == .countdown

        if needsMonitor {
            guard escKeyMonitor == nil else { return }
            escKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }   // 53 = Escape
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.selectionMode != nil {
                        // Cancel overlay selection → stay in typeSelect
                        self.exitSelecting()
                    } else {
                        // Leave windowSelect / displaySelect / countdown → back to typeSelect
                        self.appState = .typeSelect
                    }
                }
            }
        } else if let token = escKeyMonitor {
            NSEvent.removeMonitor(token)
            escKeyMonitor = nil
        }
    }

    // MARK: – Panel resize

    private func resizePanel(for state: AppState) {
        guard let panel else { return }
        let newW: CGFloat
        switch state {
        case .recording, .countdown:        newW = 297
        case .typeSelect:                   newW = 554
        case .windowSelect, .displaySelect: newW = 389
        }
        let cx = panel.frame.midX
        let y  = panel.frame.origin.y
        panel.setFrame(NSRect(x: cx - newW / 2, y: y, width: newW, height: 56),
                       display: true, animate: true)
    }

    // MARK: – Countdown & Recording

    func startCountdown() {
        if appState == .windowSelect  { overlay.freeze() }
        if appState == .displaySelect { displayOverlay.freeze() }
        settingsPanel.dismiss()

        let choice = settingsPanel.state.countdownChoice
        guard choice != .none else { actuallyStartRecording(); return }

        let startCount = choice == .one ? 1 : 3
        countdownSeconds = startCount
        appState = .countdown

        guard let panel else { return }
        countdownOverlay.show(keepingAbove: panel)
        countdownOverlay.setNumber(startCount)

        countdownTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var remaining = startCount - 1
            while remaining >= 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                countdownSeconds = remaining
                countdownOverlay.setNumber(remaining)
                remaining -= 1
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            NSSound(named: "Tink")?.play()
            countdownOverlay.hide()
            countdownTask = nil
            actuallyStartRecording()
        }
    }

    private func actuallyStartRecording() {
        appState = .recording
        seconds  = 0
        paused   = false
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.paused else { return }
                self.seconds += 1
            }
    }

    func stopRecording() {
        timer?.cancel()
        timer    = nil
        seconds  = 0
        appState = .typeSelect
    }

    func togglePause() { paused = !paused }

    // MARK: – Camera preview popup

    func showCameraPreview(deviceId: String, above toolbar: NSPanel) {
        cameraPreviewPanel?.orderOut(nil)
        cameraPreviewPanel = nil

        let w: CGFloat = 320, h: CGFloat = 240

        let popup = NSPanel.makeFloating(level: .floating)

        let vfx = NSVisualEffectView()
        vfx.blendingMode         = .behindWindow
        vfx.material             = .underWindowBackground
        vfx.state                = .active
        vfx.wantsLayer           = true
        vfx.layer?.cornerRadius  = 24
        vfx.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: CameraThumb(deviceId: deviceId))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])
        popup.contentView = vfx
        popup.setContentSize(CGSize(width: w, height: h))

        let tf = toolbar.frame
        popup.setFrameOrigin(NSPoint(x: tf.midX - w / 2, y: tf.maxY + 8))

        popup.fadeIn()
        cameraPreviewPanel = popup
    }

    func hideCameraPreview() {
        guard let popup = cameraPreviewPanel else { return }
        cameraPreviewPanel = nil
        popup.fadeOut()
    }

    var timeString: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
