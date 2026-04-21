import AppKit
import AVFoundation

extension ToolbarState {

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
