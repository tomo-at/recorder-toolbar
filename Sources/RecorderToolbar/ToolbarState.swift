import Foundation
import Combine
import AppKit

enum AppState {
    case typeSelect
    case windowSelect
    case recording
}

@MainActor
class ToolbarState: ObservableObject {
    @Published var appState: AppState = .typeSelect {
        didSet { handleStateChange(to: appState) }
    }
    @Published var paused = false
    @Published var seconds: Int = 0

    // Set by AppDelegate after panel creation
    weak var panel: NSPanel?
    let overlay = OverlayController()

    private var timer: AnyCancellable?

    init() {
        overlay.onSelect = { [weak self] in self?.startRecording() }
        overlay.onCancel = { [weak self] in self?.appState = .typeSelect }
    }

    private func handleStateChange(to state: AppState) {
        switch state {
        case .windowSelect:
            guard let panel else { return }
            overlay.show(keepingAbove: panel)
        case .typeSelect, .recording:
            overlay.hide()
        }
    }

    func startRecording() {
        appState = .recording
        seconds  = 0
        paused   = false
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.paused else { return }
                self.seconds += 1
            }
    }

    func stopRecording() {
        timer?.cancel()
        timer    = nil
        seconds  = 0
        appState = .typeSelect
    }

    func togglePause() { paused = !paused }

    var timeString: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
