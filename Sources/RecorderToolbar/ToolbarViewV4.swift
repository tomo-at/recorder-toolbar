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
        case .area:    return "Drag to select a recording area"
        case .camOnly: return "Ready to record camera"
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

                SegmentedControlItem(icon: "rectangle.dashed", label: "Area",
                                     isActive: state.selectionMode == .area) {
                    state.toggleSelecting(.area)
                }
                .onHover { h in
                    state.showPreview(h ? .area : nil)
                    if h { state.showTooltip("Record Area", "⇧⌘8", buttonCenterX: 160) }
                    else  { state.shortcutTooltip.hide() }
                }

                SegmentedControlItem(icon: "person.crop.rectangle.fill", label: "Cam only",
                                     isActive: state.selectionMode == .camOnly) {
                    state.toggleSelecting(.camOnly)
                }
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

// ── Selection confirm panel view (V4 / V5 selectedRegion) ─────────────────

struct SelectionConfirmView: View {
    @ObservedObject var state: ToolbarState
    let onCancel: () -> Void
    let onRecord: () -> Void

    // Styles that use MicIconWithLevel (SF Symbol) instead of MicLevelBars (bar graph)
    private var usesIconMicStyle: Bool {
        let s = state.settingsPanel.state.v5DefaultStyle
        return s == .revealedAllCompact || s == .horizontal
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Camera preview — fills full width, clipped by outer cornerRadius:16
                CameraThumb(deviceId: state.activeCamId)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)

                // Controls row
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        ConfirmCameraButton(
                            devices: state.cameraDevices,
                            activeId: $state.activeCamId
                        )
                        ConfirmMicButton(
                            devices: state.micDevices,
                            activeId: $state.activeMicId,
                            usesIconStyle: usesIconMicStyle
                        )
                    }

                    Button(action: onRecord) {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 13))
                            Text("Record")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Color.accentDestructive)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.highlightPrimary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.highlightPrimary).frame(height: 1)
                }
            }

            // Overlay: Cancel (left) + Settings (right)
            HStack {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(confirmGlassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.highlightPrimary, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    guard let panel = state.panel else { return }
                    state.settingsPanel.toggle(toolbar: panel,
                                               buttonCenterX: panel.frame.midX)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(confirmGlassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.highlightPrimary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private var confirmGlassBg: some View {
    ZStack {
        Color(red: 27/255, green: 35/255, blue: 38/255).opacity(0.65)
        Color.white.opacity(0.08)
    }
}

// ── Compact camera dropdown (confirm panel) ────────────────────────────────

private struct ConfirmCameraButton: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    @State private var showMenu = false

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 4) {
                CameraThumb(deviceId: activeId)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.contentTertiary)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(showMenu ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: showMenu)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            DeviceMenuView(devices: devices, activeId: $activeId)
        }
    }
}

// ── Compact mic dropdown (confirm panel) ──────────────────────────────────

private struct ConfirmMicButton: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    let usesIconStyle: Bool
    @State private var showMenu = false
    @State private var level: Float = 0
    @State private var meterTimer: Timer? = nil

    var body: some View {
        Button { showMenu.toggle() } label: {
            HStack(spacing: 4) {
                ZStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.11), Color.white.opacity(0.07)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    if usesIconStyle {
                        MicIconWithLevel(size: 14)
                    } else {
                        MicLevelBars(level: level)
                            .frame(width: 7, height: 14)
                    }
                }
                .frame(width: 20, height: 20)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.contentTertiary)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(showMenu ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: showMenu)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            DeviceMenuView(devices: devices, activeId: $activeId)
        }
        .onAppear {
            guard !usesIconStyle else { return }
            var t: Float = 0
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                t += 0.04
                level = 0.15 + abs(sin(t)) * 0.5
            }
        }
        .onDisappear { meterTimer?.invalidate(); meterTimer = nil }
    }
}

// MARK: – Drag & resize helpers (Cam-only panels)

private struct WindowDragNSView: NSViewRepresentable {
    func makeNSView(context: Context) -> _WDView { _WDView() }
    func updateNSView(_ v: _WDView, context: Context) {}

    class _WDView: NSView {
        override func mouseDragged(with e: NSEvent) {
            guard let w = window else { return }
            let o = w.frame.origin
            w.setFrameOrigin(NSPoint(x: o.x + e.deltaX, y: o.y - e.deltaY))
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

private struct ResizeGripNSView: NSViewRepresentable {
    func makeNSView(context: Context) -> _RGView { _RGView() }
    func updateNSView(_ v: _RGView, context: Context) {}

    class _RGView: NSView {
        private var startMouse: CGPoint = .zero
        private var startFrame: CGRect = .zero

        override func mouseDown(with e: NSEvent) {
            guard let w = window else { return }
            startMouse = NSEvent.mouseLocation
            startFrame = w.frame
        }
        override func mouseDragged(with e: NSEvent) {
            guard let w = window else { return }
            let cur = NSEvent.mouseLocation
            let dx = cur.x - startMouse.x
            let dy = cur.y - startMouse.y
            var f = startFrame
            f.size.width  = max(480, f.size.width + dx)
            f.size.height = max(300, f.size.height - dy)
            f.origin.y    = startFrame.maxY - f.size.height
            w.setFrame(f, display: true)
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    }
}

private struct WindowDrag: View {
    var body: some View { WindowDragNSView() }
}

private struct ResizeGripButton: View {
    var body: some View {
        ZStack {
            ResizeGripNSView()
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .allowsHitTesting(false)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: – Cam-only: large preview + controls (selectedRegion style)

struct CamOnlyConfirmView: View {
    @ObservedObject var state: ToolbarState
    let onCancel: () -> Void
    let onRecord: () -> Void

    private var usesIconMicStyle: Bool {
        let s = state.settingsPanel.state.v5DefaultStyle
        return s == .revealedAllCompact || s == .horizontal
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                CameraThumb(deviceId: state.activeCamId)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(WindowDrag())
                ResizeGripButton().padding(8)
            }

            ZStack {
                HStack {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(height: 28)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button(action: onRecord) {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 13))
                            Text("Record")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(height: 28)
                        .padding(.horizontal, 10)
                        .background(Color.accentDestructive)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 6) {
                    ConfirmCameraButton(
                        devices: state.cameraDevices,
                        activeId: $state.activeCamId
                    )
                    ConfirmMicButton(
                        devices: state.micDevices,
                        activeId: $state.activeMicId,
                        usesIconStyle: usesIconMicStyle
                    )
                    Button {
                        guard let panel = state.panel else { return }
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.midX)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.highlightPrimary).frame(height: 1)
            }
        }
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: – Cam-only: preview only (toolbar style — controls stay in toolbar)

struct CamOnlyPreviewView: View {
    let deviceId: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CameraThumb(deviceId: deviceId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(WindowDrag())
            ResizeGripButton().padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
