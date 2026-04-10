import AppKit
import SwiftUI
import AVFoundation

// MARK: - State

@MainActor
final class SettingsState: ObservableObject {
    @Published var showCursor:        Bool = true
    @Published var recordSystemAudio: Bool = true
    @Published var countdownChoice:   CountdownOption = .three
    @Published var cameraDevices:     [AVCaptureDevice] = []
    @Published var micDevices:        [AVCaptureDevice] = []
    @Published var activeCamId:       String?
    @Published var activeMicId:       String?

    enum CountdownOption: String, CaseIterable {
        case none  = "None"
        case one   = "1s"
        case three = "3s"
    }

    var activeCamLabel: String {
        cameraDevices.first { $0.uniqueID == activeCamId }?
            .localizedName.replacingOccurrences(of: " Camera", with: "")
            ?? "Camera"
    }
    var activeMicLabel: String {
        micDevices.first { $0.uniqueID == activeMicId }?.localizedName ?? "Microphone"
    }
}

// MARK: - Controller

enum SettingsSubPanelType { case camera, mic, countdown }

@MainActor
final class SettingsPanelController {
    private var mainPanel:     NSPanel?
    private var subPanel:      NSPanel?
    private var activeSubType: SettingsSubPanelType?
    private var dismissWork:   DispatchWorkItem?
    private var clickMonitor:  Any?
    private weak var toolbar:  NSPanel?

    private(set) var state = SettingsState()
    var isVisible: Bool { mainPanel != nil }

    // MARK: – Open / Close

    /// - buttonCenterX: screen x of the Settings button's center (used to align panel above it).
    func toggle(toolbar: NSPanel, buttonCenterX: CGFloat) {
        isVisible ? dismiss() : open(toolbar: toolbar, buttonCenterX: buttonCenterX)
    }

    func open(toolbar: NSPanel, buttonCenterX: CGFloat) {
        self.toolbar = toolbar
        loadDevices()

        let p = NSPanel.makeFloating(level: toolbar.level)
        let hosting = NSHostingView(rootView: SettingsPanelView(state: state, controller: self))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        p.contentView = hosting

        let w: CGFloat = 197, h: CGFloat = 211
        // Center panel above the Settings button; clamp so it stays on screen.
        let rawX = buttonCenterX - w / 2
        let screenMinX = NSScreen.main?.frame.minX ?? 0
        let screenMaxX = NSScreen.main?.frame.maxX ?? 2000
        let x = max(screenMinX + 4, min(rawX, screenMaxX - w - 4))
        let y = toolbar.frame.maxY + 8
        p.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)

        p.fadeIn(); mainPanel = p
        toolbar.orderFrontRegardless()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.dismiss() } }
    }

    func dismiss() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        dismissSubImmediate()
        mainPanel?.fadeOut(); mainPanel = nil
    }

    // MARK: – Sub-panels

    func showSub(_ type: SettingsSubPanelType) {
        cancelDismissWork()
        guard activeSubType != type else { return }
        dismissSubImmediate()
        activeSubType = type
        guard let main = mainPanel, let tb = toolbar else { return }

        let sub = NSPanel.makeFloating(level: tb.level)
        let hosting: NSHostingView<AnyView>
        let subW: CGFloat
        let rows: Int

        switch type {
        case .camera:
            hosting = NSHostingView(rootView: AnyView(DeviceSubPanelView(
                devices: state.cameraDevices,
                activeId: Binding(get: { [weak self] in self?.state.activeCamId ?? nil },
                                  set: { [weak self] in self?.state.activeCamId = $0 }),
                controller: self)))
            subW = 197; rows = max(1, state.cameraDevices.count)
        case .mic:
            hosting = NSHostingView(rootView: AnyView(DeviceSubPanelView(
                devices: state.micDevices,
                activeId: Binding(get: { [weak self] in self?.state.activeMicId ?? nil },
                                  set: { [weak self] in self?.state.activeMicId = $0 }),
                controller: self)))
            subW = 197; rows = max(1, state.micDevices.count)
        case .countdown:
            hosting = NSHostingView(rootView: AnyView(CountdownSubPanelView(
                choice: Binding(get: { [weak self] in self?.state.countdownChoice ?? .three },
                                set: { [weak self] in self?.state.countdownChoice = $0 }),
                controller: self)))
            subW = 130; rows = 3
        }

        sub.contentView = hosting
        let subH = CGFloat(rows) * 28 + 16
        let x = main.frame.maxX + 6
        let y = main.frame.maxY - subH
        sub.setFrame(NSRect(x: x, y: y, width: subW, height: subH), display: false)

        sub.fadeIn(); subPanel = sub
        main.orderFrontRegardless()
    }

    func keepSub()           { cancelDismissWork() }

    func scheduleDismissSub() {
        let work = DispatchWorkItem { [weak self] in self?.dismissSubFade() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func cancelDismissWork()  { dismissWork?.cancel(); dismissWork = nil }

    private func dismissSubImmediate() {
        cancelDismissWork()
        subPanel?.orderOut(nil); subPanel = nil; activeSubType = nil
    }

    private func dismissSubFade() {
        activeSubType = nil; subPanel?.fadeOut(); subPanel = nil
    }

    // MARK: – Helpers

    private func loadDevices() {
        state.cameraDevices = AVCaptureDevice.cameraDevices()
        if state.activeCamId == nil { state.activeCamId = state.cameraDevices.first?.uniqueID }
        state.micDevices = AVCaptureDevice.micDevices()
        if state.activeMicId == nil { state.activeMicId = state.micDevices.first?.uniqueID }
    }
}

// MARK: - Shared visual components

private struct MenuBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.22, green: 0.22, blue: 0.22))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}

private struct SettingsMenuItem: View {
    let icon:       String?
    let label:      String
    var hasChevron: Bool = false
    let onHover:    (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12)).foregroundColor(.white)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)

            Text(label)
                .font(.system(size: 12)).foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(hovering ? Color.white.opacity(0.08) : .clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { h in hovering = h; onHover(h) }
    }
}

// MARK: - Main settings view

struct SettingsPanelView: View {
    @ObservedObject var state: SettingsState
    let controller: SettingsPanelController

    var body: some View {
        VStack(spacing: 0) {
            SettingsMenuItem(icon: "video.fill", label: state.activeCamLabel, hasChevron: true) { h in
                if h { controller.showSub(.camera) } else { controller.scheduleDismissSub() }
            }
            SettingsMenuItem(icon: "mic.fill", label: state.activeMicLabel, hasChevron: true) { h in
                if h { controller.showSub(.mic) } else { controller.scheduleDismissSub() }
            }
            MenuDivider()
            SettingsMenuItem(icon: "timer", label: "Count down", hasChevron: true) { h in
                if h { controller.showSub(.countdown) } else { controller.scheduleDismissSub() }
            }
            MenuDivider()
            SettingsMenuItem(icon: state.showCursor ? "checkmark" : nil,
                             label: "Show cursor") { _ in }
                .onTapGesture { state.showCursor.toggle() }
            SettingsMenuItem(icon: state.recordSystemAudio ? "checkmark" : nil,
                             label: "Record system audio") { _ in }
                .onTapGesture { state.recordSystemAudio.toggle() }
            MenuDivider()
            SettingsMenuItem(icon: "person.circle.fill", label: "Account",
                             hasChevron: true) { _ in }
        }
        .padding(8)
        .background(MenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(width: 197)
    }
}

// MARK: - Device sub-panel

struct DeviceSubPanelView: View {
    let devices:  [AVCaptureDevice]
    @Binding var activeId: String?
    let controller: SettingsPanelController

    var body: some View {
        VStack(spacing: 0) {
            ForEach(devices, id: \.uniqueID) { device in
                SettingsMenuItem(
                    icon: device.uniqueID == activeId ? "checkmark" : nil,
                    label: device.localizedName
                ) { _ in }
                .onTapGesture { activeId = device.uniqueID }
            }
        }
        .padding(8)
        .background(MenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Shadow is provided by NSPanel.hasShadow — no SwiftUI shadow needed.
        .onHover { h in h ? controller.keepSub() : controller.scheduleDismissSub() }
    }
}

// MARK: - Countdown sub-panel

struct CountdownSubPanelView: View {
    @Binding var choice: SettingsState.CountdownOption
    let controller: SettingsPanelController

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SettingsState.CountdownOption.allCases, id: \.self) { option in
                SettingsMenuItem(
                    icon: choice == option ? "checkmark" : nil,
                    label: option.rawValue
                ) { _ in }
                .onTapGesture { choice = option }
            }
        }
        .padding(8)
        .background(MenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Shadow is provided by NSPanel.hasShadow — no SwiftUI shadow needed.
        .onHover { h in h ? controller.keepSub() : controller.scheduleDismissSub() }
    }
}
