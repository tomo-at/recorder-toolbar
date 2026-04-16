# recorder-swift

macOS スクリーンレコーダーツールバーのネイティブ Swift プロトタイプ。
実際の録画は行わず、UX・インタラクションの検証が目的。
ファイル構成・クラス役割・サイズ定数は → `docs/ARCHITECTURE.md`

---

## ビルド & 起動

**必ず Makefile 経由で `.app` バンドルとして起動すること**（通知に必須）。

```bash
make build   # ビルド + .app バンドル生成 + 署名
make run     # ビルド + 起動
make doctor  # 通知・署名・バンドル構造の 6 項目診断
```

### 通知が動作する条件

1. `.app` バンドル構造（`Info.plist` + `MacOS/`）
2. `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` が Info.plist にある
3. Apple Development 証明書で署名（ad-hoc だと拒否）
4. バンドル ID が未拒否状態（拒否キャッシュは ID を bump して回避。例: `.v3` → `.v4`）

通知が出ないときは **`make doctor`** を実行 → 項目 4/5 を確認。

---

## アーキテクチャ

### 画面遷移（AppState）

```
typeSelect ──→ windowSelect ──┐
           └→ displaySelect ──┴→ countdown → recording
```

`ToolbarState.appState` を変更すると `handleStateChange(to:)` が呼ばれ、
パネルリサイズ・オーバーレイ表示切替・Esc モニター管理が一括で行われる。

---

## Helpers.swift — 必ず使うこと

新しいパネル・オーバーレイ作成時は `NSPanel.makeFloating(level:)` / `NSWindow.makeOverlay(frame:level:)` を使う。
フェード: `.fadeIn()` / `.fadeOut(resetAlpha:)`。デバイス: `AVCaptureDevice.cameraDevices()` / `.micDevices()`。
色: `Helpers.swift` の `extension Color` に Airtime DS 全トークンが定義済み → ハードコード色を避ける。

---

## 重要パターン

### 1. グローバル NSEvent モニター
ツールバーは `.nonactivatingPanel` → **キーウィンドウにならない**。
Esc・クリック・マウス移動はグローバルモニター必須（ローカルは信頼不可）。

### 2. Freeze パターン（競合状態の回避）
`freeze()` は `hoveredWindow/Screen` → `frozenWindow/Screen` スナップショット後に `stopTracking()`。
`updateHover()` 冒頭に `guard !state.isSelected else { return }` でキャンセル済み Task の上書き防止。

### 3. 座標系
| 系 | 原点 | 用途 |
|---|---|---|
| CG | 左上 | `CGWindowListCopyWindowInfo`・ウィンドウ bounds |
| AppKit | 左下 | `NSEvent.mouseLocation`・`screen.frame` |
| SwiftUI on NSWindow | ウィンドウ左上 | `PerScreenOverlayView` 内の描画 |

変換: `cgY = primaryScreenHeight - apkY`（`NSScreen.primaryHeight` ヘルパー使用）

### 4. AVCaptureSession スレッド
開始・停止は `sessionQ`（serial queue）で実行 → UI 更新は `DispatchQueue.main.async`。

---

## デザイン

- **Figma**: https://www.figma.com/design/eWkGmCt82FmhLT041qp4oW/Airtime-Screen-Recorder
- **Airtime DS トークン**: `~/workspace/airtime-design-system-main/tokens/colors.json` が正
- **Swift 定数**: `Helpers.swift` の `extension Color` に全トークン定義済み
- **ツールバー背景**: `NSVisualEffectView` (.underWindowBackground、cornerRadius 10)
- **トークン命名**: `<category>-<color>-<N>` の N は不透明度 %。数字なしはソリッド色

---

## SourceKit 誤検知

`Cannot find type 'X' in scope` は同一モジュール内の別ファイル参照で起きる IDE バグ。
**エラー確認は必ず `swift build` で行う。**
