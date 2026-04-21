# Architecture Reference

CLAUDE.md から分離した参照テーブル。判断に必要なルールは CLAUDE.md に残してある。

---

## ファイル構成

| ファイル | 内容 |
|---|---|
| `main.swift` | アプリエントリポイント（NSApplication.main） |
| `AppDelegate.swift` | ツールバー NSPanel 生成・ToolbarState 初期化・メニューバー・通知 |
| `ToolbarState.swift` | 中央コントローラー。全コントローラー所有・AppState 管理・Esc モニター・デバイス読み込み |
| `ToolbarState+Selection.swift` | 選択モード制御（toggleSelecting / enterSelecting / exitSelecting / selectWindowFromSheet / selectDisplayFromSheet） |
| `ToolbarState+Recording.swift` | 録画・カウントダウン・アップロード・stopRecording |
| `ToolbarState+WindowRecording.swift` | 複数ウィンドウ録画（add / remove / switch / toolbar controls パターン） |
| `ToolbarState+PanelLayout.swift` | PanelDimensions 定数・resizePanel・panelHeight |
| `ToolbarState+CameraPreview.swift` | カメラプレビューポップアップ表示制御 |
| `ToolbarState+PreviewMode.swift` | TypeSelect ホバー時のオーバーレイプレビュー制御 |
| `ToolbarState+AreaConfirm.swift` | エリア確認パネル表示制御 |
| `ToolbarState+ViewHelpers.swift` | ショートカットツールチップ・ツールバーウィンドウポップアップ表示ヘルパー |
| `ToolbarView.swift` | AppState × ProtoVersion ディスパッチ・V5 組み合わせビュー |
| `ToolbarComponents.swift` | 共通 UI コンポーネント（SegmentButton / UploadProgressBarView / ToolbarHeader / ToolbarDivider / CloseSection） |
| `ToolbarViewLegacy.swift` | V1–V3 用全ビュー（TypeSelectView / TypeSelectViewV2 / TypeSelectViewV3 / WindowSelectView / CountdownToolbarView / RecordingView） |
| `ToolbarViewV4.swift` | V4 用全ビュー（TypeSelectViewV4 / CountdownToolbarViewV4 / RecordingViewV4 / SelectionConfirmView / CamOnlyConfirmView / CamOnlyPreviewView） |
| `ToolbarViewV5.swift` | V5 ディスパッチビュー（V5TypeSelect / V5WindowSelect / V5Countdown / V5Recording / UploadModeView） |
| `ToolbarViewHorizontal.swift` | V5 Horizontal / RevealedAllCompact ビュー群（HorizontalTypeSelectView / HorizontalCaptureSheet / RevealedAllCompactTypeSelectView） |
| `WindowOverlay.swift` | ウィンドウ選択オーバーレイ（DetectedWindow・OverlayState・OverlayController） |
| `AreaOverlay.swift` | エリア選択オーバーレイ（AreaSelectionState・AreaOverlayController） |
| `DisplayOverlay.swift` | ディスプレイ選択オーバーレイ（DisplayOverlayController） |
| `PreviewOverlay.swift` | TypeSelect ホバープレビューオーバーレイ |
| `CountdownOverlay.swift` | カウントダウンオーバーレイ |
| `WindowSelectionBottomBar.swift` | フルスクリーンウィンドウピッカー時の画面下部ヒントバー |
| `CameraSegment.swift` | CameraSegment / MicSegment / CamOnlySegment / CameraThumb / CameraPreviewView / DeviceMenuView / MicLevelBars |
| `SettingsPanel.swift` | SettingsPanelController・SettingsState（V5 軸 enum + UserDefaults）・Settings SwiftUI ビュー |
| `PrototypeSettingsWindow.swift` | V5 独立設定ウィンドウ（DefaultStyle × RecordingStyle × UploadStyle × AddWindow） |
| `Helpers.swift` | Airtime DS 色トークン・KeyablePanel・NSPanel/NSWindow/NSScreen ファクトリ・フェードアニメーション・AVCaptureDevice 拡張 |
| `PanelControllers.swift` | DS ダイアログ部品（BackdropBlur / DSGhostButtonStyle / DSPrimaryButtonStyle / DSDialogContainer）・各種パネルコントローラーとそのビュー（ShortcutTooltip / ToolbarWindowPopup / WindowMultiDialog / WindowHoverDialog / UploadCompleteBanner / CamOnlyPanel / SelectionConfirmPanel） |

---

## 主要クラスの役割

| クラス | 役割 |
|---|---|
| `ToolbarState` | 中央コントローラー。AppState・SelectionMode 管理、全コントローラー所有、Esc モニター、カウントダウン、アップロード、デバイス |
| `OverlayController` | ウィンドウ選択オーバーレイ（dim + 穴 + badge） |
| `DisplayOverlayController` | ディスプレイ選択オーバーレイ（per-screen dim + orange border） |
| `AreaOverlayController` | エリア選択オーバーレイ（ドラッグ選択・確認パネル連携） |
| `PreviewOverlayController` | TypeSelect ホバープレビュー（Display/Window/Area） |
| `CountdownOverlayController` | フルスクリーン カウントダウン数字オーバーレイ |
| `SettingsPanelController` | Settings パネル本体 + Prototype Settings ウィンドウ管理 |
| `ShortcutTooltipController` | ツールバーボタンのショートカットツールチップ |
| `ToolbarWindowPopupController` | 録画中ウィンドウボタンの Remove/Switch ポップアップ |
| `WindowMultiDialogController` | ホバー時の「Add window」ダイアログ |
| `WindowHoverDialogController` | 録画済みウィンドウホバー時の Switch/Remove ダイアログ |
| `UploadCompleteBannerController` | アップロード完了バナー |
| `CamOnlyPanelController` | Cam only 大プレビューパネル（Confirm / Preview の 2 モード） |
| `SelectionConfirmPanelController` | V4/V5(.selectedRegion) 用の選択確認パネル |
| `WindowSelectionBottomBarController` | フルスクリーンウィンドウピッカー時の画面下部ヒントバー |

---

## サイズ定数

| 要素 | サイズ |
|---|---|
| ツールバー高さ | 56 px（標準）/ 66 px（Message スタイル）/ 48 px（Horizontal スタイル） |
| ツールバー幅（typeSelect） | V1: 345 / V2: 506 / V3: 510 / V4: 482 / V5-Compact: 470 px |
| ツールバー幅（windowSelect） | 389 px（V1–V3）/ 482 px（V4・V5 Horizontal） |
| ツールバー幅（countdown/recording） | 297 px（通常）/ 365 px（Horizontal） |
| Cam only Confirm パネル | 1080 × 652 px（カメラ 608 px + コントロールバー 44 px） |
| Cam only Preview パネル | 1080 × 608 px（16:9 カメラのみ） |
| SelectionConfirm パネル | 284 × 204 px |
| Prototype Settings ウィンドウ | 360 × 680 px |
| カメラプレビューポップアップ | 320 × 240 px |
| SegmentButton | 64 × 48 px |
| HorizontalCaptureSheet（シート全体） | 324 × 400 px |
| HorizontalCaptureSheet（スクロール領域） | 高さ 312 px |
| HorizontalCaptureSheet（サムネイルセル） | 148 × 84 px |

---

## プロトタイプ責務

### V5（メイン・3 軸組み合わせ）

| 軸 | 選択肢 |
|---|---|
| Default style | Step by step (V1) / Revealed all (V2) / Message (V4) |
| Recording | Toolbar (V1/V2 風) / Selected region (V4 風 confirm panel) |
| Uploading | Toolbar (進捗バー + バッジ) / Menu bar + Notification (円弧 + 通知) |

ヘッダーバーは **DefaultStyle == .message のときのみ** 全ステートで表示。

### V1–V4（レガシー、将来削除予定）

| バージョン | アップロード UI | 選択確認パネル | 特徴 |
|---|---|---|---|
| V1 | ツールバー 4px バー + バッジ | なし | Step by step |
| V2 | メニューバー円弧 + 通知 | なし | Camera + Mic 常時表示 |
| V3 | なし | なし | Segmented control |
| V4 | なし | あり | Message header bar |
