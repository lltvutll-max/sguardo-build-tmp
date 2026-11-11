import SwiftUI
import UIKit
import LocalAuthentication

@main
struct SguardoApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if store.phase == .ready && !store.accountDeleted {
                            Task { await store.loadState() }
                            store.startLive()
                        }
                    case .background:
                        store.stopLive()
                        store.commitPendingRead()
                        // в фоне блокируем всегда, даже посреди проверки Face ID
                        if store.authenticating { store.wentBackground = true }
                        if store.faceOn && store.phase == .ready { store.lock() }
                    case .inactive:
                        // закрыть содержимое и для снимка в переключателе приложений;
                        // .inactive от системного окна Face ID при включении/выключении — не блокируем
                        if store.faceOn && store.phase == .ready && !store.authenticating { store.lock() }
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    private var prefs: Prefs { Prefs.shared }
    private var net: NetMonitor { NetMonitor.shared }

    private var offline: Bool { store.phase != .launching && (prefs.forceOffline || !net.online) }
    private var onboarding: Bool { store.phase == .ready && !store.locked && (!prefs.onboardDone || prefs.showOnboarding) }

    /// Открыт чат: он всегда тёмный, поэтому и окно (строка состояния, клавиатура) — тёмное.
    private var chatOnTop: Bool {
        guard store.phase == .ready else { return false }
        let path: [Route]
        switch store.tab {
        case .chats: path = store.chatsPath
        case .today: path = store.todayPath
        case .summary: path = store.summaryPath
        case .profile: path = store.profilePath
        }
        if let last = path.last, case .chat = last { return true }
        return false
    }

    var body: some View {
        // значение берём здесь, а не внутри transform: замыкание может быть @Sendable (не на главном акторе)
        let forcedDynamic: DynamicTypeSize? = prefs.fixtureDynamic
        ZStack {
            Pal.page.ignoresSafeArea()
            switch store.phase {
            case .launching:
                ZStack {
                    WallpaperView(wall: store.wall)
                    ProgressView().tint(Pal.fg)
                }
                .transition(.opacity)
            case .login:
                LoginView()
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 1.04))))
            case .ready:
                MainView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if onboarding {
                OnboardingView().transition(.opacity).zIndex(4)
            }
            if store.locked && store.phase == .ready {
                LockView().transition(.opacity).zIndex(5)
            }
            ToastView().zIndex(10)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if offline {
                OfflineBanner().transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.phase)
        .animation(.easeInOut(duration: 0.25), value: store.locked)
        .animation(.easeInOut(duration: 0.3), value: offline)
        .preferredColorScheme(chatOnTop ? ColorScheme.dark : prefs.colorScheme)
        .transformEnvironment(\.dynamicTypeSize) { (d: inout DynamicTypeSize) in
            if let f = forcedDynamic { d = f }
        }
        .onAppear { prefs.applyWindowStyle() }
        .onChange(of: prefs.theme) { _, _ in prefs.applyWindowStyle() }
        .onChange(of: chatOnTop) { _, on in
            // вернуть тему приложения после чата (preferredColorScheme(nil) сам системную не возвращает)
            if !on { DispatchQueue.main.async { Prefs.shared.applyWindowStyle() } }
        }
    }
}

struct MainView: View {
    @Environment(Store.self) private var store

    /// разовая подсказка по списку чатов: после экранов обучения, пока не нажали «Понятно»/«Пропустить»
    private var showChatsCoach: Bool {
        let p: Prefs = Prefs.shared
        return store.tab == .chats && store.chatsPath.isEmpty && !store.chatSelecting && p.onboardDone && !p.showOnboarding && !p.seen("chats")
    }

    var body: some View {
        @Bindable var store = store
        ZStack(alignment: .bottom) {
            Group {
                switch store.tab {
                case .chats:
                    NavigationStack(path: $store.chatsPath) { ChatsView().destinations() }
                case .today:
                    NavigationStack(path: $store.todayPath) { TodayView().destinations() }
                case .summary:
                    NavigationStack(path: $store.summaryPath) { SummaryView().destinations() }
                case .profile:
                    NavigationStack(path: $store.profilePath) { ProfileView().destinations() }
                }
            }
            if store.currentPathEmpty && !(store.tab == .chats && store.chatSelecting) {
                TabBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showChatsCoach {
                CoachOverlay(key: "chats", steps: CoachSteps.chats, start: Prefs.shared.coachStart).zIndex(3)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.currentPathEmpty)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.chatSelecting)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

extension View {
    func destinations() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .chat(let id): ChatScreen(convId: id)
                case .client(let id): ClientView(contactId: id)
                case .folders: FoldersView()
                case .outreach: OutreachView()
                case .partners: PartnerDestination()
                case .partnerLead(let p, let k): PartnerLeadView(partner: p, lead: k)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Чат всегда в тёмной теме (пузыри и обои рассчитаны на тёмный фон) + разовая подсказка по чату.
struct ChatScreen: View {
    let convId: String
    private var prefs: Prefs { Prefs.shared }

    var body: some View {
        ChatView(convId: convId)
            .environment(\.colorScheme, .dark)
            .environment(\.sgForceDark, true)
            .overlay {
                if prefs.onboardDone && !prefs.seen("chat") {
                    CoachOverlay(key: "chat", steps: CoachSteps.chat, start: prefs.coachStart)
                }
            }
            .onAppear { prefs.setMarkedUnread(convId, false) }
    }
}

struct TabBar: View {
    @Environment(Store.self) private var store
    @Namespace private var ns

    private let items: [(Tab, String, String)] = [
        (.chats, "bubble.left", String(localized: "Чаты")), (.today, "bell", String(localized: "Сегодня")), (.summary, "chart.bar", String(localized: "Сводка")), (.profile, "person", String(localized: "Профиль")),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                let on = store.tab == item.0
                Button {
                    if store.tab == item.0 {
                        // повторное нажатие — к корню вкладки
                        withAnimation { clearPath(item.0) }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { store.tab = item.0 }
                    }
                    haptic()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: on ? item.1 + ".fill" : item.1)
                            .font(.icon(21))
                        Text(item.2).font(Typo.body(12, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Pal.acc : Pal.fg.opacity(0.82))
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if on {
                            Capsule().fill(Pal.fg.opacity(0.16))
                                .overlay(Capsule().stroke(Pal.fg.opacity(0.25), lineWidth: 0.5))
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .overlay(alignment: .top) { badge(item.0) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab-" + item.0.rawValue)
                .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
        }
        .padding(4)
        .glass(.bar, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    @ViewBuilder private func badge(_ t: Tab) -> some View {
        let n = t == .chats ? store.totalUnread : (t == .today ? store.openReminders.filter { $0.date < Date().addingTimeInterval(86400) }.count : 0)
        if n > 0 {
            Text(n > 99 ? "99+" : "\(n)")
                .font(Typo.body(11, .semibold))
                .foregroundStyle(Pal.ink)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(t == .chats ? Pal.acc : Pal.rose))
                .offset(x: 12, y: 4)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func clearPath(_ t: Tab) {
        switch t {
        case .chats: store.chatsPath = []
        case .today: store.todayPath = []
        case .summary: store.summaryPath = []
        case .profile: store.profilePath = []
        }
    }
}

struct ToastView: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack {
            Spacer()
            if let t = store.toast {
                HStack(spacing: 8) {
                    Image(systemName: t.ok ? "checkmark" : "xmark")
                        .font(.icon(15, .bold))
                        .accessibilityHidden(true)
                        .foregroundStyle(t.ok ? Pal.mint : Pal.danger)
                    Text(t.text).font(Typo.body(15)).foregroundStyle(Pal.fg).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let undo = t.undo, !store.locked {
                        Button {
                            withAnimation { store.toast = nil }
                            haptic()
                            undo()
                        } label: {
                            Text("Отменить").font(Typo.body(15, .semibold)).foregroundStyle(Pal.acc)
                                .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("toast-undo")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glassRect(18)
                .padding(.horizontal, 12)
                .padding(.bottom, 96)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(t.id)
                .onTapGesture { withAnimation { store.toast = nil } }
            }
        }
        .allowsHitTesting(store.toast != nil && !store.locked)
    }
}

struct LockView: View {
    @Environment(Store.self) private var store
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            WallpaperView(wall: store.wall)
            VStack(spacing: 18) {
                Image("BrandIcon").resizable().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text("Sguardo").font(Typo.display(26)).foregroundStyle(Pal.fg)
                if let message {
                    Text(message).font(Typo.body(14)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).padding(.horizontal, 30)
                }
                Button { unlock() } label: {
                    Label("Войти по Face ID", systemImage: "faceid").font(Typo.body(16, .semibold))
                        .frame(maxWidth: 260).frame(height: 52).primaryFill()
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                Button { Task { await store.logout() } } label: {
                    Text("Войти заново (выйти из кабинета)").font(Typo.body(15, .medium)).foregroundStyle(Pal.acc).frame(height: 44)
                }
            }
        }
        .onAppear { unlock() }
    }

    /// Блокировка снимается только после успешной проверки; при любой ошибке экран остаётся.
    private func unlock() {
        guard !busy else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            message = String(localized: "Face ID и код-пароль недоступны на этом телефоне. Войди заново по почте.")
            return
        }
        busy = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Вход в кабинет Sguardo")) { ok, _ in
            Task { @MainActor in
                busy = false
                if ok { store.locked = false } else { message = String(localized: "Не получилось подтвердить — попробуй ещё раз") }
            }
        }
    }
}

// Свайп «назад» от края при скрытой навигационной панели.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
