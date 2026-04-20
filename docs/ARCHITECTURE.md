# Architecture Reference

CLAUDE.md から分離した参照テーブル。判断に必要なルールは CLAUDE.md に残してある。

---

## ファイル構成

| ファイル | 内容 |
|---|---|
| `AppDelegate.swift` | ツールバー NSPanel 生成・ToolbarState 初期化・メニューバー・通知 |
| `ToolbarState.swift` | AppState + 全コントローラー所有・カメラプレビュー・デバイス読み込み |
| `ToolbarView.swift` | AppState × ProtoVersion ディスパッチ・V5 組み合わせビュー・共通コンポーネント |
| `ToolbarViewLegacy.swift` | V1–V3 用全ビュー（TypeSelectView / TypeSelectViewV2 / TypeSelectViewV3 / WindowSelectView / CountdownToolbarView / RecordingView） |
| `ToolbarViewV4.swift` | V4 用全ビュー（TypeSelectViewV4 / CountdownToolbarViewV4 / RecordingViewV4） |
| `ToolbarViewHorizontal.swift` | V5 Horizontal スタイル用ビュー群（HorizontalTypeSelectView / HorizontalWindowSelectView / HorizontalRecordingView / RevealedAllCompactTypeSelectView） |
| `WindowOverlay.swift` | ウィンドウ選択オーバーレイ（DetectedWindow・OverlayState・OverlayController） |
| `DisplayOverlay.swift` | ディスプレイ選択オーバーレイ |
| `PreviewOverlay.swift` | TypeSelect ホバープレビューオーバーレイ |
| `CountdownOverlay.swift` | カウントダウンオーバーレイ |
| `CameraSegment.swift` | CameraSegment / MicSegment / CamOnlySegment / CameraThumb / CameraPreviewView / DeviceMenuView / MicLevelBars |
| `SettingsPanel.swift` | SettingsPanelController・SettingsState（V5 軸 enum + UserDefaults）・Settings SwiftUI ビュー |
| `PrototypeSettingsWindow.swift` | V5 独立設定ウィンドウ（DefaultStyle × RecordingStyle × UploadStyle） |
| `Helpers.swift` | Airtime DS 色トークン・NSPanel/NSWindow ファクトリ・フェードアニメーション・SelectionConfirmPanel |

---

## 主要クラスの役割

| クラス | 役割 |
|---|---|
| `ToolbarState` | 中央コントローラー。AppState 管理・カメラプレビュー・カウントダウン・デバイス |
| `OverlayController` | ウィンドウ選択オーバーレイ（dim + 穴 + badge） |
| `DisplayOverlayController` | ディスプレイ選択オーバーレイ（per-screen dim + orange border） |
| `PreviewOverlayController` | TypeSelect ホバープレビュー（Display/Window/Area） |
| `CountdownOverlayController` | フルスクリーン カウントダウン数字オーバーレイ |
| `SettingsPanelController` | Settings パネル本体 + Prototype Settings ウィンドウ管理 |
| `SelectionConfirmPanelController` | V4/V5(.selectedRegion) 用の選択確認パネル |

---

## サイズ定数

| 要素 | サイズ |
|---|---|
| ツールバー高さ | 56 px（標準）/ 66 px（Message スタイル）/ 48 px（Horizontal スタイル） |
| ツールバー幅（typeSelect） | V1: 345 / V2: 506 / V3: 510 / V4: 482 / V5-Compact: 470 px |
| ツールバー幅（windowSelect） | 389 px（V1–V3）/ 482 px（V4・V5 Horizontal） |
| ツールバー幅（countdown/recording） | 297 px（通常）/ 365 px（Horizontal） |
| Prototype Settings ウィンドウ | 360 × 680 px |
| カメラプレビューポップアップ | 320 × 240 px |
| SegmentButton | 64 × 48 px |

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
