import AppKit
import SwiftUI

// MARK: – Window controller

@MainActor
final class PrototypeSettingsWindowController: NSWindowController {
    private let state: SettingsState
    private weak var toolbarState: ToolbarState?
    private var contentViewConfigured = false

    init(state: SettingsState, toolbarState: ToolbarState?) {
        self.state        = state
        self.toolbarState = toolbarState
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Prototype Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        // Set contentView only once so @State draft values survive close/reopen cycles
        if !contentViewConfigured {
            window.contentView = NSHostingView(
                rootView: PrototypeSettingsView(
                    state: state,
                    toolbarState: toolbarState,
                    onClose: { [weak self] in self?.close() }
                )
            )
            contentViewConfigured = true
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: – Custom radio row with preview button

private struct RadioPreviewRow<T: Hashable>: View {
    let option:    T
    let label:     String
    @Binding var selection: T
    var warningHelp: String? = nil
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button { selection = option } label: {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                        if selection == option {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if let help = warningHelp {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.yellow)
                    .frame(width: 24, height: 24)
                    .help(help)
            }

            Button(action: onPreview) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Preview this option")
        }
        .frame(minHeight: 22)
    }
}

// MARK: – SwiftUI form

struct PrototypeSettingsView: View {
    @ObservedObject var state: SettingsState
    weak var toolbarState: ToolbarState?
    let onClose: () -> Void

    @State private var draftDefault:          SettingsState.DefaultStyle
    @State private var draftRecording:        SettingsState.RecordingStyle
    @State private var draftUpload:           SettingsState.UploadStyle
    @State private var draftAddWindowPattern: SettingsState.AddWindowPattern

    init(state: SettingsState, toolbarState: ToolbarState?, onClose: @escaping () -> Void) {
        self.state        = state
        self.toolbarState = toolbarState
        self.onClose      = onClose
        _draftDefault          = State(initialValue: state.v5DefaultStyle)
        _draftRecording        = State(initialValue: state.v5RecordingStyle)
        _draftUpload           = State(initialValue: state.v5UploadStyle)
        _draftAddWindowPattern = State(initialValue: state.addWindowPattern)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Default style
            section(title: "Default style") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsState.DefaultStyle.allCases, id: \.self) { opt in
                        RadioPreviewRow(
                            option: opt,
                            label: opt.label,
                            selection: $draftDefault,
                            onPreview: {
                                onClose()
                                toolbarState?.previewDefaultStyle(opt)
                            }
                        )
                    }
                }
            }

            Divider()

            // Recording
            section(title: "Recording") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsState.RecordingStyle.allCases, id: \.self) { opt in
                        RadioPreviewRow(
                            option: opt,
                            label: opt.label,
                            selection: $draftRecording,
                            onPreview: {
                                onClose()
                                toolbarState?.previewRecordingStyle(opt)
                            }
                        )
                    }
                }
            }

            Divider()

            // Uploading
            section(title: "Uploading") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsState.UploadStyle.allCases, id: \.self) { opt in
                        RadioPreviewRow(
                            option: opt,
                            label: opt.label,
                            selection: $draftUpload,
                            onPreview: {
                                onClose()
                                toolbarState?.previewUploadStyle(opt)
                            }
                        )
                    }
                }
            }

            Divider()

            // Add window
            section(title: "Add window") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsState.AddWindowPattern.allCases, id: \.self) { opt in
                        RadioPreviewRow(
                            option: opt,
                            label: opt.label,
                            selection: $draftAddWindowPattern,
                            onPreview: {
                                onClose()
                                toolbarState?.previewAddWindowPattern(opt)
                            }
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    state.v5DefaultStyle    = draftDefault
                    state.v5RecordingStyle  = draftRecording
                    state.v5UploadStyle     = draftUpload
                    state.addWindowPattern  = draftAddWindowPattern
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 680)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            content()
        }
    }
}
