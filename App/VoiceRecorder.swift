import SwiftUI
import AVFoundation

/// Запись голосового как в Telegram: удержание — запись, влево — отмена, вверх — запись без рук,
/// в режиме без рук можно остановить и прослушать перед отправкой. Пишем AAC m4a моно,
/// сервер перекодирует в ogg/opus и отправляет настоящим голосовым (Telegram — voice, WhatsApp — ptt).
@MainActor
@Observable
final class VoiceRecorder {
    enum Phase { case idle, recording, locked, preview }

    var phase: Phase = .idle
    var elapsed: TimeInterval = 0
    var levels: [CGFloat] = []
    /// текущая громкость 0…1 (сглаженная) — «дыхание» круга под пальцем
    var level: CGFloat = 0
    var playing = false
    var playProgress: Double = 0
    private(set) var fileURL: URL?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    static let maxDuration: TimeInterval = 600

    var isActive: Bool { phase != .idle }

    /// Разрешение на микрофон и старт записи. false — нет доступа или не удалось начать.
    /// Аудиосессия и рекордер поднимаются на своей очереди — главный поток (и палец на кнопке) не ждёт.
    func start() async -> Bool {
        let granted: Bool
        if AVAudioApplication.shared.recordPermission == .granted {
            granted = true
        } else {
            granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { ok in c.resume(returning: ok) }
            }
        }
        guard granted else { return false }
        let maxDur: TimeInterval = Self.maxDuration
        let box: VoiceStartBox = await withCheckedContinuation { (c: CheckedContinuation<VoiceStartBox, Never>) in
            voiceQueue.async { c.resume(returning: makeVoiceRecorder(maxDuration: maxDur)) }
        }
        guard let r = box.recorder, let url = box.url else { return false }
        recorder = r
        fileURL = url
        elapsed = 0
        level = 0
        levels = []
        playProgress = 0
        phase = .recording
        startTimer()
        return true
    }

    func lock() {
        guard phase == .recording else { return }
        phase = .locked
        haptic(.medium)
    }

    /// Остановить запись и перейти к прослушиванию.
    func toPreview() {
        recorder?.stop()
        recorder = nil
        phase = .preview
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    /// Закончить запись и отдать файл (nil — слишком короткая или нет файла).
    func finish() -> URL? {
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        stopTimer()
        let url = fileURL
        let long = elapsed >= 0.5
        phase = .idle
        level = 0
        playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return long ? url : nil
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        player?.stop()
        player = nil
        stopTimer()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        phase = .idle
        playing = false
        elapsed = 0
        level = 0
        levels = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func togglePlay() {
        guard phase == .preview, let fileURL else { return }
        if playing {
            player?.pause()
            playing = false
            return
        }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player = try? AVAudioPlayer(contentsOf: fileURL)
        }
        player?.play()
        playing = player != nil
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if let r = recorder {
            if r.isRecording {
                r.updateMeters()
                elapsed = r.currentTime
                let db: Float = r.averagePower(forChannel: 0)
                let lv: CGFloat = max(0.06, min(1, CGFloat(pow(10, Double(db) / 40))))
                levels.append(lv)
                level = level * 0.4 + lv * 0.6
                if levels.count > 600 { levels.removeFirst(levels.count - 600) }
            } else if phase == .recording || phase == .locked {
                // упёрлись в предел длительности — к прослушиванию
                toPreview()
            }
        }
        if let p = player {
            playProgress = p.duration > 0 ? p.currentTime / p.duration : 0
            if playing && !p.isPlaying {
                playing = false
                playProgress = 0
            }
        }
    }
}

/// Очередь запуска записи: setCategory/setActive и создание AVAudioRecorder занимают до ~0,2 с.
private let voiceQueue = DispatchQueue(label: "sguardo.voice", qos: .userInitiated)

private final class VoiceStartBox: @unchecked Sendable {
    var recorder: AVAudioRecorder?
    var url: URL?
}

/// Пишем AAC m4a моно; вызывается на voiceQueue.
private func makeVoiceRecorder(maxDuration: TimeInterval) -> VoiceStartBox {
    let box = VoiceStartBox()
    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let url: URL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(String(UUID().uuidString.prefix(8))).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.record(forDuration: maxDuration) else { return box }
        box.recorder = r
        box.url = url
    } catch {
        return box
    }
    return box
}

/// Полоса громкости записи: последние значения сжаты до `count` столбиков.
struct LevelBars: View {
    let levels: [CGFloat]
    var count: Int = 36
    var color: Color = .white
    var progress: Double? = nil

    var body: some View {
        let bars: [CGFloat] = LevelBars.compress(levels, count: count)
        HStack(alignment: .center, spacing: 2) {
            ForEach(bars.indices, id: \.self) { i in
                let played: Bool = progress.map { Double(i) / Double(max(1, bars.count)) < $0 } ?? true
                Capsule()
                    .fill(color.opacity(played ? 0.95 : 0.4))
                    .frame(width: 3, height: max(3, bars[i] * 24))
            }
        }
        .frame(height: 26)
    }

    static func compress(_ levels: [CGFloat], count: Int) -> [CGFloat] {
        guard !levels.isEmpty else { return Array(repeating: 0.08, count: count) }
        if levels.count <= count {
            let pad: [CGFloat] = Array(repeating: 0.08, count: count - levels.count)
            return pad + levels
        }
        var out: [CGFloat] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let from: Int = i * levels.count / count
            let to: Int = max(from + 1, (i + 1) * levels.count / count)
            out.append(levels[from..<min(to, levels.count)].max() ?? 0.08)
        }
        return out
    }
}

func durationText(_ t: TimeInterval) -> String {
    let s: Int = max(0, Int(t.rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
