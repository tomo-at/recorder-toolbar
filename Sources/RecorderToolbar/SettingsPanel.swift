import AppKit
import SwiftUI
import AVFoundation

// MARK: - State

@MainActor
final class SettingsState: ObservableObject {
    @Published var showCursor:        Bool = true
    @Published var recordSystemAudio: Bool = true
    @Published var countdownChoice:   CountdownOption = .three   // Used by ToolbarState
    @Published var themeChoice:       ThemeOption = .auto
    @Published var protoVersion:      ProtoVersion = .v4

    enum CountdownOption: String, CaseIterable {
        case none  = "None"
        case one   = "1s"
        case three = "3s"
    }

    enum ThemeOption: String, CaseIterable {
        case auto  = "Auto"
        case light = "Light"
        case dark  = "Dark"
    }

    enum ProtoVersion: String, CaseIterable {
        case v1 = "V1"
        case v2 = "V2"
        case v3 = "V3"
        case v4 = "V4"
    }
}

// MARK: - Controller

enum SettingsSubPanelType { case theme, prototype }

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

    func toggle(toolbar: NSPanel, buttonCenterX: CGFloat) {
        isVisible ? dismiss() : open(toolbar: toolbar, buttonCenterX: buttonCenterX)
    }

    func open(toolbar: NSPanel, buttonCenterX: CGFloat) {
        self.toolbar = toolbar

        let p = NSPanel.makeFloating(level: toolbar.level)
        let hosting = NSHostingView(rootView: SettingsPanelView(state: state, controller: self))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        p.contentView = hosting

        let w: CGFloat = 257, h: CGFloat = 350
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
        let subW: CGFloat = 130
        let rows: Int

        switch type {
        case .theme:
            let hosting = NSHostingView(rootView: AnyView(ThemeSubPanelView(
                choice: Binding(get: { [weak self] in self?.state.themeChoice ?? .auto },
                                set: { [weak self] in self?.state.themeChoice = $0 }),
                controller: self)))
            sub.contentView = hosting
            rows = SettingsState.ThemeOption.allCases.count
        case .prototype:
            let hosting = NSHostingView(rootView: AnyView(PrototypeSubPanelView(
                choice: Binding(get: { [weak self] in self?.state.protoVersion ?? .v4 },
                                set: { [weak self] in self?.state.protoVersion = $0 }),
                controller: self)))
            sub.contentView = hosting
            rows = SettingsState.ProtoVersion.allCases.count
        }

        let subH = CGFloat(rows) * 28 + 16
        let x = main.frame.maxX + 6
        // Align sub-panel top with the relevant row.
        // Row offsets from panel top:
        //   Theme:     8+28+9+28+28+9+28+28+9 = 175 px
        //   Prototype: 175+28(theme)+9(div)+28+28(cursor/audio)+9(div) = 277 px
        let rowTopOffset: CGFloat
        switch type {
        case .theme:     rowTopOffset = 175
        case .prototype: rowTopOffset = 277
        }
        let y = main.frame.maxY - rowTopOffset - subH
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

private enum MenuItemRightIcon {
    case none, chevron, externalLink
}

private struct SettingsMenuItem: View {
    let icon:      String?
    let label:     String
    var rightIcon: MenuItemRightIcon = .none
    let onHover:   (Bool) -> Void
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
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch rightIcon {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 16, height: 16)
            case .externalLink:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
                    .frame(width: 16, height: 16)
            case .none:
                EmptyView()
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

// MARK: - User profile row

private struct UserProfileRow: View {
    let onSignOut: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(Color(white: 0.65))
                .frame(width: 16, height: 16)

            Text("Tyler Reynolds")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSignOut) {
                Text("Sign out")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 1.0, green: 0.427, blue: 0.298))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(hovering ? Color.white.opacity(0.08) : .clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onHover { h in hovering = h }
    }
}

// MARK: - Main settings view

struct SettingsPanelView: View {
    @ObservedObject var state: SettingsState
    let controller: SettingsPanelController

    var body: some View {
        VStack(spacing: 0) {
            UserProfileRow { controller.dismiss() }

            MenuDivider()

            SettingsMenuItem(icon: nil, label: "All videos",
                             rightIcon: .externalLink) { _ in }
                .onTapGesture { controller.dismiss() }
            SettingsMenuItem(icon: nil, label: "Account settings",
                             rightIcon: .externalLink) { _ in }
                .onTapGesture { controller.dismiss() }

            MenuDivider()

            SettingsMenuItem(icon: nil, label: "Watch demo",
                             rightIcon: .externalLink) { _ in }
                .onTapGesture { controller.dismiss() }
            SettingsMenuItem(icon: nil, label: "Keyboard shortcuts...") { _ in }

            MenuDivider()

            SettingsMenuItem(icon: nil, label: "Theme",
                             rightIcon: .chevron) { h in
                if h { controller.showSub(.theme) } else { controller.scheduleDismissSub() }
            }

            MenuDivider()

            SettingsMenuItem(icon: state.showCursor ? "checkmark" : nil,
                             label: "Show cursor") { _ in }
                .onTapGesture { state.showCursor.toggle() }
            SettingsMenuItem(icon: state.recordSystemAudio ? "checkmark" : nil,
                             label: "Record system audio") { _ in }
                .onTapGesture { state.recordSystemAudio.toggle() }

            MenuDivider()

            SettingsMenuItem(icon: nil, label: "Prototype",
                             rightIcon: .chevron) { h in
                if h { controller.showSub(.prototype) } else { controller.scheduleDismissSub() }
            }

            MenuDivider()

            SettingsMenuItem(icon: nil, label: "Quit Airtime") { _ in }
                .onTapGesture { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .background(MenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(width: 257)
    }
}

// MARK: - Prototype sub-panel

struct PrototypeSubPanelView: View {
    @Binding var choice: SettingsState.ProtoVersion
    let controller: SettingsPanelController

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SettingsState.ProtoVersion.allCases, id: \.self) { version in
                SettingsMenuItem(
                    icon: choice == version ? "checkmark" : nil,
                    label: version.rawValue
                ) { _ in }
                .onTapGesture { choice = version }
            }
        }
        .padding(8)
        .background(MenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onHover { h in h ? controller.keepSub() : controller.scheduleDismissSub() }
    }
}

// MARK: - Theme sub-panel

struct ThemeSubPanelView: View {
    @Binding var choice: SettingsState.ThemeOption
    let controller: SettingsPanelController

    var body: some View {
        VStack(spacing: 0) {
            ForEach(SettingsState.ThemeOption.allCases, id: \.self) { option in
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
        .onHover { h in h ? controller.keepSub() : controller.scheduleDismissSub() }
    }
}
