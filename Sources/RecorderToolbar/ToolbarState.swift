import Foundation
import Combine
import AppKit
import SwiftUI
import AVFoundation

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
    @Published var isUploading:     Bool   = false
    @Published var uploadProgress:  Double = 0.0
    @Published var uploadComplete:  Bool   = false
    /// Temporary message that overrides the header in Message style during recording.
    @Published var headerOverrideMessage: String? = nil

    // デバイス（全 View で共有。各 View の .task { await state.loadDevices() } から呼ぶ）
    @Published var cameraDevices: [AVCaptureDevice] = []
    @Published var micDevices:    [AVCaptureDevice] = []
    @Published var activeCamId:   String?           = nil
    @Published var activeMicId:   String?           = nil

    // Set by AppDelegate after panel creation
    weak var panel: NSPanel?
    let overlay          = OverlayController()
    let displayOverlay   = DisplayOverlayController()
    let previewOverlay   = PreviewOverlayController()
    let countdownOverlay = CountdownOverlayController()
    let settingsPanel    = SettingsPanelController()
    let shortcutTooltip        = ShortcutTooltipController()
    let selectionConfirmPanel  = SelectionConfirmPanelController()
    let uploadCompleteBanner   = UploadCompleteBannerController()
    let windowMultiDialog      = WindowMultiDialogController()
    let windowRemoveDialog     = WindowRemoveDialogController()

    @Published var isWindowRecording:    Bool             = false
    @Published var windowRecordingCount: Int              = 0
    @Published var recordedWindows:      [DetectedWindow] = []
    private var headerMessageTask:   Task<Void, Never>?

    private var timer:              AnyCancellable?
    private var countdownTask:      Task<Void, Never>?
    private var uploadTask:         Task<Void, Never>?
    private var cameraPreviewPanel: NSPanel?
    private var escKeyMonitor:      Any?
    private var escLocalMonitor:    Any?
    private var cancellables:       Set<AnyCancellable> = []

    // MARK: – Preview mode
    @Published var isPreviewMode = false
    private var previewOriginalDefaultStyle:     SettingsState.DefaultStyle?
    private var previewOriginalRecordingStyle:   SettingsState.RecordingStyle?
    private var previewOriginalUploadStyle:      SettingsState.UploadStyle?
    private var previewOriginalAddWindowPattern: SettingsState.AddWindowPattern?
    private var previewClickMonitor: Any?
    private var previewCancellables = Set<AnyCancellable>()

    /// V4 / V5(.selectedRegion) は選択確定後に SelectionConfirmPanel を出す。
    private var usesSelectionConfirmPanel: Bool {
        let s = settingsPanel.state
        if s.protoVersion == .v4 { return true }
        if s.protoVersion == .v5 && s.v5RecordingStyle == .selectedRegion { return true }
        return false
    }

    /// V5(.selectToStart) はオーバーレイ選択 → 即カウントダウン（windowSelect をスキップ）。
    private var usesSelectToStart: Bool {
        let s = settingsPanel.state
        return s.protoVersion == .v5 && s.v5RecordingStyle == .selectToStart
    }

    init() {
        settingsPanel.toolbarState = self

        // Window selected: freeze overlay.
        // - selectToStart: 即 startCountdown（windowSelect スキップ）
        // - selectedRegion: confirm panel 表示
        // - toolbar: windowSelect ツールバーへ遷移
        overlay.onSelect = { [weak self] in
            guard let self else { return }
            self.overlay.freeze()
            self.selectionMode = nil
            if self.usesSelectToStart {
                self.startCountdown()
                return
            }
            self.appState = .windowSelect
            guard self.usesSelectionConfirmPanel else { return }
            if let bounds = self.overlay.frozenWindowBounds, let panel = self.panel {
                let origin = NSPoint(x: bounds.minX + 16,
                                     y: NSScreen.primaryHeight - bounds.maxY + 16)
                self.selectionConfirmPanel.show(origin: origin, above: panel,
                    onCancel: { [weak self] in self?.appState = .typeSelect },
                    onRecord:  { [weak self] in self?.startCountdown() })
            }
        }
        overlay.onCancel = { [weak self] in self?.exitSelecting() }

        // Hover over an unrecorded window during recording → show the add-window dialog
        // (only active when addWindowPattern == .hoverOnWindow)
        overlay.onHoverUnrecordedWindow = { [weak self] window in
            guard let self, let panel = self.panel else { return }
            guard self.settingsPanel.state.addWindowPattern == .hoverOnWindow else { return }
            if let w = window {
                guard self.windowRecordingCount < 2 else { return }
                self.windowMultiDialog.show(
                    for: w, above: panel,
                    onAdd: { [weak self] in
                        self?.windowMultiDialog.dismiss()
                        self?.handleWindowAdd(w)
                    }
                )
            } else {
                self.windowMultiDialog.dismiss()
            }
        }

        // Hover over a recorded window during multi-recording → show/hide the remove dialog
        // (only active when addWindowPattern == .hoverOnWindow)
        overlay.onHoverRecordedWindow = { [weak self] window in
            guard let self, let panel = self.panel else { return }
            guard self.settingsPanel.state.addWindowPattern == .hoverOnWindow else { return }
            if let w = window {
                self.windowRemoveDialog.show(for: w, above: panel,
                    onRemove: { [weak self] in self?.handleWindowRemove(w) })
            } else {
                self.windowRemoveDialog.hide()
            }
        }

        // Window selected via add-window overlay (toolbar controls pattern)
        overlay.onSelectAdditional = { [weak self] window in
            guard let self, let panel = self.panel else { return }
            self.overlay.exitAddWindowSelection(keepingAbove: panel)
            self.handleWindowAdd(window)
            // Return to no-tracking state until the next Add press
            self.overlay.pauseTracking()
        }

        // Replacement window selected via change-window overlay (toolbar controls pattern)
        overlay.onSelectReplacement = { [weak self] window in
            guard let self, let panel = self.panel else { return }
            self.overlay.exitAddWindowSelection(keepingAbove: panel)
            self.handleWindowReplace(with: window)
            self.overlay.pauseTracking()
        }

        // Display selected: same pattern.
        displayOverlay.onSelect = { [weak self] in
            guard let self else { return }
            self.displayOverlay.freeze()
            self.selectionMode = nil
            if self.usesSelectToStart {
                self.startCountdown()
                return
            }
            self.appState = .displaySelect
            guard self.usesSelectionConfirmPanel else { return }
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
                self.cancelUpload()
                self.appState = .typeSelect
                // resizePanel is called via handleStateChange, but force it again
                // so width also updates for the new version.
                self.resizePanel(for: .typeSelect)
            }
            .store(in: &cancellables)

        // V5 軸が変わったらツールバー幅を再計算（描画は SwiftUI が自動で対応）。
        Publishers.MergeMany(
            settingsPanel.state.$v5DefaultStyle.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settingsPanel.state.$v5RecordingStyle.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settingsPanel.state.$v5UploadStyle.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settingsPanel.state.$addWindowPattern.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            guard let self else { return }
            self.resizePanel(for: self.appState)
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

    /// Activate a selection mode without toggling (used by horizontal capture type dropdown).
    func activateSelecting(_ mode: SelectionMode) {
        settingsPanel.dismiss()
        if appState == .windowSelect || appState == .displaySelect {
            appState = .typeSelect
        }
        if selectionMode != mode {
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

    private func handleEscPress() {
        if selectionMode != nil {
            exitSelecting()
        } else if appState == .windowSelect || appState == .displaySelect || appState == .countdown {
            appState = .typeSelect
        }
    }

    private func updateEscMonitor() {
        let needsMonitor = selectionMode != nil
            || appState == .windowSelect
            || appState == .displaySelect
            || appState == .countdown

        if needsMonitor {
            // Make toolbar panel key so it receives local key events
            panel?.makeKeyAndOrderFront(nil)

            // Global monitor — catches Esc sent to other apps
            if escKeyMonitor == nil {
                escKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.keyCode == 53 else { return }   // 53 = Escape
                    Task { @MainActor [weak self] in self?.handleEscPress() }
                }
            }
            // Local monitor — catches Esc sent to this app (panel is key)
            if escLocalMonitor == nil {
                escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard event.keyCode == 53 else { return event }
                    Task { @MainActor [weak self] in self?.handleEscPress() }
                    return nil   // consume the event
                }
            }
        } else {
            if let token = escKeyMonitor  { NSEvent.removeMonitor(token); escKeyMonitor = nil }
            if let token = escLocalMonitor { NSEvent.removeMonitor(token); escLocalMonitor = nil }
        }
    }

    // MARK: – Panel resize

    private func resizePanel(for state: AppState) {
        guard let panel else { return }
        let s = settingsPanel.state
        let isHorizontal = s.protoVersion == .v5 && s.v5DefaultStyle == .horizontal
        let newH: CGFloat = panelHeight(for: s)
        let newW: CGFloat
        switch state {
        case .recording, .countdown:
            if s.addWindowPattern == .toolbarControls && isWindowRecording {
                // Count 1: primary window button + Add button + divider
                // Count 2: primary window button + secondary window button + divider (no Add)
                let extraH: CGFloat = windowRecordingCount >= 2 ? 215 : 195
                let extraV: CGFloat = 140  // SegmentButton 64×2 + divider 9 (same for both counts)
                newW = isHorizontal ? (365 + extraH) : (297 + extraV)
            } else {
                newW = isHorizontal ? 365 : 297
            }
        case .typeSelect:
            switch s.protoVersion {
            case .v1: newW = 345
            case .v2: newW = 506
            case .v3: newW = 510
            case .v4: newW = 482
            case .v5: newW = v5TypeSelectWidth(for: s.v5DefaultStyle)
            }
        case .windowSelect, .displaySelect:
            switch s.protoVersion {
            case .v1, .v2, .v3: newW = 389  // WindowSelectView width
            case .v4: newW = 482
            case .v5:
                switch s.v5RecordingStyle {
                case .selectToStart, .selectedRegion:
                    // typeSelect が出続けるので幅は defaultStyle に合わせる
                    newW = v5TypeSelectWidth(for: s.v5DefaultStyle)
                case .toolbar:
                    newW = isHorizontal ? 482 : 389
                }
            }
        }
        let cx = panel.frame.midX
        let y  = panel.frame.origin.y
        panel.setFrame(NSRect(x: cx - newW / 2, y: y, width: newW, height: newH),
                       display: true, animate: true)
    }

    private func v5TypeSelectWidth(for style: SettingsState.DefaultStyle) -> CGFloat {
        switch style {
        case .stepByStep:        return 345  // V1 と同じ
        case .revealedAll:       return 506  // V2 と同じ
        case .message:           return 482  // V4 と同じ
        case .horizontal:        return 482
        case .revealedAllCompact: return 470
        }
    }

    private func panelHeight(for s: SettingsState) -> CGFloat {
        switch s.protoVersion {
        case .v1, .v2, .v3: return 56
        case .v4:            return 66
        case .v5:
            switch s.v5DefaultStyle {
            case .stepByStep, .revealedAll, .revealedAllCompact: return 56
            case .message:                                     return 66
            case .horizontal:                                  return 48
            }
        }
    }

    // MARK: – Countdown & Recording

    /// On launch: find the frontmost window, select it, and jump straight into recording
    /// so the Add window feature can be tested without manual window selection.
    func autoStartWithFrontmostWindow() {
        guard let panel, let window = overlay.frontmostWindow() else { return }
        overlay.show(keepingAbove: panel)
        overlay.freezeToWindow(window)
        appState = .windowSelect
        startCountdown()
    }

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

        // If recording was started from window selection, keep overlay active (border only).
        if overlay.frozenWindowBounds != nil, let panel {
            isWindowRecording    = true
            windowRecordingCount = 1
            overlay.transitionToLightweight(keepingAbove: panel)
            recordedWindows = overlay.recordedWindowsList
            // resizePanel was already called via handleStateChange before isWindowRecording was
            // set, so call it again now that the correct width can be computed.
            resizePanel(for: .recording)
            // In toolbar controls mode, hover tracking is only needed during add-mode.
            if settingsPanel.state.addWindowPattern == .toolbarControls {
                overlay.pauseTracking()
            }
        }
    }

    func stopRecording(upload: Bool = true) {
        let wasPreviewMode = isPreviewMode
        timer?.cancel()
        timer    = nil
        seconds  = 0
        appState = .typeSelect

        // Reset window recording state
        isWindowRecording    = false
        windowRecordingCount = 0
        recordedWindows      = []
        windowMultiDialog.dismiss()
        windowRemoveDialog.hide()
        headerMessageTask?.cancel()
        headerMessageTask    = nil
        headerOverrideMessage = nil

        if wasPreviewMode {
            exitPreviewMode()
            return
        }

        guard upload else { return }
        let s = settingsPanel.state
        let triggersUpload = s.protoVersion == .v1
            || s.protoVersion == .v2
            || s.protoVersion == .v5
        if triggersUpload {
            startFakeUpload()
        }
    }

    private func startFakeUpload() {
        uploadTask?.cancel()
        isUploading    = true
        uploadProgress = 0.0
        let s = settingsPanel.state
        // バッジ系の完了表示を出すのは V1 か V5+toolbar のとき。
        // V2 / V5+menuBarNotification はメニューバーチェック + 通知で完了を示す。
        let usesToolbarBadges = s.protoVersion == .v1
            || (s.protoVersion == .v5 && s.v5UploadStyle == .toolbar)

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
            if usesToolbarBadges {
                self.settingsPanel.state.settingsBadge   = true
                self.settingsPanel.state.allVideosCount += 1
            }
            if s.v5UploadStyle == .uploadMode {
                self.uploadComplete = true
            }
            if s.v5UploadStyle == .toolbarWithCompleteMessage, let panel = self.panel {
                self.uploadCompleteBanner.show(above: panel, onViewVideo: { [weak self] in
                    self?.dismissUploadComplete()
                }, onDismiss: { [weak self] in
                    self?.dismissUploadComplete()
                })
            }
            // プレビュー時: ユーザー操作なしで終わるスタイルは自動でPrototype Settingsへ戻す
            guard self.isPreviewMode else { return }
            switch s.v5UploadStyle {
            case .toolbar:
                // バッジが表示された状態を少し見せてから戻る
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self.dismissUploadComplete()
            case .menuBarNotification:
                // AppDelegate がチェックマークを3秒表示するので、それより少し長く待って戻る
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard !Task.isCancelled else { return }
                self.dismissUploadComplete()
            case .toolbarWithCompleteMessage, .uploadMode:
                break  // バナー/Complete UIのボタンクリックで dismissUploadComplete() が呼ばれる
            }
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
        uploadTask     = nil
        isUploading    = false
        uploadProgress = 0
        uploadComplete = false
        uploadCompleteBanner.hide()
        if isPreviewMode { exitPreviewMode() }
    }

    func dismissUploadComplete() {
        uploadComplete = false
        uploadCompleteBanner.hide()
        if isPreviewMode { exitPreviewMode() }
    }

    // MARK: – Window multi-recording helpers

    private func setTemporaryHeaderMessage(_ msg: String, duration: TimeInterval = 3) {
        headerMessageTask?.cancel()
        headerOverrideMessage = msg
        headerMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.headerOverrideMessage = nil
            self?.headerMessageTask = nil
        }
    }

    private func handleWindowAdd(_ window: DetectedWindow) {
        windowRecordingCount += 1
        overlay.addRecordedWindow(window)
        recordedWindows = overlay.recordedWindowsList
        resizePanel(for: appState)
        if settingsPanel.state.v5DefaultStyle == .message {
            setTemporaryHeaderMessage("Recording \(windowRecordingCount) windows")
        }
    }

    private func handleWindowRemove(_ window: DetectedWindow) {
        windowRecordingCount = max(1, windowRecordingCount - 1)
        overlay.removeRecordedWindow(window)
        recordedWindows = overlay.recordedWindowsList
        windowRemoveDialog.hide()
        resizePanel(for: appState)
    }

    func addWindowViaToolbar() {
        guard let panel else { return }
        overlay.startAddWindowSelection(keepingAbove: panel)
    }

    func changeWindowViaToolbar() {
        guard let panel else { return }
        overlay.startChangeWindowSelection(keepingAbove: panel)
    }

    func removeWindowViaToolbar(_ window: DetectedWindow) {
        handleWindowRemove(window)
    }

    private func handleWindowReplace(with newWindow: DetectedWindow) {
        overlay.replaceRecordedWindow(with: newWindow)
        recordedWindows = overlay.recordedWindowsList
        resizePanel(for: appState)
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

    // MARK: – Preview actions

    func previewDefaultStyle(_ style: SettingsState.DefaultStyle) {
        previewOriginalDefaultStyle = settingsPanel.state.v5DefaultStyle
        settingsPanel.state.v5DefaultStyle = style
        isPreviewMode = true
        // Install click monitor after window-close animation to avoid catching the close click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isPreviewMode else { return }
            self.previewClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isPreviewMode else { return }
                    self.exitPreviewMode()
                }
            }
        }
    }

    func previewRecordingStyle(_ style: SettingsState.RecordingStyle) {
        previewOriginalRecordingStyle = settingsPanel.state.v5RecordingStyle
        settingsPanel.state.v5RecordingStyle = style
        isPreviewMode = true
        $appState
            .filter { $0 == .recording }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.exitPreviewMode() }
            .store(in: &previewCancellables)
    }

    func previewUploadStyle(_ style: SettingsState.UploadStyle) {
        previewOriginalUploadStyle = settingsPanel.state.v5UploadStyle
        settingsPanel.state.v5UploadStyle = style
        isPreviewMode = true
        startFakeUpload()
    }

    func previewAddWindowPattern(_ pattern: SettingsState.AddWindowPattern) {
        previewOriginalAddWindowPattern = settingsPanel.state.addWindowPattern
        settingsPanel.state.addWindowPattern = pattern
        isPreviewMode = true
        actuallyStartRecording()
        // Simulate single-window recording so toolbar shows add-window controls
        isWindowRecording    = true
        windowRecordingCount = 1
        resizePanel(for: .recording)
    }

    private func exitPreviewMode() {
        isPreviewMode = false
        previewCancellables.removeAll()
        if let m = previewClickMonitor { NSEvent.removeMonitor(m); previewClickMonitor = nil }
        // Restore original settings values
        if let v = previewOriginalDefaultStyle     { settingsPanel.state.v5DefaultStyle    = v; previewOriginalDefaultStyle     = nil }
        if let v = previewOriginalRecordingStyle   { settingsPanel.state.v5RecordingStyle  = v; previewOriginalRecordingStyle   = nil }
        if let v = previewOriginalUploadStyle      { settingsPanel.state.v5UploadStyle     = v; previewOriginalUploadStyle      = nil }
        if let v = previewOriginalAddWindowPattern { settingsPanel.state.addWindowPattern  = v; previewOriginalAddWindowPattern = nil }
        // Fully reset toolbar to typeSelect regardless of current state
        exitSelecting()
        selectionConfirmPanel.dismiss()
        countdownTask?.cancel(); countdownTask = nil; countdownOverlay.hide()
        cancelUpload()   // isPreviewMode is already false so no recursion
        if appState == .recording {
            // Use stopRecording to clean up timer/window-recording state; wasPreviewMode will be false
            stopRecording(upload: false)
        } else {
            appState = .typeSelect
        }
        settingsPanel.openPrototypeSettings()
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

    // MARK: – Device loading (shared)

    /// カメラ・マイクデバイスを一括取得。各 View の `.task { await state.loadDevices() }` から呼ぶ。
    func loadDevices() async {
        cameraDevices = AVCaptureDevice.cameraDevices()
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID
        micDevices    = AVCaptureDevice.micDevices()
        activeMicId   = activeMicId ?? micDevices.first?.uniqueID
    }
}
