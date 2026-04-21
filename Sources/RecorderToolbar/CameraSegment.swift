import SwiftUI
import AVFoundation
import CoreMedia

struct CameraSegment: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    var onHoverChanged: ((Bool) -> Void)? = nil
    @State private var stream: AVCaptureSession? = nil
    @State private var showMenu = false
    @State private var hovering = false

    var activeDevice: AVCaptureDevice? {
        devices.first { $0.uniqueID == activeId }
    }

    var label: String {
        guard let d = activeDevice else { return "Camera" }
        return String(d.localizedName.replacingOccurrences(of: " Camera", with: "").prefix(12))
    }

    var body: some View {
        Button {
            showMenu.toggle()
        } label: {
            VStack(spacing: 4) {
                CameraThumb(deviceId: activeId)
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color.contentTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 60)
            }
            .frame(width: 64, height: 48)
            .background(hovering ? Color.highlightPrimary : .clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            onHoverChanged?(h)
        }
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            DeviceMenuView(devices: devices, activeId: $activeId)
        }
    }
}

// Camera-only button for TypeSelectView — shows live preview thumbnail, no device menu.
struct CamOnlySegment: View {
    let activeId: String?
    var isActive: Bool = false
    var action: () -> Void = {}
    var onHoverChanged: ((Bool) -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        Button { action() } label: {
            VStack(spacing: 4) {
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                Text("Cam only")
                    .font(.system(size: 11))
                    .foregroundColor(Color.contentTertiary)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 48)
            .background(isActive || hovering ? Color.highlightPrimary : .clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            onHoverChanged?(h)
        }
    }
}

struct MicSegment: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    @State private var showMenu = false
    @State private var hovering = false
    @State private var level: Float = 0
    @State private var meterTimer: Timer? = nil

    var activeDevice: AVCaptureDevice? {
        devices.first { $0.uniqueID == activeId }
    }

    var label: String {
        guard let d = activeDevice else { return "Microphone" }
        return String(d.localizedName.prefix(12))
    }

    var body: some View {
        Button {
            showMenu.toggle()
        } label: {
            VStack(spacing: 4) {
                MicLevelBars(level: level)
                    .frame(width: 12, height: 20)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color.contentTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 60)
            }
            .frame(width: 64, height: 48)
            .background(hovering ? Color.highlightPrimary : .clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showMenu, arrowEdge: .bottom) {
            DeviceMenuView(devices: devices, activeId: $activeId)
        }
        .onAppear { startFakeMeter() }
        .onDisappear { meterTimer?.invalidate() }
    }

    func startFakeMeter() {
        var t: Float = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            t += 0.04
            level = 0.15 + abs(sin(t)) * 0.5
        }
    }
}

struct MicLevelBars: View {
    let level: Float   // 0-1
    private let barCount = 10

    var litCount: Int {
        Int(Float(barCount) * min(level, 1) * 1.0)
    }

    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<barCount, id: \.self) { i in
                let fromBottom = barCount - 1 - i
                Rectangle()
                    .fill(fromBottom < litCount
                          ? Color.selectedGreen
                          : Color.white.opacity(0.24))
                    .frame(width: 12, height: 1)
                    .cornerRadius(2)
            }
        }
    }
}

/// Mic SF Symbol filled from bottom by audio level (green on gray).
/// Self-contained with its own fake meter timer.
struct MicIconWithLevel: View {
    let size: CGFloat
    @State private var level: Float = 0
    @State private var meterTimer: Timer? = nil

    var body: some View {
        ZStack {
            // Base: dim icon
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.67))
                .foregroundColor(.contentTertiary)
            // Fill: green, masked from bottom by level
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.67))
                .foregroundColor(.selectedGreen)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: size * CGFloat(max(0, 1 - level)))
                        Color.white
                            .frame(height: size * CGFloat(min(1, level)))
                    }
                }
        }
        .frame(width: size, height: size)
        .onAppear { startFakeMeter() }
        .onDisappear { meterTimer?.invalidate() }
    }

    private func startFakeMeter() {
        var t: Float = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            t += 0.04
            level = 0.15 + abs(sin(t)) * 0.5
        }
    }
}

// MARK: – Real-time mic audio level delegate (unused – kept for future use)

/// AVCaptureAudioDataOutput delegate that calculates RMS audio level from sample buffers.
class MicAudioLevelDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let onLevel: @Sendable (Float) -> Void

    init(onLevel: @escaping @Sendable (Float) -> Void) {
        self.onLevel = onLevel
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                    didOutput sampleBuffer: CMSampleBuffer,
                                    from connection: AVCaptureConnection) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee,
              let buf = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(buf, atOffset: 0, lengthAtOffsetOut: nil,
                                           totalLengthOut: &length, dataPointerOut: &dataPointer) == noErr,
              let ptr = dataPointer, length > 0 else { return }

        let rms: Float
        if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { return }
            let floatPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
            var sum: Float = 0
            for i in 0..<count { sum += floatPtr[i] * floatPtr[i] }
            rms = sqrt(sum / Float(count))
        } else {
            // 16-bit integer PCM
            let count = length / MemoryLayout<Int16>.size
            guard count > 0 else { return }
            let int16Ptr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Int16.self)
            var sum: Float = 0
            for i in 0..<count {
                let s = Float(int16Ptr[i]) / Float(Int16.max)
                sum += s * s
            }
            rms = sqrt(sum / Float(count))
        }

        onLevel(min(1.0, rms * 4))
    }
}

struct DeviceMenuView: View {
    let devices: [AVCaptureDevice]
    @Binding var activeId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ForEach(devices, id: \.uniqueID) { device in
                Button {
                    activeId = device.uniqueID
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(device.uniqueID == activeId
                                  ? Color.selectedGreen
                                  : .clear)
                            .frame(width: 6, height: 6)
                        Text(device.localizedName)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(device.uniqueID == activeId ? 0.06 : 0))
            }
        }
        .padding(4)
        .background(Color.deviceMenuBg)
        .cornerRadius(8)
        .frame(minWidth: 200, maxWidth: 280)
    }
}

struct CameraThumb: NSViewRepresentable {
    let deviceId: String?

    func makeNSView(context: Context) -> CameraPreviewView {
        CameraPreviewView()
    }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        view.start(deviceId: deviceId)
    }

    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) {
        nsView.stop()
    }
}

class CameraPreviewView: NSView {
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentDeviceId: String?
    // Serial queue ensures start/stop never race
    private let sessionQ = DispatchQueue(label: "cam.session", qos: .userInitiated)

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func stop() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        currentDeviceId = nil
        let s = session; session = nil
        sessionQ.async { s?.stopRunning() }
    }

    func start(deviceId: String?) {
        guard let id = deviceId, id != currentDeviceId else { return }
        currentDeviceId = id

        // Remove old layer immediately; stop old session on queue
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        let old = session; session = nil

        sessionQ.async { [weak self] in
            old?.stopRunning()
            guard let self else { return }

            guard let device = AVCaptureDevice.cameraDevices().first(where: { $0.uniqueID == id }),
                  let input  = try? AVCaptureDeviceInput(device: device) else { return }

            let s = AVCaptureSession()
            if s.canAddInput(input) { s.addInput(input) }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentDeviceId == id else { return }
                let layer = AVCaptureVideoPreviewLayer(session: s)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.bounds
                if device.position == .front {
                    layer.transform = CATransform3DMakeScale(-1, 1, 1)
                }
                self.wantsLayer = true
                self.layer?.addSublayer(layer)
                self.previewLayer = layer
                self.session = s
            }

            s.startRunning()
        }
    }
}
