import AppKit
import SwiftUI

extension ToolbarState {

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

    func enterSelecting(_ mode: SelectionMode) {
        // Dismiss any confirm/preview panels from a previous mode before entering a new one.
        selectionConfirmPanel.dismiss()
        camOnlyPanel.dismiss()

        // Hide overlays for the other modes when switching.
        switch mode {
        case .window:  displayOverlay.hide(); areaOverlay.hideImmediate()
        case .display: overlay.hide();        areaOverlay.hideImmediate()
        case .area:    overlay.hide();        displayOverlay.hide()
        case .camOnly: overlay.hide();        displayOverlay.hide(); areaOverlay.hideImmediate()
        }

        selectionMode = mode

        guard let panel else { return }
        switch mode {
        case .window:
            overlay.show(keepingAbove: panel)
            if shouldUseFullScreenWindowPicker {
                panel.orderOut(nil)
                let screen = NSScreen.main ?? NSScreen.screens[0]
                windowSelectionBottomBar.show(screen: screen, level: panel.level,
                                              message: "Select a window to record")
            }
        case .display:
            displayOverlay.show(keepingAbove: panel)
            if shouldUseFullScreenWindowPicker {
                panel.orderOut(nil)
                let screen = NSScreen.main ?? NSScreen.screens[0]
                windowSelectionBottomBar.show(screen: screen, level: panel.level,
                                              message: "Select a display to record")
            }
        case .area:
            areaOverlay.show(keepingAbove: panel)
            // Toolbar recording style: show pre-recording toolbar immediately on Area click.
            if usesToolbarRecordingStyle {
                appState = .windowSelect
            }
            // selectedRegion: show confirm panel immediately alongside the area overlay.
            if usesSelectionConfirmPanel {
                showAreaConfirmPanel()
                panel.orderOut(nil)
            }
        case .camOnly:
            let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
            if usesToolbarRecordingStyle {
                // Toolbar style: show preview-only panel; toolbar handles controls.
                let sz = PanelDimensions.camOnlyPreviewSize
                let rawX = panel.frame.midX - sz.width / 2
                let origin = NSPoint(
                    x: max(screen.frame.minX + 8, min(rawX, screen.frame.maxX - sz.width - 8)),
                    y: panel.frame.maxY + 8
                )
                camOnlyPanel.showPreview(origin: origin, above: panel,
                                         deviceId: activeCamId)
                appState = .windowSelect
            } else {
                // selectedRegion (and all other styles): show confirm panel with controls.
                let sz = PanelDimensions.camOnlyConfirmSize
                let rawX = panel.frame.midX - sz.width / 2
                let origin = NSPoint(
                    x: max(screen.frame.minX + 8, min(rawX, screen.frame.maxX - sz.width - 8)),
                    y: panel.frame.maxY + 8
                )
                camOnlyPanel.showConfirm(origin: origin, above: panel, state: self,
                    onCancel: { [weak self] in self?.exitSelecting() },
                    onRecord: { [weak self] in
                        guard let self else { return }
                        self.selectionMode = nil
                        self.startCountdown()
                    })
                panel.orderOut(nil)
            }
        }
    }

    func exitSelecting() {
        selectionMode = nil
        switchTargetWindow = nil
        overlay.hide()
        displayOverlay.hide()
        areaOverlay.hide()
        windowSelectionBottomBar.hide()
        selectionConfirmPanel.dismiss()
        camOnlyPanel.dismiss()
        panel?.orderFrontRegardless()
        // Reset to typeSelect (e.g. when area/camOnly+toolbar mode was entered but user cancels).
        if appState == .windowSelect || appState == .displaySelect {
            appState = .typeSelect
        }
    }
}
