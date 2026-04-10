import Foundation
import Combine

enum AppState {
    case typeSelect
    case windowSelect
    case recording
}

@MainActor
class ToolbarState: ObservableObject {
    @Published var appState: AppState = .typeSelect
    @Published var paused = false

    // Timer
    @Published var seconds: Int = 0
    private var timer: AnyCancellable?

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

    func togglePause() {
        paused = !paused
    }

    var timeString: String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
