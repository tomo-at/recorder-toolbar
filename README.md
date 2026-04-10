# Recorder Toolbar — Swift Prototype

A native Swift prototype of a macOS screen recorder toolbar.  
**No actual recording** — built purely to validate UX and interaction flows.

Figma design: [Airtime Screen Recorder](https://www.figma.com/design/eWkGmCt82FmhLT041qp4oW/Airtime-Screen-Recorder)

---

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ or Swift 5.9+ CLI
- Camera and microphone access (grant when prompted)

---

## Build & Run

```bash
git clone https://github.com/tomo-at/recorder-toolbar.git
cd recorder-toolbar

swift build

# Launch
pkill RecorderToolbar 2>/dev/null; sleep 1 && .build/debug/RecorderToolbar &
```

---

## File Structure

```
Sources/RecorderToolbar/
├── AppDelegate.swift       # NSPanel setup and initialization
├── ToolbarState.swift      # Central controller (AppState, timer, countdown)
├── ToolbarView.swift       # SwiftUI views for all states
├── CameraSegment.swift     # Camera / Mic / DeviceMenu / CameraPreview
├── WindowOverlay.swift     # Window selection overlay
├── DisplayOverlay.swift    # Display selection overlay
├── PreviewOverlay.swift    # TypeSelect hover preview
├── CountdownOverlay.swift  # Countdown number overlay
├── SettingsPanel.swift     # Settings panel and sub-panels
└── Helpers.swift           # Shared NSPanel / NSWindow / AVCaptureDevice helpers
```
