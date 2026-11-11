import SwiftUI
import UIKit
import AVFoundation
import AVKit

/// Камера для «кружка» Telegram: фронтальная, VGA (60 с ≈ 25 МБ, укладываемся в предел 50 МБ).
/// Сервер обрезает видео в квадрат 384 px и отправляет в Telegram как video note.
final class CameraModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var ready = false
    @Published var recording = false
    @Published var elapsed: TimeInterval = 0
    @Published var outputURL: URL?
    @Published var problem: String?

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "sguardo.camera")
    private var timer: Timer?
    private var startedAt: Date?
    private var configured = false
    static let maxDuration: Double = 60

    func prepare() {
        Task { @MainActor in
            let video: Bool = await AVCaptureDevice.requestAccess(for: .video)
            let audio: Bool = await AVCaptureDevice.requestAccess(for: .audio)
            guard video else {
                self.problem = String(localized: "Нет доступа к камере — разреши в настройках iPhone")
                return
            }
            self.queue.async { self.configure(audio: audio) }
        }
    }

    private func configure(audio: Bool) {
        if configured {
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.ready = self.session.isRunning }
            return
        }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.problem = String(localized: "Камера недоступна на этом устройстве") }
            return
        }
        session.addInput(input)
        if audio, let mic = AVCaptureDevice.default(for: .audio), let micInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.maxRecordedDuration = CMTime(seconds: Self.maxDuration, preferredTimescale: 600)
        if let c = output.connection(with: .video) {
            if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        }
        session.commitConfiguration()
        session.startRunning()
        DispatchQueue.main.async { self.ready = self.session.isRunning }
    }

    func record() {
        guard ready, !recording else { return }
        outputURL = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(String(UUID().uuidString.prefix(8))).mov")
        queue.async { self.output.startRecording(to: url, recordingDelegate: self) }
        recording = true
        elapsed = 0
        startedAt = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let s = self.startedAt else { return }
            self.elapsed = min(Self.maxDuration, Date().timeIntervalSince(s))
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard recording else { return }
        queue.async { self.output.stopRecording() }
    }

    func reset() {
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        elapsed = 0
    }

    /// Фронтальная ↔ основная камера (можно и во время записи).
    func switchCamera() {
        queue.async {
            let inputs: [AVCaptureDeviceInput] = self.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            guard let current = inputs.first(where: { $0.device.hasMediaType(.video) }) else { return }
            let pos: AVCaptureDevice.Position = current.device.position == .front ? .back : .front
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(current)
            if self.session.canAddInput(input) { self.session.addInput(input) } else { self.session.addInput(current) }
            if let c = self.output.connection(with: .video) {
                if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = pos == .front }
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            }
            self.session.commitConfiguration()
        }
    }

    func shutdown() {
        timer?.invalidate()
        ready = false
        queue.async {
            if self.output.isRecording { self.output.stopRecording() }
            self.session.stopRunning()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // предел 60 с тоже приходит «ошибкой», но файл при этом записан целиком
        let ns = error as NSError?
        let finished: Bool = error == nil || (ns?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.recording = false
            if finished {
                self.outputURL = outputFileURL
            } else {
                self.problem = String(localized: "Запись не получилась, попробуй ещё раз")
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Зацикленный просмотр записанного кружка.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        let q = AVQueuePlayer()
        v.looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
        v.playerLayer.player = q
        v.playerLayer.videoGravity = .resizeAspectFill
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        q.play()
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player?.pause()
        uiView.looper = nil
    }
}
