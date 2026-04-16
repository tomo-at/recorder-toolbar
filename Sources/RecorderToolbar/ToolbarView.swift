import SwiftUI
import AVFoundation

struct ToolbarView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    private var toolbarHeight: CGFloat {
        switch settings.protoVersion {
        case .v1, .v2, .v3: return 56
        case .v4:           return 66
        case .v5:
            switch settings.v5DefaultStyle {
            case .stepByStep, .revealedAll, .revealedAllCompact: return 56
            case .message:                                     return 66
            case .horizontal:                                  return 48
            }
        }
    }

    var body: some View {
        Group {
            // Upload mode: replace entire toolbar with upload UI
            if state.isUploading && settings.v5UploadStyle == .uploadMode {
                UploadModeView(state: state)
            } else {
                switch state.appState {
                case .typeSelect:
                    switch settings.protoVersion {
                    case .v1: TypeSelectView(state: state)
                    case .v2: TypeSelectViewV2(state: state)
                    case .v3: TypeSelectViewV3(state: state)
                    case .v4: TypeSelectViewV4(state: state)
                    case .v5: V5TypeSelect(state: state)
                    }
                case .windowSelect, .displaySelect:
                    switch settings.protoVersion {
                    case .v1, .v2, .v3: WindowSelectView(state: state)
                    case .v4:           TypeSelectViewV4(state: state)
                    case .v5:           V5WindowSelect(state: state)
                    }
                case .countdown:
                    switch settings.protoVersion {
                    case .v1, .v2, .v3: CountdownToolbarView(state: state)
                    case .v4:           CountdownToolbarViewV4(state: state)
                    case .v5:           V5Countdown(state: state)
                    }
                case .recording:
                    switch settings.protoVersion {
                    case .v1, .v2, .v3: RecordingView(state: state)
                    case .v4:           RecordingViewV4(state: state)
                    case .v5:           V5Recording(state: state)
                    }
                }
            }
        }
        .frame(height: toolbarHeight)
    }
}
