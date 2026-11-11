import SwiftUI

struct TodayView: View {
    @Environment(Store.self) private var store
    @State private var seg = "today"
    @State private var remFor: String?

    var body: some View {
        let now = Date()
        let day0 = Calendar.current.startOfDay(for: now)
        let R = store.openReminders.sorted { $0.date < $1.date }
        let late = R.filter { $0.date < now }
        let today = R.filter { $0.date >= now && $0.date < day0.addingTimeInterval(86400) }
        let later = R.filter { $0.date >= day0.addingTimeInterval(86400) }
        let waiting = waitingList()
        let rCount: Int = R.count
        let waitCount: Int = waiting.count

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Сегодня").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4)
                Text(subtitle(R.count, late.count, waiting.count))
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).padding(.horizontal, 4).padding(.top, 6)
                GlassSegment(items: [("today", String(localized: "Напоминания · \(rCount)")), ("wait", String(localized: "Ждут ответа · \(waitCount)"))], selection: $seg)
                    .padding(.top, 16)

                if seg == "today" {
                    if !late.isEmpty { section(String(localized: "Просрочено"), late, color: Pal.rose) }
                    if !today.isEmpty { section(String(localized: "Сегодня"), today) }
                    if !later.isEmpty { section(String(localized: "Позже"), later) }
                    if R.isEmpty {
                        VStack(spacing: 8) {
                            Text("Напоминаний пока нет").font(Typo.display(17)).foregroundStyle(Pal.fg)
                            Text("Поставь его из чата или карточки клиента — или нажми подсказку «Обещает оплатить».")
                                .font(Typo.body(14)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(3)
                            PillButton(action: { withAnimation { seg = "wait" } }) { Text("Кто ждёт ответа · \(waiting.count)") }
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18).padding(.vertical, 22)
                        .glassRect(24)
                        .padding(.top, 16)
                    }
                } else {
                    Cap(String(localized: "Последнее сообщение от клиента"))
                    LazyVStack(spacing: 10) {
                        ForEach(waiting) { conv in
                            if let c = store.contact(conv.contactId) {
                                card(c, why: conv.last?.preview ?? "", time: Fmt.when(conv.last?.date ?? now), remId: nil, convId: conv.id)
                            }
                        }
                    }
                    if waiting.isEmpty { EmptyNote(text: String(localized: "Все ответы отправлены 👌")) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 130)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: seg)
        }
        .refreshable { await store.loadState(force: true) }
        .screenBackground(store.wall)
        .sheet(item: Binding(get: { remFor.map(IDBox.init) }, set: { remFor = $0?.id })) { b in ReminderSheet(contactId: b.id) }
    }

    private func subtitle(_ r: Int, _ late: Int, _ wait: Int) -> String {
        if r == 0 { return String(localized: "Ждут ответа: \(wait)") }
        if late == 0 { return String(localized: "Напоминаний: \(r)") }
        return String(localized: "Напоминаний: \(r), просрочено \(late)")
    }

    private func waitingList() -> [Conversation] {
        store.state.conversations.filter { conv in
            guard let m = conv.last, !m.isOut else { return false }
            let key = store.folder(store.contact(conv.contactId)?.folderId)?.key
            return key != "rejected" && key != "spam"
        }
        .sorted { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [Reminder], color: Color = Pal.fg2) -> some View {
        Cap(title, color: color)
        LazyVStack(spacing: 10) {
            ForEach(list) { r in
                if let c = store.contact(r.contactId) {
                    let isToday = Calendar.current.isDateInToday(r.date)
                    card(c, why: r.text, time: isToday ? Fmt.hm(r.date) : Fmt.dayLong(r.date) + " " + Fmt.hm(r.date), remId: r.id,
                         convId: store.mainConversation(of: c.id)?.id)
                }
            }
        }
    }

    private func card(_ c: Contact, why: String, time: String, remId: String?, convId: String?) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Avatar(name: c.name, hue: c.displayHue, url: c.avatar, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg).lineLimit(1)
                    Text(why).font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(time).font(Typo.display(13)).foregroundStyle(Pal.fg)
            }
            HStack(spacing: 8) {
                Button {
                    if let convId { store.open(.chat(convId)) } else { store.open(.client(c.id)) }
                } label: {
                    Text("Написать").font(Typo.body(14, .semibold)).frame(maxWidth: .infinity).frame(height: 40).primaryFill(14)
                }
                .buttonStyle(PressStyle())
                if let remId {
                    Button {
                        Task { await store.act(["type": "doneReminder", "id": remId], ok: String(localized: "Отмечено")) }
                    } label: {
                        Text("Готово").font(Typo.body(14, .medium)).foregroundStyle(Pal.fg).padding(.horizontal, 16).frame(height: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
                }
                Button { remFor = c.id } label: {
                    Image(systemName: "clock").font(.icon(17)).foregroundStyle(Pal.fg).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(String(localized: "Напомнить о клиенте"))
                .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
        }
        .padding(14)
        .glassRect(24)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
