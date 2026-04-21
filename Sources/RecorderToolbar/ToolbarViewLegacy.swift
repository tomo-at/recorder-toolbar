import SwiftUI
import AVFoundation

// MARK: – V1/V2/V3 toolbar views

// ── V1: Type Select ────────────────────────────────────────

struct TypeSelectView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                SegmentButton(icon: "display", label: "Display",
                              isActive: state.selectionMode == .display
                                        || state.appState == .displaySelect) {
                    state.toggleSelecting(.display)
                }
                .onHover { h in
                    state.showPreview(h ? .display : nil)
                    if h { state.showTooltip("Record Screen", "⇧⌘6", buttonCenterX: 40) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentButton(icon: "macwindow", label: "Window",
                              isActive: state.selectionMode == .window
                                        || state.appState == .windowSelect) {
                    state.toggleSelecting(.window)
                }
                .onHover { h in
                    state.showPreview(h ? .window : nil)
                    if h { state.showTooltip("Record Window", "⇧⌘7", buttonCenterX: 104) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentButton(icon: "rectangle.dashed", label: "Area",
                              isActive: state.selectionMode == .area) {
                    state.toggleSelecting(.area)
                }
                .onHover { h in
                    state.showPreview(h ? .area : nil)
                    if h { state.showTooltip("Record Area", "⇧⌘8", buttonCenterX: 168) }
                    else  { state.shortcutTooltip.hide() }
                }

                CamOnlySegment(activeId: state.activeCamId) { h in
                    guard let panel = state.panel else { return }
                    if h, let id = state.activeCamId {
                        state.showCameraPreview(deviceId: id, above: panel)
                    } else {
                        state.hideCameraPreview()
                    }
                }

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Settings",
                              showBadge: settings.settingsBadge) {
                    settings.settingsBadge = false
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 305)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            if state.isUploading {
                UploadProgressBarView(progress: state.uploadProgress)
            }
        }
        .task { await state.loadDevices() }
    }
}

// ── State 2: Window Select ──────────────────────────────────

struct WindowSelectView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 0) {
            CloseSection {
                state.appState = .typeSelect
            } icon: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

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
                                                   buttonCenterX: panel.frame.minX + 229)
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
        .task {
            await state.loadDevices()
        }
        .keyboardShortcut(.escape, modifiers: [])
        .onExitCommand { state.appState = .typeSelect }
    }
}

// ── State 3: Countdown ──────────────────────────────────────

struct CountdownToolbarView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 0) {
            SegmentButton(icon: "arrow.counterclockwise", label: "Restart") {
                state.stopRecording(upload: false)
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
                    .frame(height: 20)
                Text("Starting...")
                    .font(.system(size: 11))
                    .foregroundColor(Color.subtitleGray)
            }
            .frame(width: 80, height: 48)
        }
        .padding(.horizontal, 8)
    }
}

// ── State 4: Recording ──────────────────────────────────────

struct RecordingView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    private var showWindowControls: Bool {
        settings.addWindowPattern == .toolbarControls && state.isWindowRecording
    }

    var body: some View {
        HStack(spacing: 0) {
            if showWindowControls {
                // Primary window (always shown)
                if let primary = state.recordedWindows.first {
                    WindowSegmentButton(
                        window: primary,
                        onRemove: { state.removeWindowViaToolbar(primary) },
                        onSwitch: state.windowRecordingCount >= 2 ? { state.changeWindowViaToolbar() } : nil,
                        onShowPopup: { f, r, s in state.showToolbarWindowPopup(at: f, onRemove: r, onSwitch: s) }
                    )
                }
                // Additional windows
                ForEach(state.recordedWindows.dropFirst()) { window in
                    WindowSegmentButton(
                        window: window,
                        onRemove: { state.removeWindowViaToolbar(window) },
                        onSwitch: { state.switchWindowViaToolbar(window) },
                        onShowPopup: { f, r, s in state.showToolbarWindowPopup(at: f, onRemove: r, onSwitch: s) }
                    )
                }
                // Add button — only when below max (2 windows)
                if state.windowRecordingCount < 2 {
                    SegmentButton(icon: "plus", label: "Add") {
                        state.addWindowViaToolbar()
                    }
                }
                ToolbarDivider()
            }

            SegmentButton(icon: "arrow.counterclockwise", label: "Restart") {
                state.stopRecording(upload: false)
            }
            SegmentButton(
                icon:      state.paused ? "play.fill"  : "pause.fill",
                label:     state.paused ? "Resume"     : "Pause"
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
                    .frame(height: 20)
                Text("1 hour limit")
                    .font(.system(size: 11))
                    .foregroundColor(Color.subtitleGray)
            }
            .frame(width: 80, height: 48)
        }
        .padding(.horizontal, 8)
    }
}

/// Window button styled like SegmentButton (VStack icon+label, 64×48).
/// Hover: subtle highlight. Click: DSDialogContainer popup with Remove (1 window) or Switch+Remove (2 windows).
struct WindowSegmentButton: View {
    let window: DetectedWindow
    var onRemove: () -> Void = {}
    var onSwitch: (() -> Void)? = nil
    var onShowPopup: (CGRect, @escaping () -> Void, (() -> Void)?) -> Void = { _, _, _ in }
    @StateObject private var frameReader = ButtonFrameReader()
    @State private var hovering = false

    var body: some View {
        Button {
            guard let frame = frameReader.screenFrame else { return }
            onShowPopup(frame, onRemove, onSwitch)
        } label: {
            VStack(spacing: 4) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                }
                Text(window.appName)
                    .foregroundColor(Color.contentTertiary)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 64, height: 48)
            .background(hovering ? Color.highlightPrimary : .clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .background(ButtonFrameCaptureView(reader: frameReader))
        .onHover { hovering = $0 }
        .help(window.appName)
    }
}

// ── V2: Type Select (Camera + Mic always visible) ───────────

struct TypeSelectViewV2: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    SegmentButton(icon: "display", label: "Display",
                                  isActive: state.selectionMode == .display
                                            || state.appState == .displaySelect) {
                        state.toggleSelecting(.display)
                    }
                    .onHover { h in
                        state.showPreview(h ? .display : nil)
                        if h { state.showTooltip("Record Screen", "⇧⌘6", buttonCenterX: 40) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentButton(icon: "macwindow", label: "Window",
                                  isActive: state.selectionMode == .window
                                            || state.appState == .windowSelect) {
                        state.toggleSelecting(.window)
                    }
                    .onHover { h in
                        state.showPreview(h ? .window : nil)
                        if h { state.showTooltip("Record Window", "⇧⌘7", buttonCenterX: 104) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentButton(icon: "rectangle.dashed", label: "Area",
                                  isActive: state.selectionMode == .area) {
                        state.toggleSelecting(.area)
                    }
                    .onHover { h in
                        state.showPreview(h ? .area : nil)
                        if h { state.showTooltip("Record Area", "⇧⌘8", buttonCenterX: 168) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    CamOnlySegment(activeId: state.activeCamId) { h in
                        guard let panel = state.panel else { return }
                        if h, let id = state.activeCamId {
                            state.showCameraPreview(deviceId: id, above: panel)
                        } else {
                            state.hideCameraPreview()
                        }
                    }
                }
                .padding(.trailing, 8)

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
                                                   buttonCenterX: panel.frame.minX + 466)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .task { await state.loadDevices() }
    }
}

// ── V3: Segmented Control type selector ────────────────────

struct SegmentedControlItem: View {
    let icon:     String
    let label:    String
    var isActive: Bool = false
    let action:   () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .white : Color.contentTertiary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive  ? Color.white.opacity(0.16)
                          : hovering ? Color.highlightPrimary
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct TypeSelectViewV3: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    SegmentedControlItem(icon: "display", label: "Display",
                                         isActive: state.selectionMode == .display) {
                        state.toggleSelecting(.display)
                    }
                    .onHover { h in
                        state.showPreview(h ? .display : nil)
                        if h { state.showTooltip("Record Screen", "⇧⌘6", buttonCenterX: 42) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentedControlItem(icon: "macwindow", label: "Window",
                                         isActive: state.selectionMode == .window) {
                        state.toggleSelecting(.window)
                    }
                    .onHover { h in
                        state.showPreview(h ? .window : nil)
                        if h { state.showTooltip("Record Window", "⇧⌘7", buttonCenterX: 106) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentedControlItem(icon: "rectangle.dashed", label: "Area",
                                         isActive: state.selectionMode == .area) {
                        state.toggleSelecting(.area)
                    }
                    .onHover { h in
                        state.showPreview(h ? .area : nil)
                        if h { state.showTooltip("Record Area", "⇧⌘8", buttonCenterX: 170) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentedControlItem(icon: "person.crop.rectangle.fill",
                                         label: "Cam only") {}
                        .onHover { h in
                            guard let panel = state.panel else { return }
                            if h, let id = state.activeCamId {
                                state.showCameraPreview(deviceId: id, above: panel)
                            } else {
                                state.hideCameraPreview()
                            }
                        }
                }
                .padding(2)
                .background(Color.black.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.trailing, 8)

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

                SegmentButton(icon: "gearshape.fill", label: "Settings") {
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 470)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .task { await state.loadDevices() }
    }
}
