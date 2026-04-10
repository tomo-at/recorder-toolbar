import SwiftUI
import AVFoundation

struct ToolbarView: View {
    @StateObject private var state = ToolbarState()

    var body: some View {
        Group {
            switch state.appState {
            case .typeSelect:   TypeSelectView(state: state)
            case .windowSelect: WindowSelectView(state: state)
            case .recording:    RecordingView(state: state)
            }
        }
        .frame(height: 68)
    }
}

// ── State 1: Type Select ────────────────────────────────────

struct TypeSelectView: View {
    @ObservedObject var state: ToolbarState

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
                SegmentButton(icon: "display", label: "Display") {}
                SegmentButton(icon: "macwindow", label: "Window") {
                    state.appState = .windowSelect
                }
                SegmentButton(icon: "rectangle.dashed", label: "Area") {}
                SegmentButton(icon: "video.fill", label: "Cam only") {}

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Options") {}
            }
            .padding(.horizontal, 4)
        }
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
                // Camera
                CameraSegment(devices: cameraDevices, activeId: $activeCamId)
                // Mic
                MicSegment(devices: micDevices, activeId: $activeMicId)

                ToolbarDivider()

                SegmentButton(icon: "gearshape.fill", label: "Options") {}

                ToolbarDivider()

                // Record button
                Button {
                    state.startRecording()
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
                    .background(Color(red: 0.839, green: 0.251, blue: 0.184))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
        }
        .task {
            await loadDevices()
        }
        .keyboardShortcut(.escape, modifiers: [])
        .onExitCommand { state.appState = .typeSelect }
    }

    func loadDevices() async {
        let session  = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video, position: .unspecified)
        cameraDevices = session.devices
        activeCamId   = activeCamId ?? cameraDevices.first?.uniqueID

        let micSession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio, position: .unspecified)
        micDevices  = micSession.devices
        activeMicId = activeMicId ?? micDevices.first?.uniqueID
    }
}

// ── State 3: Recording ──────────────────────────────────────

struct RecordingView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ActionButton(icon: "arrow.counterclockwise", label: "Restart") {
                    state.stopRecording()
                }
                ActionButton(icon: state.paused ? "play.fill" : "pause.fill",
                             label: state.paused ? "Resume" : "Pause") {
                    state.togglePause()
                }
                ActionButton(icon: "stop.fill", label: "Stop") {
                    state.stopRecording()
                }
            }
            .padding(.leading, 8)

            ToolbarDivider()

            VStack(alignment: .leading, spacing: 2) {
                Text(state.timeString)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.white)
                Text("1 hour limit")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.69))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// ── Shared Components ───────────────────────────────────────

struct CloseSection<Icon: View>: View {
    let action: () -> Void
    let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 44, height: 68)
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
    let icon:   String
    let label:  String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.69))
                    .lineLimit(1)
            }
            .frame(width: 64, height: 68)
            .background(hovering ? Color.white.opacity(0.08) : .clear)
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
