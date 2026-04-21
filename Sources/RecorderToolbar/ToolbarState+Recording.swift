import Foundation
import Combine
import AppKit

extension ToolbarState {

    // MARK: – Countdown & Recording

    func startCountdown() {
        selectionMode = nil
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

    func actuallyStartRecording() {
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
        windowHoverDialog.hide()
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

    func startFakeUpload() {
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

    func togglePause() { paused = !paused }

    var timeString: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
