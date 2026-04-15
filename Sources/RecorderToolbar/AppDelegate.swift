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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: ToolbarView(state: state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Ensure transparent corners so the panel shadow follows the rounded content shape.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        panel = NSPanel(
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
        panel.setContentSize(CGSize(width: 482, height: 66))

        // Position: horizontally centered, near bottom of screen
        if let screen = NSScreen.main {
            let sw = screen.visibleFrame.width
            let x  = screen.visibleFrame.minX + (sw - 482) / 2
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
    }

    // MARK: – Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let url = Bundle.module.url(forResource: "icon-menu", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                button.image = img
            }
        }

        statusItem?.menu = buildMenu()
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

    /// メニューバーアイコンはアップロード中は変更しない。
    /// 完了時のみチェックマーク → 通知 → 元アイコンへ復帰。
    private func observeUploadState() {
        state.$isUploading
            .dropFirst()                        // 初期値 false は無視
            .receive(on: RunLoop.main)
            .sink { [weak self] uploading in
                guard let self, uploading == false else { return }
                self.statusItem?.button?.image = self.makeCheckmarkImage()
                self.sendUploadCompleteNotification()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.restoreOriginalIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func restoreOriginalIcon() {
        if let url = Bundle.module.url(forResource: "icon-menu", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
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
        // UNUserNotificationCenter requires a proper .app bundle.
        // Skip gracefully when running as a bare binary (e.g. Xcode DerivedData).
        guard Bundle.main.bundleIdentifier != nil else { return }
        // アプリ前面時もバナー表示させるため delegate を設定
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // アプリがアクティブな状態でも通知バナーを表示する
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func sendUploadCompleteNotification() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Upload Complete"
        content.body  = "Your recording is ready to share."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}
