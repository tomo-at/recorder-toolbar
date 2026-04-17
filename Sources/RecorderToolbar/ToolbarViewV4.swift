import SwiftUI
import AVFoundation

// MARK: – V4 toolbar views (message header bar)

// Layout (482px): [SegItems(4×64=256)] [div(9)] [Cam+Mic+trail(144)] [div(9)] [Settings(64)]
struct TypeSelectViewV4: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var headerMessage: String {
        if state.appState == .displaySelect || state.appState == .windowSelect {
            return "Click Record when you're ready"
        }
        switch state.selectionMode {
        case .display: return "Click a display to start recording"
        case .window:  return "Click a window to start recording"
        case nil:      return "Choose a recording type"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolbarHeader(message: headerMessage)

            HStack(spacing: 0) {
                SegmentedControlItem(icon: "display", label: "Display",
                                     isActive: state.selectionMode == .display
                                               || state.appState == .displaySelect) {
                    state.toggleSelecting(.display)
                }
                .onHover { h in
                    state.showPreview(h ? .display : nil)
                    if h { state.showTooltip("Record Screen", "⇧⌘6", buttonCenterX: 32) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentedControlItem(icon: "macwindow", label: "Window",
                                     isActive: state.selectionMode == .window
                                               || state.appState == .windowSelect) {
                    state.toggleSelecting(.window)
                }
                .onHover { h in
                    state.showPreview(h ? .window : nil)
                    if h { state.showTooltip("Record Window", "⇧⌘7", buttonCenterX: 96) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentedControlItem(icon: "rectangle.dashed", label: "Area") {}
                    .onHover { h in
                        state.showPreview(h ? .area : nil)
                        if h { state.showTooltip("Record Area", "⇧⌘8", buttonCenterX: 160) }
                        else  { state.shortcutTooltip.hide() }
                    }

                SegmentedControlItem(icon: "person.crop.rectangle.fill", label: "Cam only") {}
                    .onHover { h in
                        guard let panel = state.panel else { return }
                        if h, let id = state.activeCamId {
                            state.showCameraPreview(deviceId: id, above: panel)
                        } else {
                            state.hideCameraPreview()
                        }
                    }

                ToolbarDivider()

                HStack(spacing: 8) {
                    CameraSegment(devices: state.cameraDevices, activeId: $state.activeCamId,
                                  onHoverChanged: { h in
                                      guard let panel = state.panel else { return }
                                      if h, let id = state.activeCamId {
                                          state.showCameraPreview(deviceId: id, above: panel)
                                      } else {
                                          state.hideCameraPreview()
                                      }
                                  })
                    MicSegment(devices: state.micDevices, activeId: $state.activeMicId)
                }
                .padding(.trailing, 8)

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Settings",
                              showBadge: settings.settingsBadge) {
                    settings.settingsBadge = false
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 450)
                    }
                }
            }
        }
        .task { await state.loadDevices() }
    }
}

// Layout (346px): [Cam+Mic+trail(144)] [div(9)] [Settings(64)] [div(9)] [lead(8)+Record+trail(16)]
struct WindowSelectViewV4: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarHeader(message: "Click Record when you're ready")

            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    CameraSegment(devices: state.cameraDevices, activeId: $state.activeCamId,
                                  onHoverChanged: { h in
                                      guard let panel = state.panel else { return }
                                      if h, let id = state.activeCamId {
                                          state.showCameraPreview(deviceId: id, above: panel)
                                      } else {
                                          state.hideCameraPreview()
                                      }
                                  })
                    MicSegment(devices: state.micDevices, activeId: $state.activeMicId)
                }
                .padding(.trailing, 8)

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Settings") {
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 185)
                    }
                }

                ToolbarDivider()

                Button {
                    state.startCountdown()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 12))
                        Text("Record")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.recordRed)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .padding(.trailing, 16)
            }
        }
        .task { await state.loadDevices() }
    }
}

struct CountdownToolbarViewV4: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarHeader(message: "Starting in \(state.countdownSeconds)...")

            HStack(spacing: 0) {
                SegmentButton(icon: "arrow.counterclockwise", label: "Restart") {
                    state.stopRecording()
                }
                SegmentButton(icon: "pause.fill", label: "Pause",
                              isDisabled: true) {}
                SegmentButton(icon: "stop.fill", label: "Stop",
                              iconColor: Color.recordRed,
                              isDisabled: true) {}

                ToolbarDivider()

                VStack(spacing: 4) {
                    Text(String(format: "00:%02d", state.countdownSeconds))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(.white)
                    Text("Starting...")
                        .font(.system(size: 11))
                        .foregroundColor(Color.subtitleGray)
                }
                .frame(width: 80, height: 48)
            }
            .padding(.horizontal, 8)
        }
    }
}

struct RecordingViewV4: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarHeader(message: "Recording in progress")

            HStack(spacing: 0) {
                SegmentButton(icon: "arrow.counterclockwise", label: "Restart") {
                    state.stopRecording()
                }
                SegmentButton(
                    icon:  state.paused ? "play.fill"  : "pause.fill",
                    label: state.paused ? "Resume"     : "Pause"
                ) {
                    state.togglePause()
                }
                SegmentButton(icon: "stop.fill", label: "Stop",
                              iconColor: Color.recordRed) {
                    state.stopRecording()
                }

                ToolbarDivider()

                VStack(spacing: 4) {
                    Text(state.timeString)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundColor(.white)
                    Text("1 hour limit")
                        .font(.system(size: 11))
                        .foregroundColor(Color.subtitleGray)
                }
                .frame(width: 80, height: 48)
            }
            .padding(.horizontal, 8)
        }
    }
}

// ── Selection confirm panel view (V4) ──────────────────────

struct SelectionConfirmView: View {
    let onCancel: () -> Void
    let onRecord: () -> Void
    @State private var cameraDeviceId: String? = nil
    @State private var cancelHovering = false

    private let panelBg = Color.bgSecondary

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let id = cameraDeviceId {
                    CameraThumb(deviceId: id)
                } else {
                    Color.black
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 172)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.highlightPrimary)
                    .frame(height: 1)
            }

            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 28)
                        .background(cancelHovering ? Color.highlightPrimary : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { cancelHovering = $0 }

                Button(action: onRecord) {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 12))
                        Text("Record")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Color.recordRed)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .frame(height: 44)
        }
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.highlightPrimary, lineWidth: 1)
        )
        .task {
            cameraDeviceId = AVCaptureDevice.cameraDevices().first?.uniqueID
        }
    }
}
