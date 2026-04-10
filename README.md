# Airtime Screen Recorder Toolbar — Swift Prototype

macOS スクリーンレコーダーツールバーのネイティブ Swift プロトタイプ。  
実際の録画は行わず、**UX・インタラクションの検証**が目的。

Figma デザイン: [Airtime Screen Recorder](https://www.figma.com/design/eWkGmCt82FmhLT041qp4oW/Airtime-Screen-Recorder)

---

## 動作環境

- macOS 13 Ventura 以降
- Xcode 15 以降 または Swift 5.9+ CLI (`swift build`)
- カメラ・マイクのアクセス許可（プロンプトが出たら許可）

---

## ビルド & 起動

```bash
# リポジトリクローン
git clone <repo-url>
cd recorder-swift

# ビルド確認
swift build 2>&1 | grep -E "error:|Build complete"

# 起動
pkill RecorderToolbar 2>/dev/null; sleep 1 && .build/debug/RecorderToolbar &

# ビルド + 起動（一発）
swift build 2>&1 | grep -E "error:|Build complete" && pkill RecorderToolbar 2>/dev/null; sleep 1 && .build/debug/RecorderToolbar &
```

---

## 画面フロー

```
typeSelect ──→ windowSelect ──┐
           └→ displaySelect ──┴→ countdown → recording
```

| ステート | ツールバー幅 | 説明 |
|---|---|---|
| Type Select（初期） | 389 px | 録画タイプ選択（Display / Window / Area / Cam only） |
| Window Selecting | 389 px | TypeSelect ツールバーのまま、ウィンドウ選択オーバーレイを表示 |
| Display Selecting | 389 px | TypeSelect ツールバーのまま、ディスプレイ選択オーバーレイを表示 |
| Window / Display Selected | 389 px | ウィンドウ/ディスプレイ選択済み、Record ボタン表示 |
| Countdown | 297 px | 録画開始前のカウントダウン（3・1・なしを Settings で設定） |
| Recording | 297 px | タイマー表示・Pause / Stop |

---

## 機能一覧

### Type Select
- **Display** / **Window** — クリックすると選択オーバーレイを表示（ツールバーは TypeSelect のまま）
  - ボタンをハイライト表示（アクティブ状態を示す）
  - もう一方のボタンをクリック → 即時切り替え
  - 同じボタンを再クリック または **Esc** → オーバーレイを閉じて TypeSelect に戻る
- **Area** — 現在 UI のみ（インタラクションなし）
- **Cam only** — カメラサムネイル表示、ホバーでプレビューポップアップ
- **Settings** — Settings ボタンの上にパネルを表示
- **ホバープレビュー** — Display / Window / Area にホバーすると各タイプのプレビューを表示

### Window / Display オーバーレイ
- 画面全体にオーバーレイ表示、マウス位置のウィンドウ / ディスプレイをオレンジボーダーでハイライト
- **ウィンドウ/ディスプレイをクリック** → 選択確定 → Record ボタン付きツールバーに遷移
- Record ボタン付き状態で **Esc** → Type Select に戻り、オーバーレイ非表示

### Settings パネル
- **Camera** — 使用するカメラデバイスを選択（ホバーでサブパネル表示）
- **Microphone** — 使用するマイクデバイスを選択
- **Count down** — None / 1s / 3s から選択
- **Show cursor** — トグル（記録のみ、機能は未実装）
- **Record system audio** — トグル（記録のみ）

### Recording
- タイマー（MM:SS）・1 hour limit 表示
- **Restart** — タイマーリセットして Type Select へ
- **Pause / Resume** — タイマーを一時停止
- **Stop** — Type Select へ戻る

---

## ファイル構成

```
Sources/RecorderToolbar/
├── AppDelegate.swift          # ツールバー NSPanel 生成・初期化
├── main.swift                 # エントリーポイント
├── ToolbarState.swift         # 中央コントローラー（AppState・タイマー・カウントダウン）
├── ToolbarView.swift          # 全ステートの SwiftUI ビュー
├── CameraSegment.swift        # Camera / Mic / DeviceMenu / CameraPreview
├── WindowOverlay.swift        # ウィンドウ選択オーバーレイ
├── DisplayOverlay.swift       # ディスプレイ選択オーバーレイ
├── PreviewOverlay.swift       # TypeSelect ホバープレビュー
├── CountdownOverlay.swift     # カウントダウン数字オーバーレイ
├── SettingsPanel.swift        # Settings パネル + サブパネル
└── Helpers.swift              # 共通ヘルパー（NSPanel・NSWindow・AVCaptureDevice）
```

---

## 主要クラス

| クラス | 役割 |
|---|---|
| `ToolbarState` | 中央コントローラー。AppState 管理・カメラプレビュー・カウントダウン |
| `OverlayController` | ウィンドウ選択オーバーレイ（dim + ハイライト + badge） |
| `DisplayOverlayController` | ディスプレイ選択オーバーレイ（per-screen dim + オレンジボーダー） |
| `PreviewOverlayController` | TypeSelect ホバープレビュー（Display / Window / Area） |
| `CountdownOverlayController` | フルスクリーン カウントダウン数字オーバーレイ |
| `SettingsPanelController` | Settings パネル本体 + Camera / Mic / Countdown サブパネル |

---

## デザイン仕様

| 要素 | 値 |
|---|---|
| ツールバー背景 | `NSVisualEffectView` (.underWindowBackground, cornerRadius 10) |
| ツールバーサイズ（Type / Window / Display Select） | 389 × 56 px |
| ツールバーサイズ（Countdown / Recording） | 297 × 56 px |
| Settings パネル | 197 × 211 px |
| カメラプレビューポップアップ | 320 × 240 px |
| オレンジ選択ボーダー | `rgb(255, 109, 76)` lineWidth 3 |
| 選択済みグリーン | `rgb(48, 209, 88)` |
| Settings 背景 | `rgb(56, 56, 56)` + border rgba(255,255,255,0.15) + cornerRadius 14 |

---

## 開発メモ

### SourceKit の誤検知について

SourceKit（IDE の静的解析）が `Cannot find type 'X' in scope` を報告することがあるが、同一モジュール内の別ファイルへの参照で起きる既知の IDE バグ。  
**エラー確認は必ず `swift build` で行うこと**（SourceKit の診断は無視してよい）。

### 新しいパネル・オーバーレイを追加するとき

`Helpers.swift` の共通ヘルパーを必ず使う：

```swift
// フローティングパネル（Settings・カメラプレビュー等）
let p = NSPanel.makeFloating(level: toolbar.level)

// フルスクリーン透過オーバーレイ（ignoresMouseEvents = true）
let w = NSWindow.makeOverlay(frame: screen.frame, level: toolbar.level)

// フェードイン / フェードアウト
p.fadeIn()
p.fadeOut()

// デバイス列挙
let cameras = AVCaptureDevice.cameraDevices()
let mics    = AVCaptureDevice.micDevices()
```

### ツールバーのキーイベント

ツールバーは `.nonactivatingPanel` のためキーウィンドウにならない。  
Esc・クリック・マウス移動は**グローバル NSEvent モニター**を使うこと（ローカルモニターは動作不安定）。
