# Airtime Screen Recorder Toolbar — Prototype PRD

## 目的

新しい Screen Recorder ツールバーの UX・インタラクションを検証するための Electron プロトタイプ。
実際の録画は行わない。ツールバーのフロー・カメラ/マイク UI の体験を確認する。

---

## ウィンドウ仕様

- **形式**: Electron、フレームレス、常に最前面（alwaysOnTop）
- **ドラッグ**: ツールバーをドラッグして画面の好きな位置に移動できる
- **デフォルト位置**: 画面下部中央
- **高さ**: 68px（ステートによって幅が変わる）
- **スタイル**: ガラスモーフィズム（backdrop-blur + rgba(56,56,56,0.75) + border rgba(255,255,255,0.15)）

---

## ステート 1: タイプ選択（初期状態）

### UI
```
[×]  Display | Window | Area | Cam only  |  Options
```

### 挙動
- `×` → アプリ終了
- `Window` のみクリック可能 → ステート 2 へ
- Display / Area / Cam only / Options は見た目のみ（インタラクションなし）

---

## ステート 2: ウィンドウ選択

### UI
```
[←]  [カメラサムネイル  Opal C1 ▾]  [波形  Elgato... ▾]  [● Record]
```

### 挙動
- 画面全体に黒オーバーレイ（opacity 50%）
- マウスが乗っているウィンドウに **赤ボーダー** を表示、そのウィンドウをフロントに移動
- **カメラサムネイル**: 実際の getUserMedia 映像を表示。クリックでカメラ選択メニュー
- **マイク波形**: Web Audio API で実際のマイク音量をアニメーション表示
- `←` → ステート 1 へ戻る
- `Record` → ステート 3 へ

---

## ステート 3: 録画中

### UI
```
[↺ Restart]  [⏸ Pause]  [■ Stop]  |  00:03 / 1 hour limit
```

### 挙動
- タイマー: 00:00 からカウントアップ（実際の秒数）
- `Restart` → タイマーリセット → ステート 1 へ
- `Stop` → ステート 1 へ
- `Pause` → タイマー一時停止（Resume に切り替わる）

---

## 技術スタック

| 項目 | 内容 |
|---|---|
| フレームワーク | Electron |
| UI | HTML / CSS / Vanilla JS |
| カメラ | `navigator.mediaDevices.getUserMedia` |
| マイク波形 | Web Audio API（AnalyserNode） |
| 録画 | なし（プロトタイプのため） |
| ウィンドウ検出 | `desktopCapturer` でサムネイル一覧（簡略版） |

---

## スコープ外（プロトタイプでは実装しない）

- 実際のスクリーン録画
- Display / Area / Cam only モード
- Options メニューの中身
- アップロード・共有機能
