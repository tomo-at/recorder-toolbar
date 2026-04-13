import SwiftUI
import AVFoundation

struct ToolbarView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        Group {
            switch state.appState {
            case .typeSelect:                   TypeSelectViewV2(state: state)
            case .windowSelect, .displaySelect: WindowSelectView(state: state)
            case .countdown:                    CountdownToolbarView(state: state)
            case .recording:                    RecordingView(state: state)
            }
        }
        .frame(height: 56)
    }
}

// ── State 1: Type Select ────────────────────────────────────

struct TypeSelectView: View {
    @ObservedObject var state: ToolbarState
    @State private var activeCamId: String?

    var body: some View {
        HStack(spacing: 0) {
            // Close button
            CloseSection(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }

            // Segment strip
            HStack(spacing: 0) {
                SegmentButton(icon: "display", label: "Display",
                              isActive: state.selectionMode == .display) {
                    state.toggleSelecting(.display)
                }
                .onHover { h in
                    preview(h ? .display : nil)
                    if h { tooltip("Record Screen", "⇧⌘6", 84) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentButton(icon: "macwindow", label: "Window",
                              isActive: state.selectionMode == .window) {
                    state.toggleSelecting(.window)
                }
                .onHover { h in
                    preview(h ? .window : nil)
                    if h { tooltip("Record Window", "⇧⌘7", 148) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentButton(icon: "rectangle.dashed", label: "Area") {}
                    .onHover { h in
                        preview(h ? .area : nil)
                        if h { tooltip("Record Area", "⇧⌘8", 212) }
                        else  { state.shortcutTooltip.hide() }
                    }

                CamOnlySegment(activeId: activeCamId) { h in
                    guard let panel = state.panel else { return }
                    if h, let id = activeCamId {
                        state.showCameraPreview(deviceId: id, above: panel)
                    } else {
                        state.hideCameraPreview()
                    }
                }

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Settings") {
                    // Settings button center x from toolbar left = 44(close) + 8(pad) + 64×4(segs) + 9(div) + 32(half btn) = 349
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 349)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .task { await loadCameraDevice() }
    }

    private func loadCameraDevice() async {
        activeCamId = AVCaptureDevice.cameraDevices().first?.uniqueID
    }

    private func preview(_ type: PreviewType?) {
        guard let panel = state.panel else { return }
        if let t = type { state.previewOverlay.show(t, keepingAbove: panel) }
        else            { state.previewOverlay.hide() }
    }

    private func tooltip(_ label: String, _ shortcut: String, _ centerX: CGFloat) {
        guard let panel = state.panel else { return }
        state.shortcutTooltip.show(label: label, shortcut: shortcut,
                                   buttonCenterX: centerX, above: panel)
    }
}

// ── State 2: Window Select ──────────────────────────────────

struct WindowSelectView: View {
    @ObservedObject var state: ToolbarState
    @State private var cameraDevices: [AVCaptureDevice] = []
    @State private var micDevices:    [AVCaptureDevice] = []
    @State private var activeCamId:   String?           = nil
    @State private var activeMicId:   String?           = nil

    var body: some View {
        HStack(spacing: 0) {
            // Back button
            CloseSection {
                state.appState = .typeSelect
            } icon: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }

            HStack(spacing: 0) {
                // Camera + Mic (8px gap between them, 8px right padding)
                HStack(spacing: 8) {
                    CameraSegment(devices: cameraDevices, activeId: $activeCamId,
                                  onHoverChanged: { h in
                                      guard let panel = state.panel else { return }
                                      if h, let id = activeCamId {
                                          state.showCameraPreview(deviceId: id, above: panel)
                                      } else {
                                          state.hideCameraPreview()
                                      }
                                  })
                    MicSegment(devices: micDevices, activeId: $activeMicId)
                }
                .padding(.trailing, 8)

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Settings") {
                    // Settings button center x from toolbar left = 44(close) + 64(cam) + 8(gap) + 64(mic) + 8(trail) + 9(div) + 32(half btn) = 229
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 229)
                    }
                }

                ToolbarDivider()

                // Record button
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
            await loadDevices()
        }
        .keyboardShortcut(.escape, modifiers: [])
        .onExitCommand { state.appState = .typeSelect }
    }

    func loadDevices() async {
        cameraDevices = AVCaptureDevice.cameraDevices()
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID
        micDevices    = AVCaptureDevice.micDevices()
        activeMicId   = activeMicId ?? micDevices.first?.uniqueID
    }
}

// ── State 3: Countdown ──────────────────────────────────────

struct CountdownToolbarView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 0) {
            CloseSection(action: { state.appState = .typeSelect }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(spacing: 4) {
                Text("\(state.countdownSeconds)")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                Text("Starting...")
                    .font(.system(size: 11))
                    .foregroundColor(Color.subtitleGray)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// ── State 4: Recording ──────────────────────────────────────

struct RecordingView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 0) {
            SegmentButton(icon: "arrow.counterclockwise", label: "Restart") {
                state.stopRecording()
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
                Text("1 hour limit")
                    .font(.system(size: 11))
                    .foregroundColor(Color.subtitleGray)
            }
            .frame(width: 80, height: 48)
        }
        .padding(.horizontal, 8)
    }
}

// ── Shared Components ───────────────────────────────────────

struct CloseSection<Icon: View>: View {
    let action: () -> Void
    let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .background(Color.black.opacity(0.16))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
        }
    }
}

struct SegmentButton: View {
    let icon:      String
    let label:     String
    var iconColor: Color = .white
    var isActive:  Bool  = false
    let action:    () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.69))
                    .lineLimit(1)
            }
            .frame(width: 64, height: 48)
            .background(isActive ? Color.white.opacity(0.16) : (hovering ? Color.white.opacity(0.08) : .clear))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ActionButton: View {
    let icon:   String
    let label:  String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(width: 80, height: 36)
            .background(hovering
                ? Color.white.opacity(0.14)
                : Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
    }
}

// ── V2: Type Select (Camera + Mic always visible) ───────────
// Layout (550px): [X(44)] [Display|Window|Area|CamOnly(256)+8] [div(9)] [Cam+Mic(136)+8] [div(9)] [Settings(64)] + outer pad(8×2)

struct TypeSelectViewV2: View {
    @ObservedObject var state: ToolbarState
    @State private var cameraDevices: [AVCaptureDevice] = []
    @State private var micDevices:    [AVCaptureDevice] = []
    @State private var activeCamId:   String?           = nil
    @State private var activeMicId:   String?           = nil

    var body: some View {
        HStack(spacing: 0) {
            CloseSection(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }

            HStack(spacing: 0) {
                // Recording type selector
                HStack(spacing: 0) {
                    SegmentButton(icon: "display", label: "Display",
                                  isActive: state.selectionMode == .display) {
                        state.toggleSelecting(.display)
                    }
                    .onHover { h in
                        preview(h ? .display : nil)
                        if h { tooltip("Record Screen", "⇧⌘6", 84) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentButton(icon: "macwindow", label: "Window",
                                  isActive: state.selectionMode == .window) {
                        state.toggleSelecting(.window)
                    }
                    .onHover { h in
                        preview(h ? .window : nil)
                        if h { tooltip("Record Window", "⇧⌘7", 148) }
                        else  { state.shortcutTooltip.hide() }
                    }

                    SegmentButton(icon: "rectangle.dashed", label: "Area") {}
                        .onHover { h in
                            preview(h ? .area : nil)
                            if h { tooltip("Record Area", "⇧⌘8", 212) }
                            else  { state.shortcutTooltip.hide() }
                        }

                    CamOnlySegment(activeId: activeCamId) { h in
                        guard let panel = state.panel else { return }
                        if h, let id = activeCamId {
                            state.showCameraPreview(deviceId: id, above: panel)
                        } else {
                            state.hideCameraPreview()
                        }
                    }
                }
                .padding(.trailing, 8)

                ToolbarDivider()

                // Camera + Mic (always visible in V2)
                HStack(spacing: 8) {
                    CameraSegment(devices: cameraDevices, activeId: $activeCamId,
                                  onHoverChanged: { h in
                                      guard let panel = state.panel else { return }
                                      if h, let id = activeCamId {
                                          state.showCameraPreview(deviceId: id, above: panel)
                                      } else {
                                          state.hideCameraPreview()
                                      }
                                  })
                    MicSegment(devices: micDevices, activeId: $activeMicId)
                }
                .padding(.trailing, 8)

                ToolbarDivider()

                // Settings — center X from toolbar left: 44+8+264+9+144+9+32 = 510
                SegmentButton(icon: "gearshape.fill", label: "Settings") {
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 510)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .task { await loadDevices() }
    }

    private func loadDevices() async {
        cameraDevices = AVCaptureDevice.cameraDevices()
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID
        micDevices    = AVCaptureDevice.micDevices()
        activeMicId   = activeMicId ?? micDevices.first?.uniqueID
    }

    private func preview(_ type: PreviewType?) {
        guard let panel = state.panel else { return }
        if let t = type { state.previewOverlay.show(t, keepingAbove: panel) }
        else            { state.previewOverlay.hide() }
    }

    private func tooltip(_ label: String, _ shortcut: String, _ centerX: CGFloat) {
        guard let panel = state.panel else { return }
        state.shortcutTooltip.show(label: label, shortcut: shortcut,
                                   buttonCenterX: centerX, above: panel)
    }
}

// ── Shortcut tooltip view (light appearance, shown above type-select buttons) ──

struct ShortcutTooltipView: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white)
            Text(shortcut)
                .font(.system(size: 12))
                .foregroundColor(Color.subtitleGray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(red: 0.22, green: 0.22, blue: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        .padding(7)    // room for shadow to render without clipping
    }
}

