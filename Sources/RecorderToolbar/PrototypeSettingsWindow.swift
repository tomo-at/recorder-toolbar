import AppKit
import SwiftUI

// MARK: – Instant tooltip (zero-delay, NSPanel-backed)

/// NSView that shows a floating tooltip panel immediately on mouseEntered.
private final class InstantTooltipNSView: NSView {
    var label: String = ""
    private var tooltipPanel: NSPanel?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { showPanel() }
    override func mouseExited(with event: NSEvent)  { hidePanel() }

    private func showPanel() {
        hidePanel()
        let tf = NSTextField(labelWithString: label)
        tf.font = .systemFont(ofSize: 11)
        tf.textColor = .labelColor
        tf.sizeToFit()

        let hPad: CGFloat = 7, vPad: CGFloat = 3
        let size = CGSize(width: tf.frame.width + hPad * 2,
                          height: tf.frame.height + vPad * 2)
        guard let screenRect = window?.convertToScreen(convert(bounds, to: nil)) else { return }

        let p = NSPanel(contentRect: .init(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: 200) // kCGHelpWindowLevel
        p.backgroundColor = .windowBackgroundColor
        p.isOpaque = true
        p.hasShadow = true
        tf.frame = NSRect(x: hPad, y: vPad, width: tf.frame.width, height: tf.frame.height)
        p.contentView?.addSubview(tf)
        p.setFrameOrigin(NSPoint(x: screenRect.midX - size.width / 2,
                                 y: screenRect.maxY + 4))
        p.orderFrontRegardless()
        tooltipPanel = p
    }

    private func hidePanel() { tooltipPanel?.orderOut(nil); tooltipPanel = nil }
}

private struct InstantTooltip: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> InstantTooltipNSView {
        let v = InstantTooltipNSView(); v.label = text; return v
    }
    func updateNSView(_ v: InstantTooltipNSView, context: Context) { v.label = text }
}

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
            .background(InstantTooltip(text: "Quick build"))
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
