import AppKit
import SwiftUI

// MARK: – Window controller

@MainActor
final class PrototypeSettingsWindowController: NSWindowController {
    private let state: SettingsState

    init(state: SettingsState) {
        self.state = state
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
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
        window.contentView = NSHostingView(
            rootView: PrototypeSettingsView(state: state, onClose: { [weak self] in self?.close() })
        )
        // .accessory アクティベーションでは既定でフォーカスを取れないので明示的にアクティブ化
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: – SwiftUI form

struct PrototypeSettingsView: View {
    @ObservedObject var state: SettingsState
    let onClose: () -> Void

    @State private var draftDefault:   SettingsState.DefaultStyle
    @State private var draftRecording: SettingsState.RecordingStyle
    @State private var draftUpload:    SettingsState.UploadStyle

    init(state: SettingsState, onClose: @escaping () -> Void) {
        self.state   = state
        self.onClose = onClose
        _draftDefault   = State(initialValue: state.v5DefaultStyle)
        _draftRecording = State(initialValue: state.v5RecordingStyle)
        _draftUpload    = State(initialValue: state.v5UploadStyle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Default style
            section(title: "Default style") {
                Picker("", selection: $draftDefault) {
                    ForEach(SettingsState.DefaultStyle.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            // Recording
            section(title: "Recording") {
                Picker("", selection: $draftRecording) {
                    ForEach(SettingsState.RecordingStyle.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            // Uploading
            section(title: "Uploading") {
                Picker("", selection: $draftUpload) {
                    ForEach(SettingsState.UploadStyle.allCases, id: \.self) { opt in
                        Text(opt.label).tag(opt)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    state.v5DefaultStyle   = draftDefault
                    state.v5RecordingStyle = draftRecording
                    state.v5UploadStyle    = draftUpload
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360, height: 360)
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
