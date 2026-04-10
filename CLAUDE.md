# recorder-swift

## ビルド

```
cd ~/workspace/recorder-swift && swift build
```

## 起動

```
pkill RecorderToolbar 2>/dev/null; sleep 1 && ~/workspace/recorder-swift/.build/debug/RecorderToolbar &
```

## ビルド + 起動（一発）

```
cd ~/workspace/recorder-swift && swift build 2>&1 | grep -E "error:|Build complete" && pkill RecorderToolbar 2>/dev/null; sleep 1 && .build/debug/RecorderToolbar &
```
