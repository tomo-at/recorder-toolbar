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
    case area
    case camOnly
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
    let camOnlyPanel           = CamOnlyPanelController()
    let uploadCompleteBanner   = UploadCompleteBannerController()
    let windowMultiDialog      = WindowMultiDialogController()
    let windowSelectionBottomBar = WindowSelectionBottomBarController()
    let windowHoverDialog      = WindowHoverDialogController()
    let toolbarWindowPopup     = ToolbarWindowPopupController()
    let areaOverlay            = AreaOverlayController()

    @Published var isWindowRecording:    Bool             = false
    @Published var windowRecordingCount: Int              = 0
    @Published var recordedWindows:      [DetectedWindow] = []
    var headerMessageTask:   Task<Void, Never>?
    var switchTargetWindow:  DetectedWindow?      = nil

    var timer:              AnyCancellable?
    var countdownTask:      Task<Void, Never>?
    var uploadTask:         Task<Void, Never>?
    var cameraPreviewPanel: NSPanel?
    var escKeyMonitor:      Any?
    var escLocalMonitor:    Any?
    var cancellables:       Set<AnyCancellable> = []

    // MARK: – Preview mode
    @Published var isPreviewMode = false
    var previewOriginalDefaultStyle:     SettingsState.DefaultStyle?
    var previewOriginalRecordingStyle:   SettingsState.RecordingStyle?
    var previewOriginalUploadStyle:      SettingsState.UploadStyle?
    var previewOriginalAddWindowPattern: SettingsState.AddWindowPattern?
    var previewClickMonitor: Any?
    var previewCancellables = Set<AnyCancellable>()

    /// V4 / V5(.selectedRegion) は選択確定後に SelectionConfirmPanel を出す。
    var usesSelectionConfirmPanel: Bool {
        let s = settingsPanel.state
        if s.protoVersion == .v4 { return true }
        if s.protoVersion == .v5 && s.v5RecordingStyle == .selectedRegion { return true }
        return false
    }

    /// V5(.toolbar) recording style shows the pre-recording toolbar when Area is selected.
    var usesToolbarRecordingStyle: Bool {
        let s = settingsPanel.state
        return s.protoVersion == .v5 && s.v5RecordingStyle == .toolbar
    }

    /// Styles with camera AND mic both visible in the toolbar use the full-screen window picker
    /// (toolbar hidden, bottom-bar hint shown across the entire display).
    var shouldUseFullScreenWindowPicker: Bool {
        guard settingsPanel.state.protoVersion == .v5 else { return false }
        let style = settingsPanel.state.v5DefaultStyle
        return style == .revealedAll || style == .revealedAllCompact
    }

    init() {
        settingsPanel.toolbarState = self

        // Window selected: freeze overlay.
        // - selectedRegion: confirm panel 表示
        // - toolbar: windowSelect ツールバーへ遷移
        overlay.onSelect = { [weak self] in
            guard let self else { return }
            self.overlay.freeze()
            self.selectionMode = nil
            self.appState = .windowSelect
            guard self.usesSelectionConfirmPanel else { return }
            if let bounds = self.overlay.frozenWindowBounds, let panel = self.panel {
                let origin = NSPoint(x: bounds.minX + 16,
                                     y: NSScreen.primaryHeight - bounds.maxY + 16)
                self.selectionConfirmPanel.show(origin: origin, above: panel, state: self,
                    onCancel: { [weak self] in self?.appState = .typeSelect },
                    onRecord:  { [weak self] in self?.startCountdown() })
                panel.orderOut(nil)
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

        // Hover over a recorded window → show Switch (1 window) or Remove+Switch (2 windows)
        // (only active when addWindowPattern == .hoverOnWindow)
        overlay.onHoverRecordedWindow = { [weak self] window in
            guard let self, let panel = self.panel else { return }
            guard self.settingsPanel.state.addWindowPattern == .hoverOnWindow else { return }
            if let w = window {
                let hasMultiple = self.windowRecordingCount >= 2
                self.windowHoverDialog.show(
                    for: w, above: panel,
                    onRemove: hasMultiple ? { [weak self] in self?.handleWindowRemove(w) } : nil,
                    onSwitch: { [weak self] in self?.switchWindowViaHover(w) }
                )
            } else {
                self.windowHoverDialog.hide()
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

        // Replacement window selected via change-window overlay (toolbar controls or hover Switch)
        overlay.onSelectReplacement = { [weak self] window in
            guard let self, let panel = self.panel else { return }
            self.overlay.exitAddWindowSelection(keepingAbove: panel)
            if let target = self.switchTargetWindow {
                self.switchTargetWindow = nil
                self.handleWindowSwitchReplace(target: target, with: window)
                // Resume hover tracking (hover Switch path — don't pauseTracking)
            } else {
                self.handleWindowReplace(with: window)
                self.overlay.pauseTracking()
            }
        }

        // Area confirmed (Enter key): freeze overlay, proceed like window/display selection.
        // For usesSelectionConfirmPanel: the confirm panel is already visible; Enter = Record.
        areaOverlay.onSelect = { [weak self] in
            guard let self else { return }
            self.areaOverlay.freeze()
            self.selectionMode = nil
            if self.usesSelectionConfirmPanel {
                self.startCountdown()
                return
            }
            self.appState = .windowSelect
        }
        areaOverlay.onCancel = { [weak self] in self?.exitSelecting() }

        // Drag start: hide confirm panel so it doesn't obstruct the selection.
        areaOverlay.onDragStart = { [weak self] in
            guard let self, self.usesSelectionConfirmPanel else { return }
            self.selectionConfirmPanel.dismiss()
            self.areaOverlay.confirmPanelFrame = nil
        }
        // Drag end: re-show confirm panel at the updated position.
        areaOverlay.onDragEnd = { [weak self] in
            guard let self, self.usesSelectionConfirmPanel,
                  self.selectionMode == .area else { return }
            self.showAreaConfirmPanel()
        }

        // Display selected: same pattern.
        displayOverlay.onSelect = { [weak self] in
            guard let self else { return }
            self.displayOverlay.freeze()
            self.selectionMode = nil
            self.appState = .displaySelect
            guard self.usesSelectionConfirmPanel else { return }
            if let screen = self.displayOverlay.frozenScreen, let panel = self.panel {
                let origin = NSPoint(x: screen.frame.minX + 16,
                                     y: screen.frame.minY + 16)
                self.selectionConfirmPanel.show(origin: origin, above: panel, state: self,
                    onCancel: { [weak self] in self?.appState = .typeSelect },
                    onRecord:  { [weak self] in self?.startCountdown() })
                panel.orderOut(nil)
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

    // MARK: – State change handler

    func handleStateChange(to state: AppState) {
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
            areaOverlay.hideImmediate()
            camOnlyPanel.dismiss()
            panel?.orderFrontRegardless()
        case .windowSelect, .displaySelect:
            // Restore toolbar hidden during full-screen window picker.
            windowSelectionBottomBar.hide()
            panel?.orderFrontRegardless()
            // Keep areaOverlay visible when frozen (area selection was confirmed).
            // Keep camOnlyPanel visible for toolbar-style cam-only preview.
        case .countdown:
            windowSelectionBottomBar.hide()
            areaOverlay.hideImmediate()
            camOnlyPanel.dismiss()
            panel?.orderFrontRegardless()
        case .recording:
            break
        }
        resizePanel(for: state)
    }

    // MARK: – Esc monitor

    func handleEscPress() {
        if selectionMode != nil {
            exitSelecting()
        } else if appState == .windowSelect || appState == .displaySelect || appState == .countdown {
            appState = .typeSelect
        }
    }

    func updateEscMonitor() {
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
}
