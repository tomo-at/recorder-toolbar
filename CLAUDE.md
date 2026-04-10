# recorder-swift

macOS スクリーンレコーダーツールバーのネイティブ Swift プロトタイプ。
実際の録画は行わず、UX・インタラクションの検証が目的。

---

## ビルド & 起動

```bash
# ビルド確認
cd ~/workspace/recorder-swift && swift build 2>&1 | grep -E "error:|Build complete"

# 起動
pkill RecorderToolbar 2>/dev/null; sleep 1 && ~/workspace/recorder-swift/.build/debug/RecorderToolbar &

# ビルド + 起動（一発）
cd ~/workspace/recorder-swift && swift build 2>&1 | grep -E "error:|Build complete" && pkill RecorderToolbar 2>/dev/null; sleep 1 && .build/debug/RecorderToolbar &
```

---

## アーキテクチャ

### 画面遷移（AppState）

```
typeSelect ──→ windowSelect ──┐
           └→ displaySelect ──┴→ countdown → recording
```

`ToolbarState.appState` を変更すると `handleStateChange(to:)` が呼ばれ、
パネルリサイズ・オーバーレイ表示切替・Esc モニター管理が一括で行われる。

### 主要クラスの役割

| クラス | 役割 |
|---|---|
| `ToolbarState` | 中央コントローラー。AppState 管理・カメラプレビュー・カウントダウンロジック |
| `OverlayController` | ウィンドウ選択オーバーレイ（dim + 穴 + badge） |
| `DisplayOverlayController` | ディスプレイ選択オーバーレイ（per-screen dim + orange border） |
| `PreviewOverlayController` | TypeSelect ホバープレビュー（Display/Window/Area） |
| `CountdownOverlayController` | フルスクリーン カウントダウン数字オーバーレイ |
| `SettingsPanelController` | Settings パネル本体 + Camera/Mic/Countdown サブパネル |

### ファイル構成

| ファイル | 内容 |
|---|---|
| `AppDelegate.swift` | ツールバー NSPanel 生成・ToolbarState 初期化 |
| `ToolbarState.swift` | AppState + 全コントローラー所有・カメラプレビューポップアップ |
| `ToolbarView.swift` | AppState スイッチ・TypeSelectView / WindowSelectView / CountdownToolbarView / RecordingView・共通コンポーネント |
| `WindowOverlay.swift` | ウィンドウ選択オーバーレイ一式（DetectedWindow・OverlayState・OverlayController） |
| `DisplayOverlay.swift` | ディスプレイ選択オーバーレイ一式 |
| `PreviewOverlay.swift` | TypeSelect ホバープレビューオーバーレイ |
| `CountdownOverlay.swift` | カウントダウンオーバーレイ |
| `CameraSegment.swift` | CameraSegment / MicSegment / CamOnlySegment / CameraThumb / CameraPreviewView / DeviceMenuView / MicLevelBars |
| `SettingsPanel.swift` | SettingsPanelController・SettingsState・Settings 全 SwiftUI ビュー |
| `Helpers.swift` | **共通ヘルパー**（後述） |

---

## Helpers.swift — 必ず使うこと

新しいパネル・オーバーレイを作るときは必ずこれを使う。

```swift
// フローティング NSPanel（Settings パネル・カメラプレビュー等）
let p = NSPanel.makeFloating(level: toolbar.level)
p.contentView = NSHostingView(rootView: MyView())
p.setFrame(rect, display: false)
p.fadeIn()          // アルファ 0→1 フェードイン
p.fadeOut()         // アルファ 1→0 フェードアウト後に orderOut

// フルスクリーン透過オーバーレイ NSWindow（ignoresMouseEvents=true）
let w = NSWindow.makeOverlay(frame: screen.frame, level: toolbar.level)
hosting.frame = CGRect(origin: .zero, size: screen.frame.size)
w.contentView = hosting
w.fadeIn(duration: 0.2)
w.fadeOut(duration: 0.15, resetAlpha: true)  // resetAlpha: 再利用時に alphaValue を 1 に戻す

// デバイス検出（.external を使用、.externalUnknown は deprecated）
let cameras = AVCaptureDevice.cameraDevices()
let mics    = AVCaptureDevice.micDevices()
```

---

## 重要パターン

### 1. グローバル NSEvent モニター
ツールバーは `.nonactivatingPanel` のため **絶対にキーウィンドウにならない**。
ローカルモニターは動作不安定 → Esc・クリック・マウス移動はグローバルモニターを使う。

```swift
// グローバル：他プロセスへのイベントを傍受（自パネルへのイベントは来ない）
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in ... }

// ローカル：自パネルがキーウィンドウのときのみ（基本的に信頼できない）
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in ... return event }
```

### 2. Freeze パターン（競合状態の回避）
`freeze()` は必ず `hoveredWindow/Screen` を `frozenWindow/Screen` にスナップショットしてから
`stopTracking()` を呼ぶ。`updateHover()` 冒頭に `guard !state.isSelected else { return }` を置き、
キャンセル済み Task による上書きを防ぐ。

### 3. 座標系
| 系 | 原点 | 用途 |
|---|---|---|
| CG（CoreGraphics） | 左上 | `CGWindowListCopyWindowInfo`・ウィンドウ bounds |
| AppKit / NSScreen | 左下 | `NSEvent.mouseLocation`・`screen.frame` |
| SwiftUI on NSWindow | ウィンドウ左上 | `PerScreenOverlayView` 内の描画座標 |

変換: `cgY = primaryScreenHeight - apkY`
プライマリスクリーン = `frame.origin == .zero` の NSScreen

### 4. AVCaptureSession スレッド
セッション開始・停止は必ず `sessionQ`（serial queue）で実行。
UI 更新（`previewLayer` 追加等）は `DispatchQueue.main.async` に戻す。
→ `CameraPreviewView.start()` / `stop()` 参照。

---

## サイズ定数

| 要素 | サイズ |
|---|---|
| ツールバー（typeSelect / windowSelect / displaySelect） | 389 × 56 px |
| ツールバー（countdown / recording） | 297 × 56 px |
| Settings パネル | 197 × 211 px（ツールバー中央上、8px 上） |
| カメラプレビューポップアップ | 320 × 240 px（ツールバー中央上、8px 上） |
| SegmentButton | 64 × 48 px |
| CloseSection | 44 × 56 px |

---

## デザイン

- **Figma**: https://www.figma.com/design/eWkGmCt82FmhLT041qp4oW/Airtime-Screen-Recorder
- **ツールバー背景**: `NSVisualEffectView` (.underWindowBackground、cornerRadius 10)
- **オレンジ選択ボーダー**: `Color(red: 1.0, green: 0.427, blue: 0.298)` lineWidth 3
- **選択済みグリーン**: `Color(red: 0.188, green: 0.820, blue: 0.345)`
- **Settings / サブパネル背景**: `Color(red: 0.22, green: 0.22, blue: 0.22)` + border rgba(255,255,255,0.15) + cornerRadius 14
- **SegmentButton ホバー**: `Color.white.opacity(0.08)` + cornerRadius 4

---

## SourceKit 誤検知について

SourceKit が `Cannot find type 'X' in scope` を報告することがあるが、
同一モジュール内の別ファイルへの参照で起きる既知の IDE バグ。
**エラー確認は必ず `swift build` で行う**（SourceKit の診断は無視してよい）。
