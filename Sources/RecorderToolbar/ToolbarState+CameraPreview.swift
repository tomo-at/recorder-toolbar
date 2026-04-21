import AppKit
import SwiftUI

extension ToolbarState {

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
}
