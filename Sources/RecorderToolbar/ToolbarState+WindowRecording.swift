import AppKit

extension ToolbarState {

    // MARK: – Window multi-recording helpers

    func setTemporaryHeaderMessage(_ msg: String, duration: TimeInterval = 3) {
        headerMessageTask?.cancel()
        headerOverrideMessage = msg
        headerMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.headerOverrideMessage = nil
            self?.headerMessageTask = nil
        }
    }

    func handleWindowAdd(_ window: DetectedWindow) {
        windowRecordingCount += 1
        overlay.addRecordedWindow(window)
        recordedWindows = overlay.recordedWindowsList
        resizePanel(for: appState)
        if settingsPanel.state.v5DefaultStyle == .message {
            setTemporaryHeaderMessage("Recording \(windowRecordingCount) windows")
        }
    }

    func handleWindowRemove(_ window: DetectedWindow) {
        windowRecordingCount = max(1, windowRecordingCount - 1)
        overlay.removeRecordedWindow(window)
        recordedWindows = overlay.recordedWindowsList
        windowHoverDialog.hide()
        resizePanel(for: appState)
    }

    func switchWindowViaHover(_ target: DetectedWindow) {
        guard let panel else { return }
        switchTargetWindow = target
        windowHoverDialog.hide()
        windowMultiDialog.dismiss()
        overlay.startChangeWindowSelection(keepingAbove: panel)
    }

    func handleWindowSwitchReplace(target: DetectedWindow, with newWindow: DetectedWindow) {
        overlay.replaceSpecificRecordedWindow(target, with: newWindow)
        recordedWindows = overlay.recordedWindowsList
        resizePanel(for: appState)
    }

    func showToolbarWindowPopup(at buttonFrame: CGRect,
                                onRemove: @escaping () -> Void,
                                onSwitch: (() -> Void)?) {
        guard let panel else { return }
        toolbarWindowPopup.show(at: buttonFrame, above: panel, onRemove: onRemove, onSwitch: onSwitch)
    }

    func switchWindowViaToolbar(_ window: DetectedWindow) {
        guard let panel else { return }
        switchTargetWindow = window
        overlay.startChangeWindowSelection(keepingAbove: panel)
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

    func handleWindowReplace(with newWindow: DetectedWindow) {
        overlay.replaceRecordedWindow(with: newWindow)
        recordedWindows = overlay.recordedWindowsList
        resizePanel(for: appState)
    }
}
