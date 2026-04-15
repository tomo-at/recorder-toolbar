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
    @Published var isUploading:    Bool   = false
    @Published var uploadProgress: Double = 0.0

    // Set by AppDelegate after panel creation
    weak var panel: NSPanel?
    let overlay          = OverlayController()
    let displayOverlay   = DisplayOverlayController()
    let previewOverlay   = PreviewOverlayController()
    let countdownOverlay = CountdownOverlayController()
    let settingsPanel    = SettingsPanelController()
    let shortcutTooltip        = ShortcutTooltipController()
    let selectionConfirmPanel  = SelectionConfirmPanelController()

    private var timer:              AnyCancellable?
    private var countdownTask:      Task<Void, Never>?
    private var uploadTask:         Task<Void, Never>?
    private var cameraPreviewPanel: NSPanel?
    private var escKeyMonitor:      Any?
    private var cancellables:       Set<AnyCancellable> = []

    init() {
        // Window selected: freeze overlay, keep toolbar in typeSelect-like state,
        // show confirm panel at the selected window's bottom-left.
        overlay.onSelect = { [weak self] in
            guard let self else { return }
            self.overlay.freeze()
            self.appState      = .windowSelect   // handleStateChange fires; panel stays at 482px
            self.selectionMode = nil
            guard self.settingsPanel.state.protoVersion == .v4 else { return }
            if let bounds = self.overlay.frozenWindowBounds, let panel = self.panel {
                let origin = NSPoint(x: bounds.minX + 16,
                                     y: NSScreen.primaryHeight - bounds.maxY + 16)
                self.selectionConfirmPanel.show(origin: origin, above: panel,
                    onCancel: { [weak self] in self?.appState = .typeSelect },
                    onRecord:  { [weak self] in self?.startCountdown() })
            }
        }
        overlay.onCancel = { [weak self] in self?.exitSelecting() }

        // Display selected: same pattern — confirm panel at display bottom-left.
        displayOverlay.onSelect = { [weak self] in
            guard let self else { return }
            self.displayOverlay.freeze()
            self.appState      = .displaySelect
            self.selectionMode = nil
            guard self.settingsPanel.state.protoVersion == .v4 else { return }
            if let screen = self.displayOverlay.frozenScreen, let panel = self.panel {
                let origin = NSPoint(x: screen.frame.minX + 16,
                                     y: screen.frame.minY + 16)
                self.selectionConfirmPanel.show(origin: origin, above: panel,
                    onCancel: { [weak self] in self?.appState = .typeSelect },
                    onRecord:  { [weak self] in self?.startCountdown() })
            }
        }
        displayOverlay.onCancel = { [weak self] in self?.exitSelecting() }

        // Reset to typeSelect (and resize panel) when proto version changes.
        settingsPanel.state.$protoVersion
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.exitSelecting()
                self.selectionConfirmPanel.dismiss()
                self.appState = .typeSelect
                // resizePanel is called via handleStateChange, but force it again
                // so width also updates for the new version.
                self.resizePanel(for: .typeSelect)
            }
            .store(in: &cancellables)
    }

    // MARK: – Selection mode (overlay visible, toolbar still in typeSelect)

    /// Toggle the overlay for the given mode.
    /// - Same mode re-click → cancel selection.
    /// - Different mode → switch overlay.
    func toggleSelecting(_ mode: SelectionMode) {
        settingsPanel.dismiss()

        // 確定済みの選択状態 (windowSelect/displaySelect) からモード切替する場合は
        // 一度 typeSelect に戻して確定パネル・オーバーレイをリセットする。
        if appState == .windowSelect || appState == .displaySelect {
            appState = .typeSelect
        }
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
        // Dismiss confirm panel for any state except re-entering the same selection state.
        if state != .windowSelect && state != .displaySelect {
            selectionConfirmPanel.dismiss()
        }

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
        case .recording, .countdown:
            newW = 297
        case .typeSelect:
            switch settingsPanel.state.protoVersion {
            case .v1: newW = 345
            case .v2: newW = 506
            case .v3: newW = 510
            case .v4: newW = 482
            }
        case .windowSelect, .displaySelect:
            switch settingsPanel.state.protoVersion {
            case .v1, .v2, .v3: newW = 389  // WindowSelectView width
            case .v4: newW = 482
            }
        }
        let cx = panel.frame.midX
        let y  = panel.frame.origin.y
        panel.setFrame(NSRect(x: cx - newW / 2, y: y, width: newW, height: 66),
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

        let proto = settingsPanel.state.protoVersion
        if proto == .v1 || proto == .v2 {
            startFakeUpload()
        }
    }

    private func startFakeUpload() {
        uploadTask?.cancel()
        isUploading    = true
        uploadProgress = 0.0

        uploadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let totalSteps = 50    // 5 秒 × 10 steps/s（デバッグ用）
            for i in 1...totalSteps {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                self.uploadProgress = Double(i) / Double(totalSteps)
            }
            self.isUploading    = false
            self.uploadProgress = 0.0
            self.settingsPanel.state.settingsBadge   = true
            self.settingsPanel.state.allVideosCount += 1
        }
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

    // MARK: – View helpers (shared across TypeSelect variants)

    /// Show or hide the hover preview overlay.
    /// Centralises the `guard let panel` check that was duplicated in every TypeSelect view.
    func showPreview(_ type: PreviewType?) {
        guard let panel else { return }
        if let t = type { previewOverlay.show(t, keepingAbove: panel) }
        else            { previewOverlay.hide() }
    }

    /// Show a shortcut tooltip above a toolbar button.
    /// `buttonCenterX` is measured from the toolbar's left edge.
    func showTooltip(_ label: String, _ shortcut: String, buttonCenterX: CGFloat) {
        guard let panel else { return }
        shortcutTooltip.show(label: label, shortcut: shortcut,
                             buttonCenterX: buttonCenterX, above: panel)
    }
}
