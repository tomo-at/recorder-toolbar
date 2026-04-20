import AppKit
import SwiftUI
import Combine
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var panel: NSPanel!
    let state = ToolbarState()
    var statusItem: NSStatusItem?

    private var cancellables: Set<AnyCancellable> = []
    private var uploadHostingView: NSHostingView<MenuBarUploadArcView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: ToolbarView(state: state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Ensure transparent corners so the panel shadow follows the rounded content shape.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel             = true
        panel.level                       = .floating
        panel.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor             = .clear
        panel.isOpaque                    = false
        panel.hasShadow                   = true
        panel.isMovableByWindowBackground = true
        panel.appearance = NSAppearance(named: .darkAqua)

        // Visual effect (vibrancy)
        let vfx = NSVisualEffectView()
        vfx.blendingMode       = .behindWindow
        vfx.material           = .underWindowBackground
        vfx.state              = .active
        vfx.wantsLayer         = true
        vfx.layer?.cornerRadius    = 10
        vfx.layer?.masksToBounds   = true

        vfx.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])

        panel.contentView = vfx
        panel.setContentSize(CGSize(width: 506, height: 56))

        // Position: horizontally centered, near bottom of screen
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let x  = screen.visibleFrame.minX + (sw - 506) / 2
            let y  = screen.visibleFrame.minY + 42
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        panel.invalidateShadow()   // recompute shadow from rounded content alpha

        // Give ToolbarState a reference to the panel for overlay positioning
        state.panel = panel

        setupMenuBar()
        observeUploadState()
        requestNotificationPermission()
        state.settingsPanel.openPrototypeSettings()

        let s = state.settingsPanel.state
        if s.v5RecordingStyle == .selectToStart {
            state.autoStartWithFrontmostWindow()
        }
    }

    // MARK: – Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button, let img = loadMenuBarIcon() {
            img.isTemplate = true
            button.image = img
        }

        statusItem?.menu = buildMenu()
    }

    private func loadMenuBarIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "icon-menu", withExtension: "png"),
           let img = NSImage(contentsOf: url) { return img }
        return nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // ── Airtime Tools ──────────────────────────────
        menu.addItem(sectionHeader("Airtime Tools"))

        for name in ["Camera", "Creator", "Recorder", "Stacks"] {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "square.fill", accessibilityDescription: name)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // ── Recorder ───────────────────────────────────
        menu.addItem(sectionHeader("Recorder"))

        let recordingItems: [(String, String)] = [
            ("New Recording", "2"),
            ("Record Screen", "6"),
            ("Record Window", "7"),
            ("Record Area",   "8"),
        ]
        for (title, key) in recordingItems {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.shift, .command]
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // ── Settings ───────────────────────────────────
        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        menu.addItem(settings)

        menu.addItem(.separator())

        // ── Quit ───────────────────────────────────────
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.image = NSImage(systemSymbolName: "xmark.square", accessibilityDescription: "Quit")
        menu.addItem(quit)

        return menu
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: – Upload state observation

    /// メニューバーで完了演出するのは V2、または V5 + uploadStyle == .menuBarNotification のときだけ。
    /// V1 / V5(toolbar) はツールバー側の進捗バーで完了を示すため、メニューバー側は触らない。
    private func observeUploadState() {
        state.$isUploading
            .dropFirst()                        // 初期値 false は無視
            .receive(on: DispatchQueue.main)    // RunLoop モード依存を避けるため DispatchQueue に変更
            .sink { [weak self] uploading in
                guard let self else { return }
                let s = self.state.settingsPanel.state
                let usesMenuBar = s.protoVersion == .v2
                    || (s.protoVersion == .v5 && s.v5UploadStyle == .menuBarNotification)
                NSLog("[Upload] isUploading=\(uploading) usesMenuBar=\(usesMenuBar) style=\(s.v5UploadStyle.rawValue)")
                guard usesMenuBar else { return }
                if uploading {
                    self.startUploadIndicator()
                } else {
                    self.stopUploadIndicator()
                    self.statusItem?.button?.image = self.makeCheckmarkImage()
                    self.sendUploadCompleteNotification()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.restoreOriginalIcon()
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// アップロード中の進捗円弧を表示。NSStatusItem.button に
    /// SwiftUI ベースの MenuBarUploadArcView を NSHostingView でぶら下げる。
    /// 円弧は state.uploadProgress(0.0–1.0) に追従して時計回りに塗りが進む。
    private func startUploadIndicator() {
        guard let button = statusItem?.button, uploadHostingView == nil else { return }
        button.image = nil

        let hosting = NSHostingView(rootView: MenuBarUploadArcView(state: state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hosting.widthAnchor.constraint(equalToConstant: 18),
            hosting.heightAnchor.constraint(equalToConstant: 18),
        ])
        uploadHostingView = hosting
    }

    private func stopUploadIndicator() {
        uploadHostingView?.removeFromSuperview()
        uploadHostingView = nil
    }

    private func restoreOriginalIcon() {
        if let img = loadMenuBarIcon() {
            img.isTemplate = true
            statusItem?.button?.image = img
        }
    }

    private func makeCheckmarkImage() -> NSImage? {
        // pointSize で明示的にサイズ指定しないと checkmark が見えないほど小さくなる。
        // paletteColors は [circle fill, checkmark] の順で 2 色必要。
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemTeal, .white]))
        guard let img = NSImage(systemSymbolName: "checkmark.circle.fill",
                                accessibilityDescription: "Upload complete")?
                        .withSymbolConfiguration(config) else { return nil }
        img.isTemplate = false   // カラーをそのまま表示（template にするとモノクロになる）
        return img
    }

    // MARK: – Notifications

    private func requestNotificationPermission() {
        let bundleID = Bundle.main.bundleIdentifier ?? "(nil)"
        // アプリ前面時もバナー表示させるため delegate を設定
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error {
                        NSLog("[Notification] Auth error: \(error.localizedDescription)")
                    }
                    NSLog("[Notification] Auth granted: \(granted)")
                }
            case .denied:
                NSLog("[Notification] Denied for \(bundleID). Enable in System Settings → Notifications.")
            case .authorized, .provisional, .ephemeral:
                NSLog("[Notification] Authorized for \(bundleID).")
            @unknown default:
                break
            }
        }
    }

    // アプリがアクティブな状態でも通知バナーを表示する
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func sendUploadCompleteNotification() {
        let bundleID = Bundle.main.bundleIdentifier ?? "(nil)"
        NSLog("[Notification] Sending notification for bundleID: \(bundleID)")
        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body  = "Your recording is ready to share."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[Notification] Add error: \(error.localizedDescription)")
            } else {
                NSLog("[Notification] Scheduled successfully")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}

// MARK: – Menu bar upload arc (V2)

/// メニューバー上で時計回りに塗りが進む円弧。
/// state.uploadProgress(0.0–1.0) を観測してリアルタイム描画。
/// 12時方向（top）から開始し、完了で full circle。
struct MenuBarUploadArcView: View {
    @ObservedObject var state: ToolbarState

    var body: some View {
        ZStack {
            // 進捗トラック（薄いベース円）
            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 2)
            // 進捗の塗り（時計回り、12時開始）
            Circle()
                .trim(from: 0, to: state.uploadProgress)
                .stroke(Color.primary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: state.uploadProgress)
        }
        .padding(2)
        .frame(width: 18, height: 18)
    }
}
