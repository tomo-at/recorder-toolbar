import SwiftUI
import AVFoundation

// MARK: – Horizontal layout (V5 DefaultStyle.horizontal)
// Toolbar height: 48px, button height: 32px, icons: 24px

// ── Horizontal: Type Select (482×48) ────────────────────────

struct HorizontalTypeSelectView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        HStack(spacing: 4) {
            HCaptureTypeButton(state: state)
            ToolbarDivider(height: 16)
            HStack(spacing: 8) {
                HCameraDropdown(devices: state.cameraDevices, activeId: $state.activeCamId,
                                onHoverChanged: { h in
                                    guard let panel = state.panel else { return }
                                    if h, let id = state.activeCamId {
                                        state.showCameraPreview(deviceId: id, above: panel)
                                    } else {
                                        state.hideCameraPreview()
                                    }
                                })
                HMicDropdown(devices: state.micDevices, activeId: $state.activeMicId, showIcon: true)
            }
            .padding(.trailing, 8)
            ToolbarDivider(height: 16)
            HSettingsButton(state: state, settings: settings)
        }
        .padding(.horizontal, 8)
        .task { await state.loadDevices() }
    }
}

// ── Horizontal: Window Select (482×48) ──────────────────────

struct HorizontalWindowSelectView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        HStack(spacing: 0) {
            CloseSection {
                state.appState = .typeSelect
            } icon: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            HStack(spacing: 4) {
                HRecordButton { state.startCountdown() }
                ToolbarDivider(height: 16)
                HStack(spacing: 8) {
                    HCameraDropdown(devices: state.cameraDevices, activeId: $state.activeCamId,
                                    fixedWidth: 126,
                                    onHoverChanged: { h in
                                        guard let panel = state.panel else { return }
                                        if h, let id = state.activeCamId {
                                            state.showCameraPreview(deviceId: id, above: panel)
                                        } else {
                                            state.hideCameraPreview()
                                        }
                                    })
                    HMicDropdown(devices: state.micDevices, activeId: $state.activeMicId,
                                 showIcon: true, fixedWidth: 126)
                }
                ToolbarDivider(height: 16)
                HSettingsButton(state: state, settings: settings)
            }
            .padding(.horizontal, 8)
        }
        .task { await state.loadDevices() }
    }
}

// ── Horizontal: Countdown (365×48) ──────────────────────────

struct HorizontalCountdownView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 4) {
            HActionButton(icon: "arrow.counterclockwise", label: "Restart") {
                state.stopRecording(upload: false)
            }
            HActionButton(icon: "pause.fill", label: "Pause",
                          isDisabled: true) {}
            HActionButton(icon: "stop.fill", label: "Stop",
                          iconColor: .recordRed, isDisabled: true) {}
            ToolbarDivider(height: 16)
            Text(String(format: "00:%02d", state.countdownSeconds))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
                .frame(height: 32)
        }
        .padding(.horizontal, 8)
    }
}

// ── Horizontal: Recording (365×48 base, wider with toolbar controls) ───────

struct HorizontalRecordingView: View {
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
        HStack(spacing: 4) {
            if showWindowControls {
                if state.windowRecordingCount >= 2 {
                    ForEach(state.recordedWindows) { window in
                        HWindowButton(window: window) {
                            state.removeWindowViaToolbar(window)
                        }
                    }
                } else {
                    HActionButton(icon: "macwindow", label: "Add") {
                        state.addWindowViaToolbar()
                    }
                }
                ToolbarDivider(height: 16)
            }

            HActionButton(icon: "arrow.counterclockwise", label: "Restart") {
                state.stopRecording(upload: false)
            }
            HActionButton(
                icon:  state.paused ? "play.fill"  : "pause.fill",
                label: state.paused ? "Resume"     : "Pause"
            ) {
                state.togglePause()
            }
            HActionButton(icon: "stop.fill", label: "Stop",
                          iconColor: .recordRed) {
                state.stopRecording()
            }
            ToolbarDivider(height: 16)
            Text(state.timeString)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
                .frame(height: 32)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: – Horizontal shared components

/// Capture type dropdown (Display/Window/Area/CamOnly).
struct HCaptureTypeButton: View {
    @ObservedObject var state: ToolbarState
    @State private var hovering = false
    @State private var showMenu = false

    private var label: String {
        if state.appState == .displaySelect || state.selectionMode == .display { return "Display" }
        return "Window"
    }

    private var icon: String {
        if state.appState == .displaySelect || state.selectionMode == .display { return "display" }
        return "macwindow"
    }

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.contentTertiary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(showMenu ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: showMenu)
            }
            .padding(.horizontal, 4)
            .frame(height: 32)
            .background((hovering || showMenu) ? Color.highlightPrimary : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            CaptureTypeMenuView(state: state)
        }
    }
}

/// Popover menu for capture type selection.
struct CaptureTypeMenuView: View {
    @ObservedObject var state: ToolbarState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            captureRow(icon: "display", label: "Display",
                       isActive: state.selectionMode == .display
                                 || state.appState == .displaySelect) {
                state.activateSelecting(.display)
                dismiss()
            }
            captureRow(icon: "macwindow", label: "Window",
                       isActive: state.selectionMode == .window
                                 || state.appState == .windowSelect) {
                state.activateSelecting(.window)
                dismiss()
            }
            captureRow(icon: "rectangle.dashed", label: "Area", isActive: false) {
                dismiss()
            }
            captureRow(icon: "person.crop.rectangle.fill", label: "Cam only", isActive: false) {
                dismiss()
            }
        }
        .padding(4)
        .background(Color.deviceMenuBg)
        .cornerRadius(8)
        .frame(minWidth: 160)
    }

    @ViewBuilder
    private func captureRow(icon: String, label: String, isActive: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentTeal)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.white.opacity(0.06) : .clear)
    }
}

/// Horizontal camera dropdown: live thumbnail + device name + chevron.
struct HCameraDropdown: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    var fixedWidth: CGFloat? = nil
    var showLabel: Bool = true
    var height: CGFloat = 32
    var onHoverChanged: ((Bool) -> Void)? = nil
    @State private var hovering = false
    @State private var showMenu = false

    var activeDevice: AVCaptureDevice? {
        devices.first { $0.uniqueID == activeId }
    }

    var label: String {
        guard let d = activeDevice else { return "Camera" }
        return String(d.localizedName.replacingOccurrences(of: " Camera", with: "").prefix(12))
    }

    var body: some View {
        Button {
            showMenu.toggle()
            if showMenu { onHoverChanged?(false) }
        } label: {
            HStack(spacing: 4) {
                CameraThumb(deviceId: activeId)
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
                if showLabel {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.contentTertiary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(showMenu ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: showMenu)
            }
            .padding(.horizontal, 4)
            .frame(width: fixedWidth, height: height)
            .background((hovering || showMenu) ? Color.highlightPrimary : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            if !showMenu { onHoverChanged?(h) }
        }
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            DeviceMenuView(devices: devices, activeId: $activeId)
        }
    }
}

/// Horizontal mic dropdown: optional icon + device name + chevron.
struct HMicDropdown: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    var showIcon: Bool = true
    var showLabel: Bool = true
    var fixedWidth: CGFloat? = nil
    var height: CGFloat = 32
    @State private var hovering = false
    @State private var showMenu = false

    var activeDevice: AVCaptureDevice? {
        devices.first { $0.uniqueID == activeId }
    }

    var label: String {
        guard let d = activeDevice else { return "Microphone" }
        return String(d.localizedName.prefix(14))
    }

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 4) {
                if showIcon {
                    MicIconWithLevel(size: 24)
                }
                if showLabel {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.contentTertiary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(showMenu ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: showMenu)
            }
            .padding(.horizontal, 4)
            .frame(width: fixedWidth, height: height)
            .background((hovering || showMenu) ? Color.highlightPrimary : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            DeviceMenuView(devices: devices, activeId: $activeId)
        }
    }
}

/// Horizontal settings button: gear icon (+ optional chevron).
struct HSettingsButton: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    var showChevron: Bool = false
    var height: CGFloat = 32
    @State private var hovering = false

    var body: some View {
        Button {
            settings.settingsBadge = false
            if let panel = state.panel {
                state.settingsPanel.toggle(toolbar: panel,
                                           buttonCenterX: panel.frame.maxX - (showChevron ? 34 : 24))
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                if showChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.contentTertiary)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(state.settingsPanel.isVisible ? 180 : 0))
                        .animation(.easeInOut(duration: 0.15), value: state.settingsPanel.isVisible)
                }
            }
            .padding(.horizontal, 4)
            .frame(width: showChevron ? 52 : 32, height: height)
            .background((hovering || state.settingsPanel.isVisible) ? Color.highlightPrimary : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Horizontal action button: icon (24px) + label, height 32px.
struct HActionButton: View {
    let icon:       String
    let label:      String
    var iconColor:  Color = .white
    var isDisabled: Bool  = false
    let action:     () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(hovering && !isDisabled ? Color.highlightPrimary : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
    }
}

/// Window button for toolbar controls multi-recording: shows app icon + name, hover → "Remove".
struct HWindowButton: View {
    let window: DetectedWindow
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                }
                Text(hovering ? "Remove" : String(window.appName.prefix(9)))
                    .font(.system(size: 13))
                    .foregroundColor(hovering ? .accentDestructive : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(nil, value: hovering)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(hovering ? Color.highlightPrimary : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(window.appName)
    }
}

/// Red record button for horizontal layout.
struct HRecordButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 14))
                Text("Record")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(width: 96, height: 32)
            .background(hovering ? Color.recordRed.opacity(0.85) : Color.recordRed)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: – Revealed all (compact) layout (V5 DefaultStyle.revealedAllCompact)

struct RevealedAllCompactTypeSelectView: View {
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

                    SegmentButton(icon: "rectangle.dashed", label: "Area") {}
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
                    HCameraDropdown(devices: state.cameraDevices, activeId: $state.activeCamId,
                                    fixedWidth: 52, showLabel: false, height: 48,
                                    onHoverChanged: { h in
                                        guard let panel = state.panel else { return }
                                        if h, let id = state.activeCamId {
                                            state.showCameraPreview(deviceId: id, above: panel)
                                        } else {
                                            state.hideCameraPreview()
                                        }
                                    })
                    HMicDropdown(devices: state.micDevices, activeId: $state.activeMicId,
                                 showIcon: true, showLabel: false, fixedWidth: 52, height: 48)
                }
                .padding(.trailing, 8)

                ToolbarDivider()

                HSettingsButton(state: state, settings: settings, showChevron: true, height: 48)
            }
            .padding(.horizontal, 8)
        }
        .task { await state.loadDevices() }
    }
}
