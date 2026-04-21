import AppKit

extension ToolbarState {

    // MARK: – Area confirm panel

    /// Show (or reposition) the SelectionConfirmPanel for the live area selection.
    func showAreaConfirmPanel() {
        guard let panel else { return }
        let origin = confirmPanelOriginForArea(rect: areaOverlay.currentRect, above: panel)
        let confirmSize = PanelDimensions.selectionConfirmSize
        areaOverlay.confirmPanelFrame = CGRect(origin: origin, size: confirmSize)
        selectionConfirmPanel.show(origin: origin, above: panel, state: self,
            onCancel: { [weak self] in self?.exitSelecting() },
            onRecord: { [weak self] in
                guard let self else { return }
                self.areaOverlay.freeze()
                self.selectionMode = nil
                self.startCountdown()
            })
    }

    /// Returns the bottom-left origin (AppKit screen coords) for the SelectionConfirmPanel.
    /// Places the panel inside the selection at bottom-left; if the area is too small,
    /// places it just below the selection instead.
    func confirmPanelOriginForArea(rect: CGRect?, above panel: NSPanel) -> NSPoint {
        let confirmSize = PanelDimensions.selectionConfirmSize
        let margin: CGFloat = 8

        if let r = rect,
           r.width  >= confirmSize.width  + margin * 2,
           r.height >= confirmSize.height + margin * 2 {
            return NSPoint(x: r.minX + margin, y: r.minY + margin)
        }

        if let r = rect {
            return NSPoint(x: r.minX, y: r.minY - confirmSize.height - margin)
        }

        return NSPoint(x: panel.frame.minX, y: panel.frame.maxY + margin)
    }
}
