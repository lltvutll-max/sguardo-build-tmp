import SwiftUI
import UIKit
import AVFoundation
import CryptoKit
import Combine

// MARK: - размеры ленты (как в Telegram iOS)

@MainActor
enum ChatLayout {
    static var screenW: CGFloat { UIScreen.main.bounds.width }
    /// Кружок ≈ 0.62 ширины экрана (на iPhone ~250 pt).
    static var noteSide: CGFloat { min(270, (screenW * 0.62).rounded()) }
    /// Пузырь голосового ≈ 0.8 экрана, но не шире ряда ленты (поля 12 + 12 и зазор 60 у Bubble).
    static var voiceWidth: CGFloat { min(screenW * 0.8, screenW - 84) }
    /// Пузырь расшифровки кружка.
    static var noteTextWidth: CGFloat { min(screenW * 0.78, screenW - 84) }
}

/// Тёмная полупрозрачная капсула поверх медиа, как в Telegram: чёрный ~40 % + размытие, белый текст.
struct TGPill: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.white)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.black.opacity(0.42))
                }
                .environment(\.colorScheme, .dark)
            }
    }
}

extension View {
    func tgPill() -> some View { modifier(TGPill()) }
}

// MARK: - расшифровка «→A»

/// Кнопка расшифровки как в Telegram: «→A»; идёт запрос — крутилка; раскрыто — подсвечена.
/// pill = true — тёмная капсула поверх кружка; иначе — капсула внутри пузыря голосового.
struct TranscribeButton: View {
    let out: Bool
    let loading: Bool
    let expanded: Bool
    var pill: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(loading)
        .accessibilityLabel(expanded ? String(localized: "Скрыть расшифровку") : String(localized: "Расшифровать в текст"))
        .accessibilityIdentifier("transcribe")
    }

    @ViewBuilder private var label: some View {
        if pill {
            glyph(.white)
                .frame(width: 38, height: 24)
                .tgPill()
                .overlay(Capsule().stroke(Color.white.opacity(expanded ? 0.55 : 0), lineWidth: 1))
        } else {
            let fg: Color = out ? Pal.ink : .white
            glyph(fg)
                .frame(width: 38, height: 26)
                .background(Capsule().fill(fg.opacity(expanded ? 0.26 : 0.13)))
        }
    }

    @ViewBuilder private func glyph(_ fg: Color) -> some View {
        if loading {
            ProgressView().controlSize(.mini).tint(fg)
        } else {
            HStack(spacing: 1) {
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                Text("A").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(fg)
        }
    }
}

/// Состояние расшифровки одного сообщения: с сервера, из кэша сессии или по запросу.
struct TranscriptModel {
    var expanded = false
    var loading = false

    static func text(_ t: Transcript) -> String {
        let s = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? String(localized: "Речь не распознана") : s
    }
}

// MARK: - голосовое

/// Скорость голосовых — общая, как в Telegram (1× → 1.5× → 2×).
enum VoiceRate {
    static let values: [Float] = [1, 1.5, 2]
    static func label(_ r: Float) -> String { r == 1 ? "1×" : (r == 2 ? "2×" : "1.5×") }
    static func next(_ r: Float) -> Float {
        let i = values.firstIndex(of: r) ?? 0
        return values[(i + 1) % values.count]
    }
}

/// Волна голосового: пики громкости из самого файла (AVAssetReader), кэш в памяти и в Caches/waves.
/// Формат, который AVAssetReader не читает (например, ogg/opus), — ровная «речевая» волна от хэша файла.
/// Точек в волне (кэш хранит столько байт).
let wavePointCount = 64

@MainActor
final class WaveCache {
    static let shared = WaveCache()
    private var memory: [String: [Float]] = [:]
    private var tasks: [String: Task<[Float], Never>] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("waves", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func cached(_ raw: String) -> [Float]? { memory[raw] }

    private func file(_ raw: String) -> URL {
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex: String = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(String(hex.prefix(32)) + ".wave")
    }

    func load(_ raw: String, url: URL?, mime: String?) async -> [Float] {
        if let c = memory[raw] { return c }
        if let t = tasks[raw] { return await t.value }
        let path = file(raw)
        let t = Task<[Float], Never> {
            if raw.hasPrefix("fixture:") { return WaveCache.pseudo(raw) }
            if let data = try? Data(contentsOf: path), data.count == wavePointCount {
                let saved: [Float] = data.map { (b: UInt8) -> Float in Float(b) / 255 }
                return saved
            }
            guard let url, let data = try? await API.download(url) else { return WaveCache.pseudo(raw) }
            let ext: String = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            guard (try? data.write(to: tmp)) != nil else { return WaveCache.pseudo(raw) }
            let peaks: [Float]? = await Task.detached(priority: .utility) { () -> [Float]? in
                await wavePeaks(tmp, mime: mime, points: wavePointCount)
            }.value
            try? FileManager.default.removeItem(at: tmp)
            // формат не читается (ogg/opus) — запомнить ровную волну, чтобы не качать файл снова
            let result: [Float] = peaks ?? WaveCache.pseudo(raw)
            let bytes: [UInt8] = result.map { (v: Float) -> UInt8 in UInt8(max(0, min(255, (v * 255).rounded()))) }
            try? Data(bytes).write(to: path)
            return result
        }
        tasks[raw] = t
        let wave = await t.value
        tasks[raw] = nil
        memory[raw] = wave
        return wave
    }

    /// «Речевая» волна без файла: стабильна для одного и того же сообщения.
    nonisolated static func pseudo(_ seed: String) -> [Float] {
        var h: UInt64 = 1469598103934665603
        for b in seed.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        var out: [Float] = []
        out.reserveCapacity(wavePointCount)
        for i in 0..<wavePointCount {
            h = h &* 6364136223846793005 &+ 1442695040888963407
            let rnd: Float = Float((h >> 33) % 1000) / 1000
            let phrase: Float = 0.55 + 0.45 * Float(abs(sin(Double(i) / 5.3)))
            out.append(max(0.08, min(1, rnd * phrase)))
        }
        return out
    }

    /// Значение волны для столбика i из count (растяжение/сжатие 64 точек под ширину пузыря).
    nonisolated static func level(_ wave: [Float], _ i: Int, _ count: Int) -> Float {
        guard !wave.isEmpty, count > 0 else { return 0.1 }
        let pos: Int = min(wave.count - 1, i * wave.count / count)
        return wave[pos]
    }
}

/// Пики громкости файла (моно 16 бит 8 кГц), нормированные к 0…1. nil — формат не читается.
func wavePeaks(_ file: URL, mime: String?, points: Int) async -> [Float]? {
    var opts: [String: Any] = [:]
    if let mime, !mime.isEmpty { opts[AVURLAssetOverrideMIMETypeKey] = mime }
    let asset = AVURLAsset(url: file, options: opts)
    guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first else { return nil }
    guard let reader = try? AVAssetReader(asset: asset) else { return nil }
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 8000
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    guard reader.startReading() else { return nil }
    var peaks: [Float] = []
    var cur: Float = 0
    var n: Int = 0
    while let sb = output.copyNextSampleBuffer() {
        guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
        let len: Int = CMBlockBufferGetDataLength(bb)
        guard len >= 2 else { continue }
        var samples = [Int16](repeating: 0, count: len / 2)
        let status: OSStatus = samples.withUnsafeMutableBytes { (p: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let base = p.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: (len / 2) * 2, destination: base)
        }
        guard status == kCMBlockBufferNoErr else { continue }
        for s in samples {
            let v: Float = Float(abs(Int32(s))) / 32768
            if v > cur { cur = v }
            n += 1
            if n == 400 {
                peaks.append(cur)
                cur = 0
                n = 0
            }
        }
    }
    if n > 0 { peaks.append(cur) }
    guard reader.status == .completed, !peaks.isEmpty else { return nil }
    // сжать до points, максимум по корзине
    var out: [Float] = []
    out.reserveCapacity(points)
    for k in 0..<points {
        let a: Int = k * peaks.count / points
        let b: Int = max(a + 1, (k + 1) * peaks.count / points)
        let slice = peaks[min(a, peaks.count - 1)..<min(b, peaks.count)]
        out.append(slice.max() ?? 0)
    }
    let top: Float = max(0.0001, out.max() ?? 1)
    let norm: [Float] = out.map { (v: Float) -> Float in max(0.06, min(1, v / top)) }
    return norm
}

/// Голосовое в ленте, как в Telegram: крупная кнопка, волна на всю ширину, длительность и скорость,
/// «→A» справа вверху, время и галочки справа внизу, текст расшифровки под волной.
struct AudioBubble: View {
    @Environment(Store.self) private var store
    let url: URL?
    let raw: String
    let out: Bool
    let message: Message
    /// время и галочки внутри пузыря (когда у сообщения нет текста)
    var showTime: Bool = false
    var mime: String? = nil
    /// волна и длительность из данных сообщения (сервер); нет — считаем по файлу или берём запасную
    var serverWave: [Double]? = nil
    var serverDuration: Double? = nil
    @AppStorage("voiceRate") private var rate: Double = 1
    @State private var rateOverride: Double? = nil
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    @State private var observer: Any?
    @State private var tr = TranscriptModel()
    @State private var wave: [Float] = []

    private var fg: Color { out ? Pal.ink : .white }
    private var curRate: Double { rateOverride ?? rate }
    private var transcript: Transcript? { message.transcript ?? store.transcripts[message.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                playButton
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        waveView
                        TranscribeButton(out: out, loading: tr.loading, expanded: tr.expanded) { Task { await toggleTranscript() } }
                    }
                    infoRow
                }
            }
            if tr.expanded, let t = transcript {
                Text(TranscriptModel.text(t))
                    .font(Typo.body(15))
                    .foregroundStyle(fg.opacity(t.text.isEmpty ? 0.6 : 0.95))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 4)
                    .padding(.bottom, showTime ? 0 : 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 6).padding(.trailing, 6).padding(.top, 6).padding(.bottom, showTime ? 2 : 6)
        .frame(width: ChatLayout.voiceWidth - 8, alignment: .leading)
        .task(id: raw) {
            if let sw = serverWave, !sw.isEmpty {
                // волна пришла в данных сообщения: файл целиком не качаем
                wave = sw.map { (v: Double) -> Float in Float(max(0.06, min(1, v / 31))) }
                if let d = serverDuration, d > 0 { duration = d } else { await loadDuration() }
                return
            }
            if let c = WaveCache.shared.cached(raw) { wave = c } else { wave = WaveCache.pseudo(raw) }
            await loadDuration()
            let real = await WaveCache.shared.load(raw, url: url, mime: mime)
            withAnimation(.easeOut(duration: 0.25)) { wave = real }
        }
        .onAppear(perform: applyFixture)
        .onReceive(NotificationCenter.default.publisher(for: .sguardoMediaPlay)) { n in
            if (n.object as? String) != message.id, playing { player?.pause(); playing = false }
        }
        .onDisappear {
            player?.pause()
            playing = false
            if let observer { player?.removeTimeObserver(observer) }
            observer = nil
        }
    }

    private var playButton: some View {
        Button { toggle() } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 19, weight: .semibold))
                .offset(x: playing ? 0 : 1.5)
                .foregroundStyle(out ? Pal.acc : Pal.ink)
                .frame(width: 46, height: 46)
                .background(Circle().fill(out ? Pal.ink : Color.white))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(playing ? String(localized: "Пауза") : String(localized: "Слушать голосовое"))
    }

    private var waveView: some View {
        GeometryReader { g in
            let w: CGFloat = g.size.width
            waveBars(width: w)
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { p in
                    seek(to: Double(p.x / max(1, w)))
                }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    private func waveBars(width: CGFloat) -> some View {
        let barW: CGFloat = 2.5
        let gap: CGFloat = 1.6
        let count: Int = max(8, Int((width + gap) / (barW + gap)))
        let levels: [Float] = wave
        let shown: Double = progress
        return HStack(alignment: .center, spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                let v: CGFloat = CGFloat(WaveCache.level(levels, i, count))
                let played: Bool = (Double(i) + 0.5) / Double(count) <= shown
                Capsule()
                    .fill(fg)
                    .frame(width: barW, height: 3 + v * 21)
                    .opacity(played ? 1 : 0.38)
            }
        }
        .frame(width: width, height: 26, alignment: .leading)
    }

    private var infoRow: some View {
        HStack(spacing: 6) {
            Text(timeLabel).font(Typo.body(12)).monospacedDigit().foregroundStyle(fg.opacity(0.62))
            if playing || curRate != 1 { rateButton }
            Spacer(minLength: 4)
            if showTime {
                HStack(spacing: 3) {
                    Text(Fmt.hm(message.date)).font(Typo.body(11))
                    if out { SentMark(size: 10) }
                }
                .foregroundStyle(fg.opacity(0.62))
            }
        }
        .frame(height: 18)
    }

    private var rateButton: some View {
        Button {
            let next: Double = Double(VoiceRate.next(Float(curRate)))
            if rateOverride != nil { rateOverride = next } else { rate = next }
            haptic()
            if playing { player?.rate = Float(next) }
        } label: {
            Text(VoiceRate.label(Float(curRate)))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(fg.opacity(0.85))
                .padding(.horizontal, 6).frame(height: 18)
                .background(Capsule().fill(fg.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .accessibilityLabel("Скорость \(VoiceRate.label(Float(curRate)))")
    }

    private var timeLabel: String {
        if duration <= 0 { return String(localized: "голосовое") }
        return playing || progress > 0 ? durationText(progress * duration) : durationText(duration)
    }

    private func toggleTranscript() async {
        if tr.expanded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tr.expanded = false }
            return
        }
        if transcript == nil {
            tr.loading = true
            let t = await store.transcribe(message.id)
            tr.loading = false
            guard t != nil else { return }
        }
        haptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tr.expanded = true }
        NotificationCenter.default.post(name: .sguardoBubbleGrew, object: message.id)
    }

    private func loadDuration() async {
        if raw.hasPrefix("fixture:") { duration = 42; return }
        guard duration <= 0, let url else { return }
        let asset = AVURLAsset(url: url, options: API.assetOptions(for: url))
        if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 0 { duration = d.seconds }
    }

    private func applyFixture() {
        #if DEBUG
        guard store.fixture, !message.isOut else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-transcript"), message.transcript != nil {
            tr.expanded = true
            NotificationCenter.default.post(name: .sguardoBubbleGrew, object: message.id)
        }
        if args.contains("-voiceplay"), message.transcript == nil {
            progress = 0.35
            rateOverride = 1.5
            playing = true
        }
        #endif
    }

    private func ensurePlayer() {
        guard player == nil, let url, !raw.hasPrefix("fixture:") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: API.assetOptions(for: url)))
        item.audioTimePitchAlgorithm = .timeDomain
        let p = AVPlayer(playerItem: item)
        player = p
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
            Task { @MainActor in
                let d: Double = p.currentItem?.duration.seconds ?? 0
                if d.isFinite && d > 0 {
                    duration = d
                    progress = min(1, t.seconds / d)
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in
                playing = false
                progress = 0
                player?.seek(to: .zero)
            }
        }
    }

    private func start() {
        NotificationCenter.default.post(name: .sguardoMediaPlay, object: message.id)
        player?.playImmediately(atRate: Float(curRate))
        withAnimation(.easeOut(duration: 0.2)) { playing = true }
    }

    private func toggle() {
        guard url != nil, !raw.hasPrefix("fixture:") else { return }
        ensurePlayer()
        if playing {
            player?.pause()
            withAnimation(.easeOut(duration: 0.2)) { playing = false }
        } else {
            start()
        }
    }

    /// Тап по волне — перемотка (как в Telegram).
    private func seek(to f: Double) {
        let x: Double = min(1, max(0, f))
        if raw.hasPrefix("fixture:") { progress = x; return }
        ensurePlayer()
        guard let player else { return }
        progress = x
        if duration > 0 { player.seek(to: CMTime(seconds: x * duration, preferredTimescale: 600)) }
        if !playing { start() }
    }
}

extension Notification.Name {
    /// Началось проигрывание голосового/кружка: остальные в ленте встают на паузу.
    static let sguardoMediaPlay = Notification.Name("sguardoMediaPlay")
    /// Пузырь вырос (раскрыта расшифровка): лента докручивает, если это последнее сообщение.
    static let sguardoBubbleGrew = Notification.Name("sguardoBubbleGrew")
}

// MARK: - первый кадр кружка

/// Первый кадр видео (AVAssetImageGenerator): кэш в памяти и на диске (Caches/notes), чтобы лента не качала видео заново.
@MainActor
final class ThumbCache {
    static let shared = ThumbCache()
    private let memory = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    func cached(_ raw: String) -> UIImage? { memory.object(forKey: raw as NSString) }

    private func file(_ raw: String) -> URL {
        let digest = SHA256.hash(data: Data(raw.utf8))
        let hex: String = digest.map { String(format: "%02x", $0) }.joined()
        let name: String = String(hex.prefix(32)) + ".jpg"
        return dir.appendingPathComponent(name)
    }

    func load(_ raw: String) async -> UIImage? {
        if let c = cached(raw) { return c }
        if let t = tasks[raw] { return await t.value }
        let path = file(raw)
        let t = Task<UIImage?, Never> {
            if raw.hasPrefix("fixture:") { return fixtureNoteImage() }
            if let data = try? Data(contentsOf: path), let img = UIImage(data: data) { return img }
            guard let url = API.media(raw) else { return nil }
            let asset = AVURLAsset(url: url, options: API.assetOptions(for: url))
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 480, height: 480)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            guard let cg = try? await gen.image(at: CMTime(seconds: 0.05, preferredTimescale: 600)).image else { return nil }
            let img = UIImage(cgImage: cg)
            if let jpg = img.jpegData(compressionQuality: 0.8) { try? jpg.write(to: path) }
            return img
        }
        tasks[raw] = t
        let img = await t.value
        tasks[raw] = nil
        if let img { memory.setObject(img, forKey: raw as NSString) }
        return img
    }
}

/// Кадр-заглушка для снимков CI: «лицо» на градиенте (в симуляторе нет камеры и сети).
func fixtureNoteImage() -> UIImage {
    let size = CGSize(width: 480, height: 480)
    return UIGraphicsImageRenderer(size: size).image { ctx in
        let c = ctx.cgContext
        let colors: CFArray = [UIColor(red: 0.95, green: 0.78, blue: 0.66, alpha: 1).cgColor, UIColor(red: 0.42, green: 0.36, blue: 0.62, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        UIColor(red: 0.98, green: 0.86, blue: 0.76, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 150, y: 110, width: 180, height: 210))
        UIColor(red: 0.25, green: 0.2, blue: 0.3, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 140, y: 80, width: 200, height: 110))
        c.fillEllipse(in: CGRect(x: 90, y: 330, width: 300, height: 260))
    }
}

/// Плеер в круге (AVPlayerLayer).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class V: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> V {
        let v = V()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: V, context: Context) { uiView.playerLayer.player = player }
}

// MARK: - кружок в ленте

/// Кружок как в Telegram iOS: без пузыря, у стороны отправителя, ≈0.62 ширины экрана.
/// Внизу слева — капсулы длительности и «→A», по центру — значок звука, справа — время с галочками.
/// Тап — играет прямо в круге со звуком (тонкое белое кольцо прогресса), повторный тап — пауза.
struct RoundNoteBubble: View {
    @Environment(Store.self) private var store
    let raw: String
    let out: Bool
    let message: Message
    var onOpen: () -> Void = {}
    @State private var thumb: UIImage?
    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    @State private var observer: Any?
    @State private var tr = TranscriptModel()

    private var transcript: Transcript? { message.transcript ?? store.transcripts[message.id] }

    var body: some View {
        VStack(alignment: out ? .trailing : .leading, spacing: 4) {
            noteBlock
            if tr.expanded, let t = transcript {
                transcriptBubble(t)
            }
        }
        .task(id: raw) {
            thumb = await ThumbCache.shared.load(raw)
            await loadDuration()
        }
        .onAppear(perform: applyFixture)
        .onReceive(NotificationCenter.default.publisher(for: .sguardoMediaPlay)) { n in
            if (n.object as? String) != message.id, playing { player?.pause(); playing = false }
        }
        .onDisappear {
            player?.pause()
            playing = false
            if let observer { player?.removeTimeObserver(observer) }
            observer = nil
        }
    }

    /// Круг + капсулы в нижних углах его квадрата (там круг уже скруглился — капсулы не закрывают видео).
    private var noteBlock: some View {
        circle
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 5) {
                    Text(timeLabel)
                        .font(Typo.body(12, .semibold)).monospacedDigit()
                        .padding(.horizontal, 8).frame(height: 24)
                        .tgPill()
                    TranscribeButton(out: out, loading: tr.loading, expanded: tr.expanded, pill: true) { Task { await toggleTranscript() } }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 3) {
                    Text(Fmt.hm(message.date)).font(Typo.body(12, .medium)).monospacedDigit()
                    if out { SentMark(size: 10) }
                }
                .padding(.horizontal, 8).frame(height: 24)
                .tgPill()
                .accessibilityElement(children: .combine)
            }
    }

    private var circle: some View {
        let side: CGFloat = ChatLayout.noteSide
        let shown: Bool = playing || progress > 0
        return ZStack {
            LinearGradient(colors: [Pal.sky.opacity(0.45), Color(hex: 0xFFB8D6).opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let thumb {
                Image(uiImage: thumb).resizable().scaledToFill()
            }
            if let player, shown {
                PlayerLayerView(player: player)
            }
            if shown {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
            if !playing && progress > 0 {
                Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 50, height: 50).background(Circle().fill(Color.black.opacity(0.4)))
            }
            VStack {
                Spacer()
                Image(systemName: playing ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.42)))
                    .padding(.bottom, 10)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playing ? String(localized: "Кружок, пауза") : String(localized: "Кружок, смотреть"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: String(localized: "Открыть на весь экран")) { onOpen() }
    }

    /// Расшифровка — отдельным пузырём под кругом, цвета как у текстовых пузырей.
    private func transcriptBubble(_ t: Transcript) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: out ? 18 : 6, bottomTrailingRadius: out ? 6 : 18, topTrailingRadius: 18, style: .continuous)
        let fg: Color = out ? Pal.ink : .white
        return Text(TranscriptModel.text(t))
            .font(Typo.body(15))
            .foregroundStyle(fg.opacity(t.text.isEmpty ? 0.6 : 1))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if out {
                    shape.fill(Pal.acc)
                } else {
                    shape.fill(Color.white.opacity(0.13))
                        .background(shape.fill(.ultraThinMaterial))
                        .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                }
            }
            .frame(maxWidth: ChatLayout.noteTextWidth, alignment: out ? .trailing : .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var timeLabel: String {
        if duration <= 0 { return "0:00" }
        return playing || progress > 0 ? durationText(max(0, duration - progress * duration)) : durationText(duration)
    }

    private func loadDuration() async {
        if raw.hasPrefix("fixture:") { duration = message.isOut ? 28 : 57; return }
        guard duration <= 0, let url = API.media(raw) else { return }
        let asset = AVURLAsset(url: url, options: API.assetOptions(for: url))
        if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 0 { duration = d.seconds }
    }

    private func toggleTranscript() async {
        if tr.expanded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tr.expanded = false }
            return
        }
        if transcript == nil {
            tr.loading = true
            let t = await store.transcribe(message.id)
            tr.loading = false
            guard t != nil else { return }
        }
        haptic()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tr.expanded = true }
        NotificationCenter.default.post(name: .sguardoBubbleGrew, object: message.id)
    }

    private func applyFixture() {
        #if DEBUG
        guard store.fixture else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-noteplay"), message.isOut {
            progress = 0.42
            playing = true
        }
        if args.contains("-transcript"), message.transcript != nil {
            tr.expanded = true
        }
        #endif
    }

    private func toggle() {
        guard !raw.hasPrefix("fixture:"), let url = API.media(raw) else { return }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let item = AVPlayerItem(asset: AVURLAsset(url: url, options: API.assetOptions(for: url)))
            let p = AVPlayer(playerItem: item)
            player = p
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { t in
                Task { @MainActor in
                    let d: Double = p.currentItem?.duration.seconds ?? 0
                    if d.isFinite && d > 0 {
                        duration = d
                        progress = min(1, t.seconds / d)
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                Task { @MainActor in
                    playing = false
                    progress = 0
                    player?.seek(to: .zero)
                }
            }
        }
        if playing {
            player?.pause()
        } else {
            NotificationCenter.default.post(name: .sguardoMediaPlay, object: message.id)
            player?.play()
        }
        haptic()
        playing.toggle()
    }
}
