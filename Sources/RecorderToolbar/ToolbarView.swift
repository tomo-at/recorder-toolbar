import SwiftUI
import AVFoundation

struct ToolbarView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        Group {
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
        .frame(height: 66)
    }
}

// MARK: – V5: 3軸組み合わせディスパッチ
//
// Default style    : Step by step (V1) / Revealed all (V2) / Message (V4-style header)
// Recording style  : Toolbar (V1/V2 風 select→record トールバー) / Selected region (V4 風 confirm panel)
// Upload style     : Toolbar (進捗バー + Settings/All-videos バッジ) / Menu bar + Notification (V2 風)
//
// Q1: Message default + Toolbar recording → 選択後の WindowSelect/Recording にも message bar を被せる
// Q2: Selected region は録画 UI 自体も V4 風（ヘッダー付き）
// Q7: Toolbar upload の進捗バーは 2px、message bar の下（= ボタン領域の最上端に重なる）

/// V5 typeSelect: defaultStyle に従って既存 V1/V2/V4 の typeSelect を再利用し、
/// uploadStyle == .toolbar 中はその top に 2px 進捗バーを overlay する。
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
            case .stepByStep:  TypeSelectView(state: state)
            case .revealedAll: TypeSelectViewV2(state: state)
            case .message:     TypeSelectViewV4(state: state)
            }
        }
        .overlay(alignment: .top) {
            // Message bar(16px)がある場合のみその下に進捗バーを置く
            if settings.v5UploadStyle == .toolbar, state.isUploading {
                V5UploadProgressBar(progress: state.uploadProgress)
                    .padding(.top, settings.v5DefaultStyle == .message ? 16 : 0)
            }
        }
    }
}

/// V5 windowSelect/displaySelect:
/// - recording == .selectedRegion → typeSelect のまま（V4 流: confirm panel が region 横に出る）
/// - recording == .toolbar → V1/V2 風 WindowSelectView を表示。message default なら header を被せる
struct V5WindowSelect: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }
    var body: some View {
        switch settings.v5RecordingStyle {
        case .selectedRegion:
            V5TypeSelect(state: state)
        case .toolbar:
            V5MaybeHeadered(state: state, message: "Click Record when you're ready") {
                WindowSelectView(state: state)
            }
        }
    }
}

/// V5 countdown / recording: メッセージバーの有無は **DefaultStyle == .message** のときのみ。
/// RecordingStyle は問わない（Selected region でも Step by step ならヘッダー無し）。
struct V5Countdown: View {
    @ObservedObject var state: ToolbarState
    init(state: ToolbarState) { self.state = state }
    var body: some View {
        V5MaybeHeadered(state: state, message: "Starting in \(state.countdownSeconds)...") {
            CountdownToolbarView(state: state)
        }
    }
}

struct V5Recording: View {
    @ObservedObject var state: ToolbarState
    init(state: ToolbarState) { self.state = state }
    var body: some View {
        V5MaybeHeadered(state: state, message: "Recording in progress") {
            RecordingView(state: state)
        }
    }
}

/// V5 で Message default のときだけ ToolbarHeader を上に被せる小ヘルパー。
/// Toolbar 全高は 66px に維持されるため、内側の content 部分は 50px に圧縮される。
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

/// V5 用の細い (2px) 進捗バー。色味は既存 UploadProgressBarView と同じ。
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

// ── State 1: Type Select ────────────────────────────────────

struct TypeSelectView: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    @State private var activeCamId: String?

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        HStack(spacing: 0) {
            // Segment strip
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

                CamOnlySegment(activeId: activeCamId) { h in
                    guard let panel = state.panel else { return }
                    if h, let id = activeCamId {
                        state.showCameraPreview(deviceId: id, above: panel)
                    } else {
                        state.hideCameraPreview()
                    }
                }

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Settings",
                              showBadge: settings.settingsBadge) {
                    // Settings button center x from toolbar left = 8(pad) + 64×4(segs) + 9(div) + 32(half btn) = 305
                    settings.settingsBadge = false
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 305)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .overlay(alignment: .top) {
            if state.isUploading {
                UploadProgressBarView(progress: state.uploadProgress)
            }
        }
        .task { await loadCameraDevice() }
    }

    private func loadCameraDevice() async {
        activeCamId = AVCaptureDevice.cameraDevices().first?.uniqueID
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
    let icon:        String
    let label:       String
    var iconColor:   Color = .white
    var isActive:    Bool  = false
    var isDisabled:  Bool  = false
    var showBadge:   Bool  = false
    var badgeColor:  Color = .modelessTeal
    let action:      () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
                    .frame(width: 20, height: 20)
                    .overlay(alignment: .topTrailing) {
                        if showBadge {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 6, height: 6)
                                .offset(x: 3, y: -1)
                        }
                    }
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.69))
                    .lineLimit(1)
            }
            .frame(width: 64, height: 48)
            .background(isActive ? Color.white.opacity(0.16) : (hovering && !isDisabled ? Color.white.opacity(0.08) : .clear))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
    }
}

// MARK: – Upload progress bar (V1)

/// 4px progress bar shown above the toolbar during uploads.
/// Track: modeless-black-24, fill: modeless-teal (airtime design system).
struct UploadProgressBarView: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.modelessBlack24)
                Rectangle().fill(Color.modelessTeal)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
            }
        }
        .frame(height: 4)
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
// Layout (506px): [Display|Window|Area|CamOnly(256)+8] [div(9)] [Cam+Mic(136)+8] [div(9)] [Settings(64)] + outer pad(8×2)

struct TypeSelectViewV2: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    @State private var cameraDevices: [AVCaptureDevice] = []
    @State private var micDevices:    [AVCaptureDevice] = []
    @State private var activeCamId:   String?           = nil
    @State private var activeMicId:   String?           = nil

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                // Recording type selector
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

                // Settings — center X from toolbar left: 8+264+9+144+9+32 = 466
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
        .task { await loadDevices() }
    }

    private func loadDevices() async {
        cameraDevices = AVCaptureDevice.cameraDevices()
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID
        micDevices    = AVCaptureDevice.micDevices()
        activeMicId   = activeMicId ?? micDevices.first?.uniqueID
    }
}

// ── V3: Segmented Control type selector ────────────────────
// Layout (510px): [SegmentedCtrl(260)+8] [div(9)] [Cam+Mic(136)+8] [div(9)] [Settings(64)] + outer pad(8×2)

/// Single item inside the segmented control container.
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
                    .foregroundColor(isActive ? .white : Color(white: 0.69))
                    .lineLimit(1)
            }
            .frame(width: 64, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)   // inner radius = outer(10) - padding(2)
                    .fill(isActive  ? Color.white.opacity(0.16)
                          : hovering ? Color.white.opacity(0.08)
                          : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct TypeSelectViewV3: View {
    @ObservedObject var state: ToolbarState
    @State private var cameraDevices: [AVCaptureDevice] = []
    @State private var micDevices:    [AVCaptureDevice] = []
    @State private var activeCamId:   String?           = nil
    @State private var activeMicId:   String?           = nil

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                // Segmented control container
                // inner: 4×64=256px, padding 2 each side → 260px wide, 44+4=48px tall
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

                    SegmentedControlItem(icon: "rectangle.dashed", label: "Area") {}
                        .onHover { h in
                            state.showPreview(h ? .area : nil)
                            if h { state.showTooltip("Record Area", "⇧⌘8", buttonCenterX: 170) }
                            else  { state.shortcutTooltip.hide() }
                        }

                    SegmentedControlItem(icon: "person.crop.rectangle.fill",
                                         label: "Cam only") {}
                        .onHover { h in
                            guard let panel = state.panel else { return }
                            if h, let id = activeCamId {
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

                // Camera + Mic (always visible)
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

                // Settings — center X from toolbar left: 8+260+8+9+144+9+32 = 470
                SegmentButton(icon: "gearshape.fill", label: "Settings") {
                    if let panel = state.panel {
                        state.settingsPanel.toggle(toolbar: panel,
                                                   buttonCenterX: panel.frame.minX + 470)
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
}

// ── V4: Message header bar ─────────────────────────────────
// Header: 16px dark band with contextual message.
// Controls: same as V3 but without X button and no outer side padding.
// Total height: 66px (16 header + 50 controls).

/// Thin header bar shown above toolbar controls in V4.
struct ToolbarHeader: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.60))
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .background(Color.black.opacity(0.24))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
            }
    }
}

// Layout (482px): [SegItems(4×64=256)] [div(9)] [Cam+Mic+trail(144)] [div(9)] [Settings(64)]
struct TypeSelectViewV4: View {
    @ObservedObject var state: ToolbarState
    @ObservedObject var settings: SettingsState
    @State private var cameraDevices: [AVCaptureDevice] = []
    @State private var micDevices:    [AVCaptureDevice] = []
    @State private var activeCamId:   String?           = nil
    @State private var activeMicId:   String?           = nil

    init(state: ToolbarState) {
        self.state    = state
        self.settings = state.settingsPanel.state
    }

    var headerMessage: String {
        // After freeze (confirmed selection): wait-for-record prompt.
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
                // Type selector: 4 items × 64px = 256px (no wrapper background)
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
                        if h, let id = activeCamId {
                            state.showCameraPreview(deviceId: id, above: panel)
                        } else {
                            state.hideCameraPreview()
                        }
                    }

                ToolbarDivider()

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

                // Settings — center X from toolbar left: 256+9+144+9+32 = 450
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
        .task { await loadDevices() }
    }

    private func loadDevices() async {
        cameraDevices = AVCaptureDevice.cameraDevices()
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID
        micDevices    = AVCaptureDevice.micDevices()
        activeMicId   = activeMicId ?? micDevices.first?.uniqueID
    }
}

// Layout (346px): [Cam+Mic+trail(144)] [div(9)] [Settings(64)] [div(9)] [lead(8)+Record+trail(16)]
struct WindowSelectViewV4: View {
    @ObservedObject var state: ToolbarState
    @State private var cameraDevices: [AVCaptureDevice] = []
    @State private var micDevices:    [AVCaptureDevice] = []
    @State private var activeCamId:   String?           = nil
    @State private var activeMicId:   String?           = nil

    var body: some View {
        VStack(spacing: 0) {
            ToolbarHeader(message: "Click Record when you're ready")

            HStack(spacing: 0) {
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

                // Settings — center X from toolbar left: 144+9+32 = 185
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
        .task { await loadDevices() }
    }

    func loadDevices() async {
        cameraDevices = AVCaptureDevice.cameraDevices()
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID
        micDevices    = AVCaptureDevice.micDevices()
        activeMicId   = activeMicId ?? micDevices.first?.uniqueID
    }
}

/// Layout (297px): same as RecordingViewV4 but Pause/Stop disabled, time shows countdown
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

// Layout (297px): header + [Restart|Pause|Stop] [div] [time display] with outer pad 8
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
// Shown at the bottom-left of the selected window/display after freeze().
// Contains a live camera preview + Cancel and Record buttons.

struct SelectionConfirmView: View {
    let onCancel: () -> Void
    let onRecord: () -> Void
    @State private var cameraDeviceId: String? = nil
    @State private var cancelHovering = false

    // Figma: background/secondary = #12181a
    private let panelBg = Color(red: 18/255.0, green: 24/255.0, blue: 26/255.0)

    var body: some View {
        VStack(spacing: 0) {
            // ── Camera preview: 172×172 px, full width, square ──
            Group {
                if let id = cameraDeviceId {
                    CameraThumb(deviceId: id)
                } else {
                    Color.black
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 172)
            // Bottom separator between preview and controls
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            // ── Controls: padding 8px all sides, gap 8px, height 44px ──
            HStack(spacing: 8) {
                // Cancel: 56×28 px, transparent background
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 28)
                        .background(cancelHovering ? Color.white.opacity(0.08) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { cancelHovering = $0 }

                // Record: flex-1 × 28px, #d6402f = Color.recordRed
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
        // Solid panel background #12181a, 12 px corner radius
        .background(panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task {
            cameraDeviceId = AVCaptureDevice.cameraDevices().first?.uniqueID
        }
    }
}

// ── Shortcut tooltip view (shown above type-select buttons) ──

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

