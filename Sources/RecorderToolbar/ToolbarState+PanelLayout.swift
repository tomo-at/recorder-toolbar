import AppKit

extension ToolbarState {

    // MARK: – Panel dimensions

    enum PanelDimensions {
        static let v1Width:                  CGFloat = 345
        static let v2Width:                  CGFloat = 506
        static let v3Width:                  CGFloat = 510
        static let v4Width:                  CGFloat = 482
        static let v5CompactWidth:           CGFloat = 470
        static let windowSelectWidth:        CGFloat = 389
        static let recordingWidth:           CGFloat = 297
        static let horizontalRecordingWidth: CGFloat = 365
        static let defaultHeight:            CGFloat = 56
        static let camOnlyConfirmSize        = CGSize(width: 1080, height: 652)
        static let camOnlyPreviewSize        = CGSize(width: 1080, height: 608)
        static let selectionConfirmSize      = CGSize(width: 284,  height: 204)
        static let hSheetSize                = CGSize(width: 324,  height: 400)
        static let hSheetScrollHeight:       CGFloat = 312
        static let hSheetCellSize            = CGSize(width: 148,  height: 84)
    }

    // MARK: – Panel resize

    func resizePanel(for state: AppState) {
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
                newW = isHorizontal ? (PanelDimensions.horizontalRecordingWidth + extraH) : (PanelDimensions.recordingWidth + extraV)
            } else {
                newW = isHorizontal ? PanelDimensions.horizontalRecordingWidth : PanelDimensions.recordingWidth
            }
        case .typeSelect:
            switch s.protoVersion {
            case .v1: newW = PanelDimensions.v1Width
            case .v2: newW = PanelDimensions.v2Width
            case .v3: newW = PanelDimensions.v3Width
            case .v4: newW = PanelDimensions.v4Width
            case .v5: newW = v5TypeSelectWidth(for: s.v5DefaultStyle)
            }
        case .windowSelect, .displaySelect:
            switch s.protoVersion {
            case .v1, .v2, .v3: newW = PanelDimensions.windowSelectWidth
            case .v4: newW = PanelDimensions.v4Width
            case .v5:
                switch s.v5RecordingStyle {
                case .selectedRegion:
                    // typeSelect が出続けるので幅は defaultStyle に合わせる
                    newW = v5TypeSelectWidth(for: s.v5DefaultStyle)
                case .toolbar:
                    newW = isHorizontal ? PanelDimensions.v4Width : PanelDimensions.windowSelectWidth
                }
            }
        }
        let cx = panel.frame.midX
        let y  = panel.frame.origin.y
        panel.setFrame(NSRect(x: cx - newW / 2, y: y, width: newW, height: newH),
                       display: true, animate: true)
    }

    func v5TypeSelectWidth(for style: SettingsState.DefaultStyle) -> CGFloat {
        switch style {
        case .stepByStep:         return PanelDimensions.v1Width
        case .revealedAll:        return PanelDimensions.v2Width
        case .message:            return PanelDimensions.v4Width
        case .horizontal:         return PanelDimensions.v4Width
        case .revealedAllCompact: return PanelDimensions.v5CompactWidth
        }
    }

    func panelHeight(for s: SettingsState) -> CGFloat {
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

    /// Current toolbar panel height — used by ToolbarView to keep SwiftUI frame in sync.
    var currentPanelHeight: CGFloat { panelHeight(for: settingsPanel.state) }
}
