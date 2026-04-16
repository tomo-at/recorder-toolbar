import SwiftUI
import AVFoundation

// MARK: – V5: 3-axis dispatch + Upload mode
//
// Default style    : Step by step (V1) / Revealed all (V2) / Message (V4-style header)
//                    / Horizontal layout / Revealed all (compact)
// Recording style  : Toolbar / Select to start / Selected region
// Upload style     : Toolbar / Menu bar + Notification / Upload mode

struct V5TypeSelect: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }
    var body: some View {
        Group {
            switch settings.v5DefaultStyle {
            case .stepByStep:        TypeSelectView(state: state)
            case .revealedAll:       TypeSelectViewV2(state: state)
            case .message:           TypeSelectViewV4(state: state)
            case .horizontal:        HorizontalTypeSelectView(state: state)
            case .revealedAllCompact: RevealedAllCompactTypeSelectView(state: state)
            }
        }
        .overlay(alignment: .top) {
            let showsProgress = (settings.v5UploadStyle == .toolbar || settings.v5UploadStyle == .toolbarWithCompleteMessage) && state.isUploading
            if showsProgress {
                V5UploadProgressBar(progress: state.uploadProgress)
                    .padding(.top, settings.v5DefaultStyle == .message ? 16 : 0)
            }
        }
    }
}

struct V5WindowSelect: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }
    var body: some View {
        switch settings.v5RecordingStyle {
        case .selectToStart, .selectedRegion:
            V5TypeSelect(state: state)
        case .toolbar:
            if settings.v5DefaultStyle == .horizontal {
                HorizontalWindowSelectView(state: state)
            } else {
                V5MaybeHeadered(state: state, message: "Click Record when you're ready") {
                    WindowSelectView(state: state)
                }
            }
        }
    }
}

struct V5Countdown: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }
    var body: some View {
        if settings.v5DefaultStyle == .horizontal {
            HorizontalCountdownView(state: state)
        } else {
            V5MaybeHeadered(state: state, message: "Starting in \(state.countdownSeconds)...") {
                CountdownToolbarView(state: state)
            }
        }
    }
}

struct V5Recording: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }
    var body: some View {
        if settings.v5DefaultStyle == .horizontal {
            HorizontalRecordingView(state: state)
        } else {
            V5MaybeHeadered(state: state, message: "Recording in progress") {
                RecordingView(state: state)
            }
        }
    }
}

/// Shows ToolbarHeader only when DefaultStyle == .message.
struct V5MaybeHeadered<Content: View>: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    let message: String
    let content: Content
    init(state: ToolbarState, message: String, @ViewBuilder content: () -> Content) {
        self.state    = state
        self.settings = state.settingsPanel.state
        self.message  = message
        self.content  = content()
    }
    var body: some View {
        if settings.v5DefaultStyle == .message {
            VStack(spacing: 0) {
                ToolbarHeader(message: message)
                content
            }
        } else {
            content
        }
    }
}

/// V5: thin (2px) upload progress bar overlay.
struct V5UploadProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.modelessBlack24)
                Rectangle().fill(Color.modelessTeal)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
            }
        }
        .frame(height: 2)
    }
}

// MARK: – Upload mode (UploadStyle.uploadMode)

struct UploadModeView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    @State private var hovering = false

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        if state.uploadComplete {
            uploadCompleteBody
        } else {
            uploadingBody
        }
    }

    // MARK: – Uploading state

    private var uploadingBody: some View {
        VStack(spacing: 0) {
            if settings.v5DefaultStyle == .message {
                ToolbarHeader(message: "Uploading… \(Int(state.uploadProgress * 100))%")
            }

            HStack(spacing: 0) {
                Group {
                    if hovering {
                        Button {
                            state.cancelUpload()
                        } label: {
                            Text("Cancel")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                                .background(Color.highlightSecondary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Uploading video")
                            .font(.system(size: 11))
                            .foregroundColor(.contentSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 100)
                .padding(.trailing, 16)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.highlightPrimary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.modelessTeal)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, state.uploadProgress))))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    // MARK: – Upload complete state

    private var uploadCompleteBody: some View {
        VStack(spacing: 0) {
            if settings.v5DefaultStyle == .message {
                ToolbarHeader(message: "Completed")
            }

            HStack(spacing: 8) {
                Text("Upload complete ✓")
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    // prototype: no-op
                } label: {
                    Label("View video", systemImage: "play.rectangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 126, height: 28)
                        .background(Color.highlightSecondary)
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)

                Button {
                    state.dismissUploadComplete()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "record.circle.fill")
                            .foregroundColor(.modelessDestructive)
                        Text("New recording")
                            .foregroundColor(.white)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 126, height: 28)
                    .background(Color.highlightSecondary)
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
