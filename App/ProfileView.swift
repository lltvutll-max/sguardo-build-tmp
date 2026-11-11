import SwiftUI
import UIKit
import SafariServices

struct ProfileView: View {
    @Environment(Store.self) private var store
    @State private var showDelete = false
    @State private var confirmLogout = false
    @State private var webPage: HelpPage?

    private var planName: String {
        guard let acc = store.account else { return "—" }
        switch acc.plan ?? "free" {
        case "start": return String(localized: "Старт")
        case "team": return String(localized: "Команда")
        case "business": return String(localized: "Бизнес")
        case "free": return String(localized: "Пробный")
        default: return acc.plan ?? "—"
        }
    }

    @State private var modules: CabinetModules.Flags?

    /// «5 папок · 3 метки» вместо голой цифры.
    private var foldersSummary: String {
        let fc: Int = store.folders.count
        let f: String = String(localized: "\(fc) папок")
        let n: Int = store.labels.count
        return n > 0 ? f + " · " + String(localized: "\(n) меток") : f
    }

    var body: some View {
        let user = store.user
        let version: String = appVersion()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Профиль").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4)
                HStack(spacing: 14) {
                    Image("BrandIcon").resizable().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.account?.workspaceName.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Мой кабинет")).font(Typo.body(17, .semibold)).foregroundStyle(Pal.fg)
                        Text((user?.email ?? "") + " · " + (user?.isOwner == true ? String(localized: "владелец") : String(localized: "сотрудник"))).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(16)
                .glassRect(24)
                .padding(.top, 16)

                if canOutreach || canSeePartners {
                    Cap(String(localized: "Разделы кабинета"))
                    VStack(spacing: 0) {
                        if canOutreach {
                            navRow(first: true, icon: "paperplane", color: Pal.apricot, title: String(localized: "Рассылки"), value: outreachValue) { store.open(.outreach) }
                        }
                        if canSeePartners {
                            navRow(first: !canOutreach, icon: "chart.bar", color: Pal.teal, title: String(localized: "Партнёры"), value: "") { store.open(.partners) }
                        }
                    }
                    .glassRect(24)
                }

                Cap(String(localized: "Обои"))
                HStack(spacing: 8) {
                    ForEach(Wall.allCases, id: \.self) { w in
                        Button { store.setWall(w); haptic() } label: {
                            Text(w.title).font(Typo.body(14, .semibold))
                                .foregroundStyle(store.wall == w ? Pal.onAcc : Pal.fg)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background {
                                    if store.wall == w { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.acc) }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                    }
                }
                .padding(12)
                .glassRect(24)

                Cap(String(localized: "Подключённые аккаунты"))
                VStack(spacing: 0) {
                    if store.state.channels.isEmpty {
                        GroupRow(first: true) { Text("Пока ничего не подключено").foregroundStyle(Pal.fg2) }
                    }
                    ForEach(Array(store.state.channels.enumerated()), id: \.element.id) { i, ch in
                        let n = NetInfo.of(ch.type)
                        GroupRow(first: i == 0) {
                            Circle().fill(n.color).frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Pal.fg.opacity(ch.type == "threads" ? 0.5 : 0), lineWidth: 1))
                                .padding(.horizontal, 9)
                            Text(n.name).foregroundStyle(Pal.fg)
                            Spacer()
                            Text(ch.name.replacingOccurrences(of: "WhatsApp ", with: "")).foregroundStyle(Pal.fg2).lineLimit(1).frame(maxWidth: 170, alignment: .trailing)
                            Circle().fill(ch.status == "connected" ? Pal.mint : (ch.status == "error" ? Pal.danger : Pal.apricot)).frame(width: 8, height: 8)
                        }
                    }
                }
                .glassRect(24)
                Text("Новые аккаунты подключаются в веб-версии Sguardo.")
                    .font(Typo.body(13)).foregroundStyle(Pal.fg3).lineSpacing(3).padding(.horizontal, 16).padding(.top, 8)

                Cap(String(localized: "Кабинет"))
                VStack(spacing: 0) {
                    GroupRow(first: true) {
                        RowIcon(system: "sparkle", color: Pal.acc)
                        Text("Тариф").foregroundStyle(Pal.fg)
                        Spacer()
                        Text(planName).foregroundStyle(Pal.fg2)
                    }
                    navRow(first: false, icon: "folder", color: Pal.sky, title: String(localized: "Папки и метки"), value: foldersSummary) { store.open(.folders) }
                }
                .glassRect(24)

                Cap(String(localized: "Приложение"))
                VStack(spacing: 0) {
                    GroupRow(first: true) {
                        RowIcon(system: "bell", color: Pal.rose)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Уведомления").foregroundStyle(Pal.fg)
                            Text("о напоминаниях кабинета").font(Typo.body(13)).foregroundStyle(Pal.fg3)
                        }
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.pushOn }, set: { store.setPush($0) }))
                            .accessibilityLabel(String(localized: "Уведомления о напоминаниях"))
                            .accessibilityValue(store.pushOn ? Text("включены") : Text("выключены"))
                    }
                    aiRow
                    GroupRow {
                        RowIcon(system: "moon", color: Pal.lav)
                        Text("Тихие часы 23:00–08:00").foregroundStyle(Pal.fg)
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.quietOn }, set: { store.setQuiet($0) }))
                    }
                    GroupRow {
                        RowIcon(system: "faceid", color: Pal.mint)
                        Text("Вход по Face ID").foregroundStyle(Pal.fg)
                        Spacer()
                        GlassSwitch(isOn: Binding(get: { store.faceOn }, set: { store.requestFace($0) }))
                    }
                    Button {
                        haptic()
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        GroupRow {
                            RowIcon(system: "globe", color: Pal.apricot)
                            Text("Язык").foregroundStyle(Pal.fg)
                            Spacer()
                            Text(languageName).foregroundStyle(Pal.fg2)
                            Image(systemName: "chevron.right").font(.icon(13, .semibold)).foregroundStyle(Pal.fg3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("Откроются настройки приложения")
                    .accessibilityIdentifier("profile-language")
                    themeRow
                    Button {
                        haptic()
                        store.tab = .chats
                        store.chatsPath = []
                        Prefs.shared.replayTutorial()
                    } label: {
                        GroupRow {
                            RowIcon(system: "questionmark", color: Pal.sky)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Как пользоваться").foregroundStyle(Pal.fg)
                                Text("обучение и подсказки по жестам").font(Typo.body(13)).foregroundStyle(Pal.fg3)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.icon(13, .semibold)).foregroundStyle(Pal.fg3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityIdentifier("profile-howto")
                    linkRow(icon: "lifepreserver", color: Pal.teal, title: String(localized: "Поддержка"), url: API.supportURL, id: "profile-support")
                    linkRow(icon: "hand.raised", color: Pal.mint, title: String(localized: "Конфиденциальность"), url: API.privacyURL, id: "profile-privacy")
                }
                .glassRect(24)

                VStack(spacing: 0) {
                    Button { Task { await store.loadState(force: true); store.show(String(localized: "Обновлено")) } } label: {
                        GroupRow(first: true) {
                            Image(systemName: "arrow.clockwise").font(.icon(16))
                            Text("Обновить данные").font(Typo.body(16, .semibold))
                            Spacer()
                            if store.loading { ProgressView().tint(Pal.fg) }
                        }
                        .foregroundStyle(Pal.acc).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    Button { confirmLogout = true } label: {
                        GroupRow {
                            Text("Выйти").font(Typo.body(16, .semibold)); Spacer()
                        }
                        .foregroundStyle(Pal.acc).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    Button { showDelete = true } label: {
                        GroupRow {
                            Text("Удалить аккаунт").font(Typo.body(16, .semibold)); Spacer()
                        }
                        .foregroundStyle(Pal.danger).contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
                .glassRect(24)
                .padding(.top, 22)

                Text("Sguardo для iPhone · \(version)")
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                if let e = store.lastError {
                    Text("Связь: \(e)").font(Typo.body(12)).foregroundStyle(Pal.danger).frame(maxWidth: .infinity).padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 130)
        }
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-bottom") ? .bottom : .top)
        .refreshable { await store.loadState(force: true); await store.loadAccount() }
        .screenBackground(store.wall)
        .sheet(isPresented: $showDelete) { DeleteSheet() }
        .sheet(item: $webPage) { (p: HelpPage) in SafariView(url: p.url).ignoresSafeArea() }
        .confirmationDialog("Выйти из кабинета на этом телефоне?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await store.logout() } }
            Button("Отмена", role: .cancel) {}
        }
        .task {
            if store.fixture, let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen"),
               i + 1 < ProcessInfo.processInfo.arguments.count, ProcessInfo.processInfo.arguments[i + 1] == "profile-delete" {
                showDelete = true
            }
            if store.account == nil { await store.loadAccount() }
            if !store.fixture { modules = try? await API.get(CabinetModules.self, "/api/me/modules/").modules }
            if canOutreach && store.outreach == nil { await store.loadOutreach(quiet: true) }
        }
    }

    /// «Рассылки» видит любой владелец кабинета (сервер: modules.outreach = owner); в iOS 1.0 скрыты флагом AppFeatures.outreach.
    private var canOutreach: Bool {
        guard AppFeatures.outreach else { return false }
        return modules?.outreach ?? (store.user?.isOwner == true || store.user?.features?.outreach == true)
    }

    /// Согласие на перевод и расшифровку через сторонний ИИ: включить — через алерт, выключить — сразу.
    private var aiRow: some View {
        GroupRow {
            RowIcon(system: "globe", color: Pal.sky)
            VStack(alignment: .leading, spacing: 1) {
                Text("Перевод и расшифровка через ИИ").foregroundStyle(Pal.fg)
                Text("сообщения обрабатывают сторонние ИИ-сервисы — список в политике").font(Typo.body(13)).foregroundStyle(Pal.fg3)
            }
            Spacer()
            GlassSwitch(isOn: Binding(get: { store.aiConsent }, set: { (v: Bool) in store.setAIConsent(v) }))
                .accessibilityLabel(String(localized: "Перевод и расшифровка через ИИ"))
                .accessibilityValue(store.aiConsent ? Text("включены") : Text("выключены"))
        }
    }

    private var outreachValue: String {
        if store.outreachDenied != nil { return "" }
        guard let o = store.outreach else { return "" }
        let n: Int = o.auto?.left ?? 0
        return String(localized: "\(n) в очереди")
    }
    /// Текущий язык интерфейса (меняется в системных настройках приложения).
    private var languageName: String {
        let code: String = Bundle.main.preferredLocalizations.first ?? "ru"
        let name: String = uiLocale.localizedString(forLanguageCode: code) ?? code
        return name.capitalized(with: uiLocale)
    }
    private var canSeePartners: Bool { store.fixture || modules?.partners == true }

    private func navRow(first: Bool, icon: String, color: Color, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            GroupRow(first: first) {
                RowIcon(system: icon, color: color)
                Text(title).foregroundStyle(Pal.fg)
                Spacer()
                Text(value).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(1)
                Image(systemName: "chevron.right").font(.icon(13, .semibold)).foregroundStyle(Pal.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// Ссылка помощи: открывается внутри приложения (SFSafariViewController).
    private func linkRow(icon: String, color: Color, title: String, url: URL, id: String) -> some View {
        Button { haptic(); webPage = HelpPage(url: url) } label: {
            GroupRow {
                RowIcon(system: icon, color: color)
                Text(title).foregroundStyle(Pal.fg)
                Spacer()
                Image(systemName: "arrow.up.right").font(.icon(13, .semibold)).foregroundStyle(Pal.fg3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier(id)
    }

    /// Тема: как на iPhone / светлая / тёмная. Чат всегда тёмный (пузыри рассчитаны на тёмные обои).
    private var themeRow: some View {
        let prefs: Prefs = Prefs.shared
        return Menu {
            Picker("Тема", selection: Binding(get: { prefs.theme }, set: { (v: String) in prefs.setTheme(v) })) {
                Text("Как на iPhone").tag("system")
                Text("Светлая").tag("light")
                Text("Тёмная").tag("dark")
            }
        } label: {
            GroupRow {
                RowIcon(system: "circle.lefthalf.filled", color: Pal.lav)
                Text("Тема").foregroundStyle(Pal.fg)
                Spacer()
                Text(prefs.themeTitle).foregroundStyle(Pal.fg2)
                Image(systemName: "chevron.up.chevron.down").font(.icon(12, .semibold)).foregroundStyle(Pal.fg3)
            }
            .contentShape(Rectangle())
        }
        .tint(Pal.fg)
        .accessibilityLabel(String(localized: "Тема: \(prefs.themeTitle)"))
        .accessibilityIdentifier("profile-theme")
    }
}

/// Страница сайта для листа Safari.
struct HelpPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SFSafariViewController в SwiftUI: поддержка и политика открываются, не выходя из приложения.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

func appVersion() -> String {
    let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
    let short: String = info["CFBundleShortVersionString"] as? String ?? "1.0"
    let build: String = info["CFBundleVersion"] as? String ?? "1"
    return "\(short) (\(build))"
}

struct FoldersView: View {
    @Environment(Store.self) private var store
    @State private var names: [String: String] = [:]
    @State private var showLabel = false
    @State private var deleting: Folder?
    @State private var removingLabel: String?

    private func askRemove(_ l: String) {
        let used = store.state.contacts.contains { ($0.tags ?? []).contains(l) }
        if used { removingLabel = l } else { store.removeExtraLabel(l); store.show(String(localized: "Метка «\(l)» удалена")) }
    }

    /// Снять метку со всех клиентов (по одному действию на клиента) и из списка приложения.
    private func removeEverywhere(_ l: String) async {
        let owners = store.state.contacts.filter { ($0.tags ?? []).contains(l) }
        var failed = 0
        for c in owners {
            let tags: [String] = (c.tags ?? []).filter { $0 != l }
            let ok = await store.act(["type": "updateContact", "contactId": c.id, "tags": tags])
            if !ok { failed += 1 }
        }
        store.removeExtraLabel(l)
        if failed == 0 { let cnt: Int = owners.count; store.show(String(localized: "Метка «\(l)» снята у \(cnt) клиентов")) }
    }

    var body: some View {
        let owner = store.user?.isOwner == true
        VStack(spacing: 0) {
            HStack {
                CircleButton(system: "chevron.left", iconSize: 18) { commitNames(); store.pop() }
                Spacer()
                Button { commitNames(); store.pop() } label: {
                    Text("Готово").font(Typo.body(15, .semibold)).padding(.horizontal, 16).frame(height: 40).primaryFill(20)
                }
                .buttonStyle(PressStyle())
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Папки").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4).padding(.top, 14)
                    Text(owner ? String(localized: "Папка — этап сделки, у клиента она одна. Нажми на название, чтобы переименовать.") : String(localized: "Папки настраивает владелец кабинета."))
                        .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3).padding(.horizontal, 4).padding(.top, 8)
                    Cap(String(localized: "Мои папки"))
                    VStack(spacing: 0) {
                        ForEach(Array(store.folders.enumerated()), id: \.element.id) { i, f in
                            GroupRow(first: i == 0) {
                                Button { cycleColor(f) } label: {
                                    Circle().fill(Color(css: f.color)).frame(width: 22, height: 22)
                                }
                                .disabled(!owner)
                                TextField("", text: Binding(get: { names[f.id] ?? f.name }, set: { names[f.id] = $0 }))
                                    .font(Typo.body(16)).foregroundStyle(Pal.fg)
                                    .disabled(!owner)
                                    .submitLabel(.done)
                                    .onSubmit { commit(f) }
                                Text("\(store.state.contacts.filter { $0.folderId == f.id }.count)").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                                if owner {
                                    Button { Task { await store.act(["type": "moveFolder", "id": f.id, "dir": -1]) } } label: {
                                        Image(systemName: "chevron.up").font(.system(size: 15, weight: .semibold)).frame(width: 36, height: 44)
                                    }
                                    .accessibilityLabel(String(localized: "Поднять папку «\(f.name)» выше"))
                                    .foregroundStyle(Pal.fg.opacity(i == 0 ? 0.2 : 0.7))
                                    .disabled(i == 0)
                                    Button { deleting = f } label: {
                                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 44)
                                    }
                                    .accessibilityLabel(String(localized: "Удалить папку «\(f.name)»"))
                                    .foregroundStyle(Pal.fg.opacity(0.55))
                                }
                            }
                        }
                        if owner {
                            Button { Task { await store.act(["type": "addFolder", "name": String(localized: "Новая папка"), "color": "#C9CEFF"], ok: String(localized: "Папка добавлена")) } } label: {
                                GroupRow {
                                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                                    Text("Новая папка").font(Typo.body(16, .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Pal.acc).contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)
                    .buttonStyle(PressStyle())

                    Cap(String(localized: "Метки"))
                    FlowLayout(spacing: 8) {
                        ForEach(store.labels, id: \.self) { l in
                            HStack(spacing: 4) {
                                Text(l).font(Typo.body(13, .semibold))
                                Button { askRemove(l) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 20, height: 20) }
                                    .accessibilityLabel("Удалить метку \(l)")
                            }
                            .foregroundStyle(Pal.ink)
                            .padding(.leading, 14).padding(.trailing, 6)
                            .frame(height: 32)
                            .background(Capsule().fill(labelColor(l)))
                        }
                        Button { showLabel = true } label: {
                            Text("+ Метка").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg)
                                .padding(.horizontal, 14).frame(height: 32)
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Pal.fg.opacity(0.4)))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassRect(24)
                    Text("Снять метку с одного клиента — крестик на метке в чате или нажатие в карточке. Крестик здесь удаляет метку у всех клиентов.")
                        .font(Typo.body(13)).foregroundStyle(Pal.fg3).lineSpacing(3).padding(.horizontal, 16).padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .screenBackground(store.wall)
        .sheet(isPresented: $showLabel) { LabelSheet(contactId: nil) }
        .confirmationDialog("Удалить метку «\(removingLabel ?? "")» у всех клиентов?", isPresented: Binding(get: { removingLabel != nil }, set: { if !$0 { removingLabel = nil } }), titleVisibility: .visible) {
            if let l = removingLabel {
                Button("Удалить у всех", role: .destructive) {
                    removingLabel = nil
                    Task { await removeEverywhere(l) }
                }
            }
            Button("Отмена", role: .cancel) { removingLabel = nil }
        }
        .confirmationDialog("Удалить папку «\(deleting?.name ?? "")»?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let f = deleting, let to = store.folders.first(where: { $0.id != f.id }) {
                Button("Удалить, клиентов — в «\(to.name)»", role: .destructive) {
                    Task { await store.act(["type": "removeFolder", "id": f.id, "moveTo": to.id], ok: String(localized: "Папка удалена, клиенты — в «\(to.name)»")) }
                    deleting = nil
                }
            }
            Button("Отмена", role: .cancel) { deleting = nil }
        }
    }

    private func commit(_ f: Folder) {
        guard let n = names[f.id]?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n != f.name else { return }
        Task { await store.act(["type": "updateFolder", "id": f.id, "name": String(n.prefix(60))], ok: String(localized: "Переименовано")) }
    }

    private func commitNames() {
        for f in store.folders { commit(f) }
    }

    private func cycleColor(_ f: Folder) {
        let pal = Pal.folderHex
        let i = pal.firstIndex(of: (f.color ?? "").uppercased()) ?? -1
        let next = pal[(i + 1) % pal.count]
        Task { await store.act(["type": "updateFolder", "id": f.id, "color": next]) }
    }
}
