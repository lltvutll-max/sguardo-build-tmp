import SwiftUI

/// «Рассылки»: живые данные /api/outreach — первое сообщение фирмам в WhatsApp владельца, по одной, с паузами и дневным лимитом.
/// Фирмы приходят из Повода (кнопка «в Sguardo») и из турецкого списка. Раздел видит любой владелец кабинета:
/// без оплаты сервер отвечает 402 («нужна оплата»), помощникам — 403 («доступно владельцу кабинета»).
struct OutreachView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var filter = "new"
    @State private var source = "all"
    @State private var selected: OutreachTarget?
    @State private var showSettings = false
    @State private var confirmClear = false
    @State private var confirmDelete: OutreachTarget?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: { settingsButton })
                .confirmationDialog(String(localized: "Убрать фирму из рассылки?"), isPresented: deleteShown, titleVisibility: .visible, presenting: confirmDelete) { (t: OutreachTarget) in
                    Button(String(localized: "Убрать «\(t.name)»"), role: .destructive) { remove(t) }
                    Button(String(localized: "Отмена"), role: .cancel) {}
                } message: { (_: OutreachTarget) in
                    Text("Ей ещё не писали. Передумаете — нажмите «Отменить» в течение 9 секунд.")
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .refreshable { await store.loadOutreach() }
            .confirmationDialog(String(localized: "Очистить очередь?"), isPresented: $confirmClear, titleVisibility: .visible) {
                clearButtons
            } message: {
                Text("Уберём фирмы, которым ещё не писали. Отправленные и ответившие останутся. Передумаете — нажмите «Отменить» в течение 9 секунд.")
            }
        }
        .screenBackground(store.wall)
        .task {
            await store.loadOutreach()
            await applyFixture()
        }
        .sheet(item: $selected) { (t: OutreachTarget) in OutreachTargetSheet(target: t) }
        .sheet(isPresented: $showSettings) { OutreachSettingsSheet() }
    }

    // MARK: - шапка и состояния экрана

    @ViewBuilder private var settingsButton: some View {
        if store.outreach != nil && store.outreachDenied == nil {
            CircleButton(system: "slider.horizontal.3", iconSize: 17, label: String(localized: "Настройки рассылки")) { showSettings = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Рассылки").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg)
            Text("Первое сообщение фирмам в WhatsApp — по одной, с паузами и дневным лимитом. Ответы приходят в обычные чаты.")
                .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
    }

    @ViewBuilder private var content: some View {
        if let d = store.outreachDenied {
            deniedView(d)
        } else if let data = store.outreach {
            loaded(data)
        } else if let err = store.outreachLoadError {
            EmptyState(icon: "exclamationmark.triangle", title: String(localized: "Рассылка не загрузилась"), text: err,
                       actionTitle: String(localized: "Повторить"), action: { Task { await store.loadOutreach() } })
        } else {
            ProgressView().tint(Pal.fg).frame(maxWidth: .infinity).padding(.top, 40)
        }
    }

    @ViewBuilder private func deniedView(_ d: OutreachDenied) -> some View {
        if d.needPay {
            EmptyState(icon: "creditcard", title: String(localized: "Нужна оплата"),
                       text: d.text.isEmpty ? String(localized: "Рассылка работает на оплаченном тарифе. Оплатите кабинет — и раздел откроется сам.") : d.text,
                       actionTitle: String(localized: "Открыть веб-кабинет"), action: { openURL(API.webCabinet) })
        } else {
            EmptyState(icon: "person.badge.key", title: String(localized: "Доступно владельцу кабинета"),
                       text: String(localized: "Рассылку настраивает и отправляет владелец кабинета. Если нужно добавить фирмы — попросите его."))
        }
    }

    @ViewBuilder private func loaded(_ data: OutreachList) -> some View {
        let all: [OutreachTarget] = visibleTargets
        if data.needWhatsApp == true {
            OutreachWhatsAppBanner().padding(.top, 16)
        }
        statusCard(data, all: all).padding(.top, 16)
        if all.isEmpty {
            EmptyState(icon: "paperplane", title: String(localized: "Пока некому писать"),
                       text: String(localized: "Добавьте компании из Повода: выберите их в списке и нажмите «в Sguardo»"))
        } else {
            listSection(all)
        }
    }

    /// фирмы с сервера без тех, что ждут удаления (тост с «Отменить»)
    private var visibleTargets: [OutreachTarget] {
        let hidden: Set<String> = store.outreachHidden
        return (store.outreach?.targets ?? []).filter { (t: OutreachTarget) in !hidden.contains(t.id) }
    }

    // MARK: - карточка состояния

    private func statusCard(_ data: OutreachList, all: [OutreachTarget]) -> some View {
        let on: Bool = data.auto?.on ?? false
        let sent: Int = all.filter { (t: OutreachTarget) in t.status == "sent" || t.status == "replied" }.count
        let replied: Int = all.filter { (t: OutreachTarget) in t.status == "replied" }.count
        let queued: Int = all.filter { (t: OutreachTarget) in t.status == "new" }.count
        let today: Int = data.quota?.sentToday ?? 0
        let limit: Int = data.quota?.limit ?? (data.settings?.dailyLimit ?? OutreachSettings.defaults.dailyLimit)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Автоотправка").font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg)
                Spacer()
                Text(on ? String(localized: "идёт") : String(localized: "пауза"))
                    .font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(on ? Pal.mint : Pal.apricot))
            }
            Text(quotaLine(data, today: today, limit: limit))
                .font(Typo.body(13)).foregroundStyle(Pal.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Bar(fraction: Double(today) / Double(max(1, limit)), color: Pal.acc, height: 6)
            HStack {
                stat("\(sent)", String(localized: "отправлено"))
                stat("\(replied)", String(localized: "ответили"), color: Pal.mint)
                stat("\(queued)", String(localized: "в очереди"))
            }
            settingsSummary(data.settings ?? OutreachSettings.defaults)
            if let reason = data.quota?.reason, data.quota?.ok == false {
                Text(reason).font(Typo.body(13)).foregroundStyle(Pal.apricot).fixedSize(horizontal: false, vertical: true)
            }
            if let stopped = data.auto?.stopped, !stopped.isEmpty {
                Text("Автоотправка остановилась: \(stopped)").font(Typo.body(13)).foregroundStyle(Pal.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            autoButton(on: on, blocked: data.needWhatsApp == true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassRect(24)
    }

    private func quotaLine(_ data: OutreachList, today: Int, limit: Int) -> String {
        var parts: [String] = []
        if let ch = data.channel, !ch.isEmpty { parts.append(ch) }
        parts.append(String(localized: "сегодня \(today) из \(limit)"))
        if data.auto?.on == true, let n = data.auto?.next, let d = parseISO(n) {
            parts.append(String(localized: "следующее в \(Fmt.hm(d))"))
        }
        return parts.joined(separator: " · ")
    }

    private func settingsSummary(_ st: OutreachSettings) -> some View {
        Button { showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock").font(.icon(14, .semibold)).foregroundStyle(Pal.fg2).accessibilityHidden(true)
                Text(OutreachFormat.summary(st))
                    .font(Typo.body(13)).foregroundStyle(Pal.fg)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("изменить").font(Typo.body(13, .semibold)).foregroundStyle(Pal.acc)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.fg.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(String(localized: "Настройки рассылки: \(OutreachFormat.summary(st))"))
    }

    private func autoButton(on: Bool, blocked: Bool) -> some View {
        Button {
            let next: Bool = !on
            Task {
                await store.outreachAction(["action": "auto", "on": next],
                                           ok: next ? String(localized: "Автоотправка включена") : String(localized: "Автоотправка на паузе"))
            }
        } label: {
            Text(on ? String(localized: "Поставить на паузу") : String(localized: "Включить автоотправку"))
                .font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
        .disabled(blocked && !on)
        .opacity(blocked && !on ? 0.5 : 1)
    }

    private func stat(_ v: String, _ l: String, color: Color = Pal.fg) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(Typo.display(16)).foregroundStyle(color)
            Text(l).font(Typo.body(13)).foregroundStyle(Pal.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - список

    @ViewBuilder private func listSection(_ all: [OutreachTarget]) -> some View {
        let hasPovod: Bool = all.contains { (t: OutreachTarget) in t.isPovod }
        let hasTr: Bool = all.contains { (t: OutreachTarget) in !t.isPovod }
        let shown: [OutreachTarget] = filtered(all, both: hasPovod && hasTr)
        let unsent: Int = all.filter { (t: OutreachTarget) in t.unsent }.count
        if hasPovod && hasTr {
            GlassSegment(items: [("all", String(localized: "Все")), ("tr-setup", String(localized: "Рассылка TR")), ("povod", String(localized: "Рассылка Повод"))],
                         selection: $source)
                .padding(.top, 14)
        }
        GlassSegment(items: [("new", String(localized: "В очереди")), ("sent", String(localized: "Ушло")), ("replied", String(localized: "Ответили")), ("all", String(localized: "Все"))],
                     selection: $filter)
            .padding(.top, 10)
        LazyVStack(spacing: 10) {
            ForEach(shown) { (t: OutreachTarget) in
                Button { selected = t } label: { OutreachRow(target: t) }
                    .buttonStyle(PressStyle())
                    .contextMenu { rowMenu(t) }
            }
        }
        .padding(.top, 12)
        if shown.isEmpty {
            EmptyNote(text: String(localized: "В этом списке пока пусто"))
        }
        if unsent > 0 {
            Button { confirmClear = true } label: {
                Label(String(localized: "Очистить очередь (\(unsent))"), systemImage: "trash")
                    .font(Typo.body(15, .semibold)).foregroundStyle(Pal.danger)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            .padding(.top, 18)
        }
    }

    private func filtered(_ all: [OutreachTarget], both: Bool) -> [OutreachTarget] {
        let src: String = both ? source : "all"
        let f: String = filter
        return all.filter { (t: OutreachTarget) -> Bool in
            if src != "all" && t.sourceKey != src { return false }
            switch f {
            case "new": return t.unsent
            case "sent": return t.status == "sent"
            case "replied": return t.status == "replied"
            default: return true
            }
        }
    }

    @ViewBuilder private func rowMenu(_ t: OutreachTarget) -> some View {
        if t.unsent {
            Button {
                let skip: Bool = t.status != "skip"
                Task {
                    await store.outreachAction(["action": skip ? "skip" : "restore", "id": t.id],
                                               ok: skip ? String(localized: "Фирма пропущена") : String(localized: "Фирма вернулась в очередь"))
                }
            } label: {
                Label(t.status == "skip" ? String(localized: "Вернуть в очередь") : String(localized: "Пропустить"),
                      systemImage: t.status == "skip" ? "arrow.uturn.left" : "forward")
            }
            Button(role: .destructive) { confirmDelete = t } label: {
                Label(String(localized: "Убрать из рассылки"), systemImage: "trash")
            }
        }
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { confirmDelete != nil }, set: { (v: Bool) in if !v { confirmDelete = nil } })
    }

    // MARK: - удаление и очистка (запрос уходит после тоста с «Отменить»)

    private func remove(_ t: OutreachTarget) {
        store.outreachRemoveLater(ids: [t.id], body: ["action": "delete", "id": t.id],
                                  text: String(localized: "«\(t.name)» убрана из рассылки"))
    }

    /// src: nil — все неотправленные, иначе только одного источника ("tr-setup" / "povod")
    private func clear(_ src: String?) {
        let unsent: [OutreachTarget] = visibleTargets.filter { (t: OutreachTarget) in t.unsent && (src == nil || t.sourceKey == src) }
        let ids: Set<String> = Set(unsent.map { (t: OutreachTarget) in t.id })
        var body: [String: Any] = ["action": "clear"]
        if let src { body["source"] = src }
        store.outreachRemoveLater(ids: ids, body: body, text: String(localized: "Очередь очищена: убрано \(ids.count)"))
    }

    @ViewBuilder private var clearButtons: some View {
        let unsent: [OutreachTarget] = visibleTargets.filter { (t: OutreachTarget) in t.unsent }
        let povod: Int = unsent.filter { (t: OutreachTarget) in t.isPovod }.count
        let tr: Int = unsent.count - povod
        if povod > 0 && tr > 0 {
            Button(String(localized: "Убрать все неотправленные (\(unsent.count))"), role: .destructive) { clear(nil) }
            Button(String(localized: "Только «Рассылка Повод» (\(povod))"), role: .destructive) { clear("povod") }
            Button(String(localized: "Только «Рассылка TR» (\(tr))"), role: .destructive) { clear("tr-setup") }
        } else {
            Button(String(localized: "Убрать неотправленные (\(unsent.count))"), role: .destructive) { clear(nil) }
        }
        Button(String(localized: "Отмена"), role: .cancel) {}
    }

    /// Снимки CI (-fixture): открыть лист/диалог после того, как экран встал на место.
    private func applyFixture() async {
        guard store.fixture, !store.outreachFixtureScreen.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        switch store.outreachFixtureScreen {
        case "all": filter = "all"
        case "settings": showSettings = true
        case "clear": confirmClear = true
        default: break
        }
    }
}

// MARK: - строка списка

struct OutreachRow: View {
    let target: OutreachTarget

    var body: some View {
        let t: OutreachTarget = target
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t.name).font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                OutreachPill(text: t.statusLabel, color: t.statusColor)
            }
            let info: String = joinParts([t.niche, t.city, t.problem])
            if !info.isEmpty {
                Text(info).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(2).multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                OutreachTag(text: t.sourceName)
                OutreachTag(text: t.waLabel, color: t.waColor)
            }
            if let e = t.error, !e.isEmpty {
                Text(e).font(Typo.body(13)).foregroundStyle(Pal.danger).multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassRect(22)
        .accessibilityElement(children: .combine)
    }
}

struct OutreachPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(Typo.body(13, .semibold)).foregroundStyle(Pal.ink)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color))
    }
}

struct OutreachTag: View {
    let text: String
    var color: Color = Pal.fg2
    var body: some View {
        Text(text).font(Typo.body(13, .medium)).foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Pal.fg.opacity(0.08)))
    }
}

/// Плашка «подключите WhatsApp»: без WhatsApp по QR номера не проверить и не написать.
struct OutreachWhatsAppBanner: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble").font(.icon(15, .semibold)).accessibilityHidden(true)
                Text("Подключите WhatsApp").font(Typo.body(16, .semibold))
            }
            Text("Номера проверяются и сообщения уходят только через ваш WhatsApp. Подключите его по QR-коду в веб-кабинете: «Каналы» → WhatsApp.")
                .font(Typo.body(14))
                .fixedSize(horizontal: false, vertical: true)
            Button { haptic(); openURL(API.webCabinet) } label: {
                Text("Открыть веб-кабинет").font(Typo.body(15, .semibold)).foregroundStyle(Pal.ink)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(Color.white.opacity(0.9)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .foregroundStyle(Pal.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0xFFD59E)))
    }
}

// MARK: - подписи

extension OutreachTarget {
    /// источник для фильтра и очистки; старые записи без поля — турецкий список
    var sourceKey: String { isPovod ? "povod" : "tr-setup" }
    var sourceName: String { isPovod ? String(localized: "Рассылка Повод") : String(localized: "Рассылка TR") }

    var statusLabel: String {
        switch status {
        case "sent": return String(localized: "отправлено")
        case "replied": return String(localized: "ответили")
        case "skip": return String(localized: "пропущено")
        default: return String(localized: "в очереди")
        }
    }

    var statusColor: Color {
        switch status {
        case "sent": return Pal.acc
        case "replied": return Pal.mint
        case "skip": return Pal.fg.opacity(0.3)
        default: return Pal.apricot
        }
    }

    var waLabel: String {
        switch waStatus {
        case "yes": return String(localized: "WhatsApp есть")
        case "no": return String(localized: "нет WhatsApp")
        default: return String(localized: "WhatsApp не проверен")
        }
    }

    var waColor: Color {
        switch waStatus {
        case "yes": return Pal.mint
        case "no": return Pal.rose
        default: return Pal.fg2
        }
    }
}

enum OutreachFormat {
    /// пн…вс (порядок на экране) → номера дней сервера (0 — воскресенье)
    static let weekOrder: [Int] = [1, 2, 3, 4, 5, 6, 0]

    static func dayName(_ d: Int) -> String {
        switch d {
        case 1: return String(localized: "пн")
        case 2: return String(localized: "вт")
        case 3: return String(localized: "ср")
        case 4: return String(localized: "чт")
        case 5: return String(localized: "пт")
        case 6: return String(localized: "сб")
        default: return String(localized: "вс")
        }
    }

    static func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    static func days(_ list: [Int]) -> String {
        let set: Set<Int> = Set(list)
        if set.count == 7 { return String(localized: "каждый день") }
        if set == Set([1, 2, 3, 4, 5]) { return String(localized: "пн–пт") }
        if set == Set([1, 2, 3, 4, 5, 6]) { return String(localized: "пн–сб") }
        let names: [String] = weekOrder.filter { (d: Int) in set.contains(d) }.map { (d: Int) in dayName(d) }
        return names.joined(separator: ", ")
    }

    static func summary(_ st: OutreachSettings) -> String {
        let from: String = hour(st.startHour)
        let to: String = hour(st.endHour)
        let d: String = days(st.days)
        return String(localized: "\(st.dailyLimit) в день · пауза \(st.gapMin) мин · \(from)–\(to), \(d)")
    }
}

// MARK: - лист фирмы

struct OutreachTargetSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let target: OutreachTarget
    @State private var text = ""
    @State private var busy = false
    @State private var confirmSend = false
    @State private var confirmDelete = false

    var body: some View {
        let t: OutreachTarget = current
        SheetBox(title: t.name, subtitle: joinParts([t.niche, t.city, t.phone])) {
            HStack(spacing: 6) {
                OutreachPill(text: t.statusLabel, color: t.statusColor)
                OutreachTag(text: t.sourceName)
                OutreachTag(text: t.waLabel, color: t.waColor)
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            if let p = t.problem, !p.isEmpty {
                Text(p).font(Typo.body(14)).foregroundStyle(Pal.apricot).padding(.horizontal, 8).padding(.bottom, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            messageEditor(t)
            if t.unsent {
                unsentActions(t)
            } else if let cid = t.contactId, let conv = store.mainConversation(of: cid) {
                SheetOption(icon: "bubble.left", title: String(localized: "Открыть переписку"), action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.open(.chat(conv.id)) }
                })
            }
            if let site = t.site, !site.isEmpty, let u = URL(string: site.hasPrefix("http") ? site : "https://" + site) {
                SheetOption(icon: "globe", title: String(localized: "Открыть сайт"), subtitle: site, action: { openURL(u) })
            }
        }
        .onAppear { text = t.message ?? "" }
    }

    /// свежая версия фирмы из последнего ответа сервера
    private var current: OutreachTarget {
        store.outreach?.targets.first { (x: OutreachTarget) in x.id == target.id } ?? target
    }

    private var changed: Bool { text != (current.message ?? "") }

    @ViewBuilder private func messageEditor(_ t: OutreachTarget) -> some View {
        Group {
            if t.isPovod {
                Text("Текст сообщения (из Повода)")
            } else {
                Text("Текст сообщения")
            }
        }
        .font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg2)
        .padding(.horizontal, 8).padding(.top, 4)
        TextField(String(localized: "Текст первого сообщения"), text: $text, axis: .vertical)
            .lineLimit(4...10)
            .font(Typo.body(15)).foregroundStyle(Pal.fg)
            .disabled(!t.unsent)
            .padding(14)
            .glass(.light, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 4)
    }

    @ViewBuilder private func unsentActions(_ t: OutreachTarget) -> some View {
        let block: String? = sendBlock(t)
        if changed {
            SheetOption(icon: "checkmark", title: String(localized: "Сохранить текст"), action: { saveText(t) })
        }
        Button { confirmSend = true } label: {
            ZStack {
                if busy {
                    ProgressView().tint(Pal.onAcc)
                } else {
                    Text("Отправить").font(Typo.body(16, .semibold))
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .primaryFill(16)
        }
        .buttonStyle(PressStyle())
        .disabled(busy || block != nil)
        .opacity(block != nil ? 0.5 : 1)
        .padding(.top, 10)
        .confirmationDialog(String(localized: "Отправить сейчас?"), isPresented: $confirmSend, titleVisibility: .visible) {
            Button(String(localized: "Отправить в WhatsApp")) { send(t) }
            Button(String(localized: "Отмена"), role: .cancel) {}
        } message: {
            Text("Сообщение уйдёт фирме «\(t.name)» с вашего WhatsApp. Вернуть его будет нельзя.")
        }
        if let block {
            Text(block).font(Typo.body(13)).foregroundStyle(Pal.apricot).padding(.horizontal, 8).padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        } else if let reason = store.outreach?.quota?.reason, store.outreach?.quota?.ok == false {
            Text(reason).font(Typo.body(13)).foregroundStyle(Pal.apricot).padding(.horizontal, 8).padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        SheetOption(icon: "arrow.counterclockwise",
                    title: t.isPovod ? String(localized: "Вернуть текст из Повода") : String(localized: "Вернуть текст по шаблону"),
                    action: { resetText(t) })
        SheetOption(icon: "checkmark.shield", title: String(localized: "Проверить номер в WhatsApp"), subtitle: t.waLabel, action: { check(t) })
        SheetOption(icon: t.status == "skip" ? "arrow.uturn.left" : "forward",
                    title: t.status == "skip" ? String(localized: "Вернуть в очередь") : String(localized: "Пропустить фирму"),
                    action: { toggleSkip(t) })
        SheetOption(icon: "trash", iconColor: Pal.danger, title: String(localized: "Убрать из рассылки"), color: Pal.danger, action: { confirmDelete = true })
            .confirmationDialog(String(localized: "Убрать фирму из рассылки?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(String(localized: "Убрать"), role: .destructive) { remove(t) }
                Button(String(localized: "Отмена"), role: .cancel) {}
            } message: {
                Text("Ей ещё не писали. Передумаете — нажмите «Отменить» в течение 9 секунд.")
            }
    }

    /// почему «Отправить» сейчас нельзя (жёсткие причины; лимит и паузу проверяет сервер)
    private func sendBlock(_ t: OutreachTarget) -> String? {
        if store.outreach?.needWhatsApp == true { return String(localized: "Сначала подключите WhatsApp в веб-кабинете") }
        if t.status == "skip" { return String(localized: "Фирма пропущена — сначала верните её в очередь") }
        if t.waStatus == "no" { return String(localized: "У этого номера нет WhatsApp") }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(localized: "Текст пустой") }
        return nil
    }

    private func saveText(_ t: OutreachTarget) {
        let body: [String: Any] = ["action": "message", "id": t.id, "text": text]
        Task { await store.outreachAction(body, ok: String(localized: "Текст сохранён")) }
    }

    private func resetText(_ t: OutreachTarget) {
        Task {
            if await store.outreachAction(["action": "reset", "id": t.id], ok: String(localized: "Текст вернули")) != nil {
                text = current.message ?? ""
            }
        }
    }

    private func check(_ t: OutreachTarget) {
        Task {
            guard let r = await store.outreachAction(["action": "check", "id": t.id]) else { return }
            if r.wa == "no" {
                store.show(String(localized: "У этого номера нет WhatsApp"), ok: false)
            } else {
                store.show(String(localized: "WhatsApp есть — можно отправлять"))
            }
        }
    }

    private func toggleSkip(_ t: OutreachTarget) {
        let skip: Bool = t.status != "skip"
        Task {
            await store.outreachAction(["action": skip ? "skip" : "restore", "id": t.id],
                                       ok: skip ? String(localized: "Фирма пропущена") : String(localized: "Фирма вернулась в очередь"))
            dismiss()
        }
    }

    private func send(_ t: OutreachTarget) {
        busy = true
        let edited: Bool = changed
        let newText: String = text
        Task {
            if edited {
                if await store.outreachAction(["action": "message", "id": t.id, "text": newText]) == nil {
                    busy = false
                    return
                }
            }
            let r: OutreachList? = await store.outreachAction(["action": "send", "id": t.id])
            busy = false
            guard let r else { return }
            if let p = r.partial, !p.isEmpty {
                store.show(String(localized: "Ушло не полностью: \(p)"), ok: false)
            } else {
                store.show(String(localized: "Отправлено. Ответ придёт в обычный чат WhatsApp"))
            }
            dismiss()
        }
    }

    private func remove(_ t: OutreachTarget) {
        dismiss()
        store.outreachRemoveLater(ids: [t.id], body: ["action": "delete", "id": t.id],
                                  text: String(localized: "«\(t.name)» убрана из рассылки"))
    }
}

// MARK: - настройки рассылки

struct OutreachSettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var st: OutreachSettings = OutreachSettings.defaults
    @State private var loaded = false
    @State private var saving = false

    /// шаги паузы, минут (сервер принимает 3…120)
    private static let gapSteps: [Int] = [3, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        SheetBox(title: String(localized: "Настройки рассылки"),
                 subtitle: String(localized: "Сколько и когда писать фирмам. Чем аккуратнее темп, тем меньше риск, что WhatsApp заблокирует номер.")) {
            if loaded {
                form
            } else {
                ProgressView().tint(Pal.fg).frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let fetched: OutreachSettings? = await store.loadOutreachSettings()
        var v: OutreachSettings = fetched ?? store.outreach?.settings ?? OutreachSettings.defaults
        // часы — в пределах пикеров (иначе у Picker нет тега с текущим значением)
        v.startHour = min(max(v.startHour, OutreachSettings.firstHour), OutreachSettings.lastHour - OutreachSettings.minWindow)
        v.endHour = min(max(v.endHour, v.startHour + OutreachSettings.minWindow), OutreachSettings.lastHour)
        st = v
        loaded = true
    }

    @ViewBuilder private var form: some View {
        let problem: String? = validation
        Cap(String(localized: "Сколько"))
        counterRow(title: String(localized: "Сообщений в день"), value: "\(st.dailyLimit)",
                   hint: String(localized: "от 1 до 40 · по умолчанию 15"),
                   canMinus: st.dailyLimit > OutreachSettings.dailyRange.lowerBound,
                   canPlus: st.dailyLimit < OutreachSettings.dailyRange.upperBound,
                   minus: { st.dailyLimit = max(OutreachSettings.dailyRange.lowerBound, st.dailyLimit - 1) },
                   plus: { st.dailyLimit = min(OutreachSettings.dailyRange.upperBound, st.dailyLimit + 1) })
        counterRow(title: String(localized: "Пауза между сообщениями"), value: String(localized: "\(st.gapMin) мин"),
                   hint: String(localized: "от 3 до 120 минут · по умолчанию 3. Автоотправка всё равно ждёт не меньше 15 минут"),
                   canMinus: st.gapMin > OutreachSettings.gapRange.lowerBound,
                   canPlus: st.gapMin < OutreachSettings.gapRange.upperBound,
                   minus: { st.gapMin = prevGap(st.gapMin) },
                   plus: { st.gapMin = nextGap(st.gapMin) })

        Cap(String(localized: "Когда отправлять"))
        hoursRow
        daysRow
        timezoneNote

        if let problem {
            Text(problem).font(Typo.body(13)).foregroundStyle(Pal.danger).padding(.horizontal, 8).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button { save() } label: {
            ZStack {
                if saving {
                    ProgressView().tint(Pal.onAcc)
                } else {
                    Text("Сохранить").font(Typo.body(16, .semibold))
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .primaryFill(16)
        }
        .buttonStyle(PressStyle())
        .disabled(saving || problem != nil)
        .opacity(problem != nil ? 0.5 : 1)
        .padding(.top, 14)
        SheetOption(icon: "arrow.counterclockwise", title: String(localized: "Как было по умолчанию"),
                    subtitle: String(localized: "15 в день · пауза 3 мин · 10:00–19:00, пн–сб"), action: {
            let tz: String? = st.tz
            st = OutreachSettings.defaults
            st.tz = tz
        })
    }

    private var validation: String? {
        if st.days.isEmpty { return String(localized: "Выберите хотя бы один день недели") }
        if st.endHour - st.startHour < OutreachSettings.minWindow { return String(localized: "Окно отправки — не меньше 2 часов") }
        return nil
    }

    private func counterRow(title: String, value: String, hint: String, canMinus: Bool, canPlus: Bool,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.body(16)).foregroundStyle(Pal.fg)
                    Text(value).font(Typo.display(20)).foregroundStyle(Pal.fg)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 6)
                CircleButton(system: "minus", iconSize: 16, label: String(localized: "Меньше"), action: minus)
                    .disabled(!canMinus).opacity(canMinus ? 1 : 0.4)
                CircleButton(system: "plus", iconSize: 16, label: String(localized: "Больше"), action: plus)
                    .disabled(!canPlus).opacity(canPlus ? 1 : 0.4)
            }
            Text(hint).font(Typo.body(13)).foregroundStyle(Pal.fg3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.fg.opacity(0.06)))
        .padding(.bottom, 8)
    }

    private func nextGap(_ v: Int) -> Int {
        Self.gapSteps.first { (s: Int) in s > v } ?? OutreachSettings.gapRange.upperBound
    }

    private func prevGap(_ v: Int) -> Int {
        Self.gapSteps.last { (s: Int) in s < v } ?? OutreachSettings.gapRange.lowerBound
    }

    private var startHours: [Int] {
        Array(OutreachSettings.firstHour...(OutreachSettings.lastHour - OutreachSettings.minWindow))
    }

    private var endHours: [Int] {
        let lo: Int = min(st.startHour + OutreachSettings.minWindow, OutreachSettings.lastHour)
        return Array(lo...OutreachSettings.lastHour)
    }

    private var hoursRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("с").font(Typo.body(16)).foregroundStyle(Pal.fg2)
                Picker(String(localized: "Начало"), selection: startBinding) {
                    ForEach(startHours, id: \.self) { (h: Int) in Text(OutreachFormat.hour(h)).tag(h) }
                }
                .pickerStyle(.menu)
                .tint(Pal.fg)
                Text("до").font(Typo.body(16)).foregroundStyle(Pal.fg2)
                Picker(String(localized: "Конец"), selection: $st.endHour) {
                    ForEach(endHours, id: \.self) { (h: Int) in Text(OutreachFormat.hour(h)).tag(h) }
                }
                .pickerStyle(.menu)
                .tint(Pal.fg)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            Text("Окно автоотправки — не меньше 2 часов · по умолчанию 10:00–19:00")
                .font(Typo.body(13)).foregroundStyle(Pal.fg3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.fg.opacity(0.06)))
        .padding(.bottom, 8)
    }

    /// начало окна: конец сам сдвигается, чтобы окно оставалось не меньше 2 часов
    private var startBinding: Binding<Int> {
        Binding(get: { st.startHour }, set: { (v: Int) in
            st.startHour = v
            if st.endHour - v < OutreachSettings.minWindow { st.endHour = min(OutreachSettings.lastHour, v + OutreachSettings.minWindow) }
        })
    }

    private var daysRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Дни недели").font(Typo.body(16)).foregroundStyle(Pal.fg)
            HStack(spacing: 4) {
                ForEach(OutreachFormat.weekOrder, id: \.self) { (d: Int) in
                    dayButton(d)
                }
            }
            Text("По умолчанию пн–сб").font(Typo.body(13)).foregroundStyle(Pal.fg3)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.fg.opacity(0.06)))
        .padding(.bottom, 8)
    }

    private func dayButton(_ d: Int) -> some View {
        let on: Bool = st.days.contains(d)
        return Button {
            haptic()
            if on {
                st.days.removeAll { (x: Int) in x == d }
            } else {
                st.days.append(d)
                st.days.sort()
            }
        } label: {
            Text(OutreachFormat.dayName(d))
                .font(Typo.body(14, .semibold))
                .foregroundStyle(on ? Pal.onAcc : Pal.fg)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(on ? Pal.acc : Pal.fg.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var timezoneNote: some View {
        let mine: String = store.user?.tz ?? st.tz ?? "Europe/Istanbul"
        let name: String = TimeZone(identifier: mine)?.localizedName(for: .generic, locale: uiLocale) ?? mine
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Часовой пояс").font(Typo.body(16)).foregroundStyle(Pal.fg)
                Spacer(minLength: 6)
                Text(name).font(Typo.body(14, .semibold)).foregroundStyle(Pal.fg2).multilineTextAlignment(.trailing)
            }
            Text("Время считается по часовому поясу вашего профиля (\(mine)). Сутки для дневного лимита — тоже по нему.")
                .font(Typo.body(13)).foregroundStyle(Pal.fg3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Pal.fg.opacity(0.06)))
    }

    private func save() {
        saving = true
        let value: OutreachSettings = st
        Task {
            let ok: Bool = await store.saveOutreachSettings(value)
            saving = false
            if ok { dismiss() }
        }
    }
}

func joinParts(_ parts: [String?]) -> String {
    parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}
