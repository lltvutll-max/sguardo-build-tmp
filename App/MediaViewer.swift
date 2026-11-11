import SwiftUI
import UIKit
import AVKit
import Photos
import UniformTypeIdentifiers

// MARK: - загрузка картинок

/// Картинки переписки: свой загрузчик вместо AsyncImage — кэш в памяти (лента не перезагружает фото при прокрутке)
/// и та же политика кук, что у файлов: свой хост — с сессией, чужой — без кук (API.download).
@MainActor
final class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    init() { cache.totalCostLimit = 80 * 1024 * 1024 }

    func cached(_ raw: String) -> UIImage? { cache.object(forKey: raw as NSString) }

    func load(_ raw: String) async -> UIImage? {
        if let c = cached(raw) { return c }
        if let t = tasks[raw] { return await t.value }
        let t = Task<UIImage?, Never> {
            if raw.hasPrefix("fixture:") { return fixtureImage(raw) }
            guard let url = API.media(raw), let data = try? await API.download(url) else { return nil }
            guard let img = UIImage(data: data) else { return nil }
            return img.preparingForDisplay() ?? img
        }
        tasks[raw] = t
        let img = await t.value
        tasks[raw] = nil
        if let img {
            let cost: Int = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
            cache.setObject(img, forKey: raw as NSString, cost: cost)
        }
        return img
    }

    func clear() {
        cache.removeAllObjects()
        for t in tasks.values { t.cancel() }
        tasks = [:]
    }
}

/// Картинка для снимков CI (`-fixture`): градиент без сети.
func fixtureImage(_ raw: String) -> UIImage {
    let size = CGSize(width: 900, height: 1200)
    let seed: Int = abs(raw.hashValue % 360)
    return UIGraphicsImageRenderer(size: size).image { ctx in
        let c1 = UIColor(hue: CGFloat(seed) / 360, saturation: 0.45, brightness: 0.95, alpha: 1)
        let c2 = UIColor(hue: CGFloat((seed + 60) % 360) / 360, saturation: 0.6, brightness: 0.55, alpha: 1)
        let colors: CFArray = [c1.cgColor, c2.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        UIColor.white.withAlphaComponent(0.35).setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 520, y: 160, width: 220, height: 220))
    }
}

struct RemoteImage: View {
    let raw: String
    var mode: ContentMode = .fill
    /// без индикатора и подписи (аватарки)
    var quiet = false
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: mode)
            } else if quiet {
                Color.clear
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 24))
                    Text("не загрузилось").font(Typo.body(12))
                }
                .foregroundStyle(Color.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: raw) {
            if image == nil { image = ImageLoader.shared.cached(raw) }
            guard image == nil else { return }
            let img = await ImageLoader.shared.load(raw)
            image = img
            failed = img == nil
        }
    }
}

// MARK: - полноэкранный просмотр

struct MediaItem: Identifiable, Hashable {
    let id: String
    let raw: String
    let kind: String
    let name: String
    let round: Bool
    let mime: String?

    var isVideo: Bool { kind == "video" }

    var fileExtension: String {
        if let mime, let ext = UTType(mimeType: mime)?.preferredFilenameExtension { return ext }
        return isVideo ? "mp4" : "jpg"
    }
}

struct ViewerState: Identifiable {
    let id = UUID()
    let items: [MediaItem]
    let start: Int
}

/// Фото и видео переписки: листание, зум щипком и двойным тапом, смахнуть вниз — закрыть, поделиться и сохранить.
struct MediaViewer: View {
    let items: [MediaItem]
    let onClose: () -> Void
    @Environment(Store.self) private var store
    @State private var index: Int
    @State private var zoomed = false
    @State private var drag: CGFloat = 0
    @State private var chrome = true
    @State private var share: URLBox?
    @State private var busy = false

    init(items: [MediaItem], start: Int, onClose: @escaping () -> Void) {
        self.items = items
        self.onClose = onClose
        _index = State(initialValue: min(max(0, start), max(0, items.count - 1)))
    }

    var body: some View {
        let progress: CGFloat = min(1, abs(drag) / 320)
        ZStack {
            Color.black.opacity(Double(1 - progress * 0.85)).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    page(item, active: i == index).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: drag)
            .scaleEffect(1 - progress * 0.12)
            .simultaneousGesture(dismissGesture, including: zoomed ? .subviews : .all)
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() } }
            if chrome {
                controls.opacity(Double(1 - progress)).transition(.opacity)
            }
        }
        .statusBarHidden(!chrome)
        .presentationBackground(.clear)
        .sheet(item: $share) { box in ShareSheet(items: [box.url]) }
        .onChange(of: index) { _, _ in zoomed = false }
    }

    @ViewBuilder private func page(_ item: MediaItem, active: Bool) -> some View {
        if item.isVideo {
            VideoPage(item: item, active: active)
        } else {
            ZoomPage(raw: item.raw, zoomed: $zoomed)
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                guard !zoomed, abs(v.translation.height) > abs(v.translation.width) else { return }
                drag = v.translation.height
            }
            .onEnded { v in
                guard !zoomed else { return }
                let fling: CGFloat = v.predictedEndTranslation.height
                if abs(drag) > 120 || abs(fling) > 420 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                }
            }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 10) {
                CircleButton(system: "xmark", iconSize: 16) { onClose() }
                    .accessibilityLabel("Закрыть")
                Spacer()
                if items.count > 1 {
                    Text("\(index + 1) из \(items.count)")
                        .font(Typo.body(14, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 36)
                        .glassCapsule()
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
            HStack(spacing: 14) {
                Button { Task { await prepareShare() } } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up").font(Typo.body(15, .semibold))
                        .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 46)
                }
                .buttonStyle(PressStyle())
                .glassCapsule(interactive: true)
                Button { Task { await save() } } label: {
                    Label("Сохранить", systemImage: "square.and.arrow.down").font(Typo.body(15, .semibold))
                        .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 46)
                }
                .buttonStyle(PressStyle())
                .glassCapsule(interactive: true)
            }
            .disabled(busy)
            .overlay { if busy { ProgressView().tint(.white) } }
            .padding(.bottom, 18)
        }
    }

    private var current: MediaItem? { items.indices.contains(index) ? items[index] : nil }

    /// Файл текущего фото/видео во временной папке (её чистит выход из аккаунта).
    private func localFile(_ item: MediaItem) async throws -> URL {
        let data: Data
        if item.raw.hasPrefix("fixture:") {
            data = fixtureImage(item.raw).jpegData(compressionQuality: 0.9) ?? Data()
        } else {
            guard let url = API.media(item.raw) else { throw APIError(status: 0, message: String(localized: "Файл недоступен")) }
            data = try await API.download(url)
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("sguardo-\(String(UUID().uuidString.prefix(6))).\(item.fileExtension)")
        try data.write(to: dest)
        return dest
    }

    private func prepareShare() async {
        guard let item = current else { return }
        busy = true
        defer { busy = false }
        do { share = URLBox(url: try await localFile(item)) } catch { store.show(friendly(error), ok: false) }
    }

    private func save() async {
        guard let item = current else { return }
        busy = true
        defer { busy = false }
        let status: PHAuthorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            store.show(String(localized: "Нет доступа к Фото — разреши в настройках iPhone"), ok: false)
            return
        }
        do {
            let file = try await localFile(item)
            let video = item.isVideo
            try await PHPhotoLibrary.shared().performChanges {
                if video {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: file)
                }
            }
            store.show(video ? String(localized: "Видео сохранено в Фото") : String(localized: "Фото сохранено"))
        } catch {
            store.show(String(localized: "Не получилось сохранить"), ok: false)
        }
    }
}

private struct ZoomPage: View {
    let raw: String
    @Binding var zoomed: Bool
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                ZoomableImage(image: image, zoomed: $zoomed)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 34))
                    Text("Фото не загрузилось").font(Typo.body(15))
                }
                .foregroundStyle(Color.white.opacity(0.7))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: raw) {
            if image == nil { image = ImageLoader.shared.cached(raw) }
            guard image == nil else { return }
            let img = await ImageLoader.shared.load(raw)
            image = img
            failed = img == nil
        }
    }
}

private struct VideoPage: View {
    let item: MediaItem
    let active: Bool
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: item.round ? 340 : .infinity, maxHeight: item.round ? 340 : .infinity)
                    .clipShape(item.round ? AnyShape(Circle()) : AnyShape(Rectangle()))
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard player == nil, let url = API.media(item.raw), !item.raw.hasPrefix("fixture:") else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url, options: API.assetOptions(for: url))))
            if active { player?.play() }
        }
        .onChange(of: active) { _, on in if on { player?.play() } else { player?.pause() } }
        .onDisappear { player?.pause() }
    }
}

/// Зум как в «Фото»: UIScrollView (щипок, двойной тап, инерция).
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(zoomed: $zoomed) }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.delegate = context.coordinator
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 5
        sv.bouncesZoom = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.backgroundColor = .clear
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor),
            iv.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor),
            iv.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor),
            iv.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = iv
        let dt = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        dt.numberOfTapsRequired = 2
        sv.addGestureRecognizer(dt)
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image { context.coordinator.imageView?.image = image }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var zoomed: Binding<Bool>
        weak var imageView: UIImageView?

        init(zoomed: Binding<Bool>) { self.zoomed = zoomed }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            let z: Bool = scrollView.zoomScale > 1.01
            let binding = zoomed
            if binding.wrappedValue != z { DispatchQueue.main.async { binding.wrappedValue = z } }
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            let z: Bool = scale > 1.01
            let binding = zoomed
            DispatchQueue.main.async { if binding.wrappedValue != z { binding.wrappedValue = z } }
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = g.view as? UIScrollView else { return }
            if sv.zoomScale > 1.01 {
                sv.setZoomScale(1, animated: true)
            } else {
                let p: CGPoint = g.location(in: imageView)
                let w: CGFloat = sv.bounds.width / 2.5
                let h: CGFloat = sv.bounds.height / 2.5
                sv.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
