import AppKit
import Combine

extension ToolbarState {

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
        if let panel, let window = overlay.frontmostWindow() {
            overlay.show(keepingAbove: panel)
            overlay.freezeToWindow(window)
            appState = .windowSelect
            startCountdown()
        } else {
            // Fallback: no window found, simulate recording state manually
            actuallyStartRecording()
            isWindowRecording    = true
            windowRecordingCount = 1
            resizePanel(for: .recording)
        }
    }

    func exitPreviewMode() {
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
}
