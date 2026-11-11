import SwiftUI
import Network
import Observation
import UIKit

/// Локальные настройки интерфейса: тема, обучение (экраны первого запуска и разовые подсказки),
/// чаты, отмеченные «непрочитанными» (сервер такой отметки не знает — она только на этом телефоне).
/// В режиме снимков (-fixture) ничего не читает и не пишет в UserDefaults: снимки не влияют друг на друга.
@MainActor
@Observable
final class Prefs {
    static let shared = Prefs()

    /// "system" | "light" | "dark"
    var theme: String = "dark"
    var onboardDone = true
    var coachSeen: Set<String> = []
    var markedUnread: Set<String> = []
    /// показать обучение прямо сейчас (из «Как пользоваться»)
    var showOnboarding = false
    /// с какого шага открыть подсказку (для снимков)
    var coachStart = 0
    /// снимки: принудительно «нет сети»
    var forceOffline = false
    /// снимки: размер шрифта
    var fixtureDynamic: DynamicTypeSize?

    @ObservationIgnored private var fixture = false

    init() {
        #if DEBUG
        let args: [String] = ProcessInfo.processInfo.arguments
        if args.contains("-fixture") {
            fixture = true
            onboardDone = !args.contains("-onboard")
            coachSeen = ["chats", "chat"]
            if let i = args.firstIndex(of: "-coach"), i + 1 < args.count {
                switch args[i + 1] {
                case "chats1": coachSeen = ["chat"]; coachStart = 0
                case "chats2": coachSeen = ["chat"]; coachStart = 1
                case "chat": coachSeen = ["chats"]; coachStart = 0
                default: break
                }
            }
            if let i = args.firstIndex(of: "-theme"), i + 1 < args.count { theme = args[i + 1] }
            forceOffline = args.contains("-offline")
            if args.contains("-dynamic") { fixtureDynamic = .accessibility2 }
            return
        }
        #endif
        let d = UserDefaults.standard
        theme = d.string(forKey: "theme") ?? "dark"
        onboardDone = d.bool(forKey: "onboard.v1")
        coachSeen = Set(d.stringArray(forKey: "coach.v1") ?? [])
        markedUnread = Set(d.stringArray(forKey: "markedUnread") ?? [])
    }

    // MARK: тема

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "system": return nil
        default: return .dark
        }
    }

    var themeTitle: String {
        switch theme {
        case "light": return String(localized: "Светлая")
        case "system": return String(localized: "Как на iPhone")
        default: return String(localized: "Тёмная")
        }
    }

    func setTheme(_ t: String) {
        theme = t
        if !fixture { UserDefaults.standard.set(t, forKey: "theme") }
        applyWindowStyle()
    }

    /// preferredColorScheme(nil) не всегда возвращает системную тему без перезапуска — ставим стиль окнам напрямую.
    func applyWindowStyle() {
        let style: UIUserInterfaceStyle
        switch theme {
        case "light": style = .light
        case "system": style = .unspecified
        default: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.overrideUserInterfaceStyle = style }
        }
    }

    // MARK: обучение

    func finishOnboarding() {
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardDone = true
            showOnboarding = false
        }
        if !fixture { UserDefaults.standard.set(true, forKey: "onboard.v1") }
    }

    func seen(_ key: String) -> Bool { coachSeen.contains(key) }

    func markSeen(_ key: String) {
        withAnimation(.easeInOut(duration: 0.25)) { _ = coachSeen.insert(key) }
        coachStart = 0
        if !fixture { UserDefaults.standard.set(Array(coachSeen), forKey: "coach.v1") }
    }

    /// «Как пользоваться»: заново экраны обучения и все подсказки на месте.
    func replayTutorial() {
        coachSeen = []
        coachStart = 0
        if !fixture {
            UserDefaults.standard.set([String](), forKey: "coach.v1")
            UserDefaults.standard.set(false, forKey: "onboard.v1")
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardDone = false
            showOnboarding = true
        }
    }

    // MARK: «непрочитано» на этом телефоне

    func isMarkedUnread(_ convId: String) -> Bool { markedUnread.contains(convId) }

    func setMarkedUnread(_ convId: String, _ on: Bool) {
        if on { markedUnread.insert(convId) } else { markedUnread.remove(convId) }
        if !fixture { UserDefaults.standard.set(Array(markedUnread), forKey: "markedUnread") }
    }

    func resetLocal() {
        markedUnread = []
        if !fixture { UserDefaults.standard.removeObject(forKey: "markedUnread") }
    }
}

/// Есть ли интернет (NWPathMonitor). Баннер «нет сети» сверху на всех экранах.
@MainActor
@Observable
final class NetMonitor {
    static let shared = NetMonitor()
    var online = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { path in
            let ok: Bool = path.status == .satisfied
            Task { @MainActor in
                NetMonitor.shared.online = ok
            }
        }
        monitor.start(queue: DispatchQueue(label: "sguardo.net"))
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.icon(14, .semibold))
            Text("Нет интернета — показываем последние данные. Отправка заработает, когда связь вернётся.")
                .font(Typo.body(13, .medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Pal.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0xFFD59E)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Пустой экран: что тут будет, почему пусто и что сделать.
struct EmptyState: View {
    let icon: String
    let title: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.icon(28, .regular))
                .foregroundStyle(Pal.fg2)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Pal.fg.opacity(0.08)))
                .accessibilityHidden(true)
            Text(title)
                .font(Typo.body(17, .semibold))
                .foregroundStyle(Pal.fg)
                .multilineTextAlignment(.center)
            Text(text)
                .font(Typo.body(15))
                .foregroundStyle(Pal.fg2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button { haptic(); action() } label: {
                    Text(actionTitle)
                        .font(Typo.body(15, .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(minHeight: 44)
                        .primaryFill(22)
                }
                .buttonStyle(PressStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

/// Экран всегда тёмный (чат): листы, открытые из него, тоже остаются тёмными.
private struct ForceDarkKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var sgForceDark: Bool {
        get { self[ForceDarkKey.self] }
        set { self[ForceDarkKey.self] = newValue }
    }
}
