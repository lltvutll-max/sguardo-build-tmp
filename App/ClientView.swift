import SwiftUI
import UIKit

struct ClientView: View {
    @Environment(Store.self) private var store
    let contactId: String
    @State private var sheet: ClientSheet?
    @State private var amountText = ""
    @State private var note = ""
    @State private var noteLoaded = false
    @State private var confirmDeal: DealRemoval?

    struct DealRemoval: Identifiable {
        let deal: Deal
        let ok: String
        var id: String { deal.id }
    }
    @FocusState private var focus: Field?
    enum Field { case amount, note }

    enum ClientSheet: String, Identifiable {
        case write, call, remind, folder, label
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let c = store.contact(contactId) {
                content(c)
            } else {
                VStack {
                    TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: { EmptyView() })
                    EmptyNote(text: String(localized: "Клиент не найден"))
                    Spacer()
                }
            }
        }
        .screenBackground(store.wall)
        .sheet(item: $sheet) { s in
            switch s {
            case .write: WriteSheet(contactId: contactId)
            case .call: CallSheet(contactId: contactId)
            case .remind: ReminderSheet(contactId: contactId)
            case .folder: FolderSheet(contactId: contactId)
            case .label: LabelSheet(contactId: contactId)
            }
        }
        .confirmationDialog("Удалить запись о сумме \(Fmt.money(confirmDeal?.deal.amount ?? 0, currency: store.state.workspace?.currency))?",
                            isPresented: Binding(get: { confirmDeal != nil }, set: { if !$0 { confirmDeal = nil } }), titleVisibility: .visible) {
            if let r = confirmDeal {
                Button("Удалить", role: .destructive) {
                    confirmDeal = nil
                    Task { await store.act(["type": "removeDeal", "id": r.deal.id], ok: r.ok) }
                }
            }
            Button("Отмена", role: .cancel) { confirmDeal = nil }
        } message: {
            Text("Сумма пропадёт из сводки и истории клиента.")
        }
        .onAppear(perform: load)
        .onDisappear(perform: saveNote)
    }

    private func load() {
        guard !noteLoaded, let c = store.contact(contactId) else { return }
        note = c.note ?? ""
        if let d = store.dealDraft[contactId] {
            amountText = "\(d)"
        } else if let promised = store.deals(of: contactId).last(where: { $0.status == "promised" }), promised.amount > 0 {
            amountText = "\(Int(promised.amount))"
        }
        noteLoaded = true
    }

    private func saveNote() {
        guard noteLoaded, let c = store.contact(contactId), note != (c.note ?? "") else { return }
        let n = note
        Task { await store.act(["type": "setNote", "contactId": contactId, "note": n], ok: String(localized: "Заметка сохранена")) }
    }

    private var amount: Int { Int(amountText.filter(\.isNumber)) ?? 0 }

    private func content(_ c: Contact) -> some View {
        let convs = store.conversations(of: c.id)
        let msgs = convs.flatMap { store.messages($0.id) }.sorted { $0.date < $1.date }
        let ins = msgs.filter { !$0.isOut }.count
        let outs = msgs.count - ins
        var resp: [TimeInterval] = []
        for i in msgs.indices.dropFirst() where msgs[i].isOut && !msgs[i - 1].isOut {
            resp.append(msgs[i].date.timeIntervalSince(msgs[i - 1].date))
        }
        let avg = resp.isEmpty ? nil : resp.reduce(0, +) / Double(resp.count)
        let days = max(1, Int((Date().timeIntervalSince(c.first) / 86400).rounded()))
        let firstOut = msgs.first(where: { $0.isOut })
        let firstIn = msgs.first(where: { !$0.isOut })
        let whoFirst = (firstOut != nil && (firstIn == nil || firstOut!.date < firstIn!.date)) ? String(localized: "мы") : String(localized: "клиент")
        let deals = store.deals(of: c.id)
        let paid = deals.filter { $0.status == "paid" }.reduce(0) { $0 + $1.amount }
        let net = NetInfo.of(convs.first?.network ?? c.source)
        let f = store.folder(c.folderId)
        let rem = store.reminder(for: c.id)
        let cur = store.state.workspace?.currency
        let older = convs.reduce(0) { $0 + ($1.older ?? 0) }
        let handleText: String = joinHandle(net.name, c.handle)
        let sinceText: String = Fmt.dayLong(c.first)
        let shownCount: Int = msgs.count

        return VStack(spacing: 0) {
            TopBar(back: { saveNote(); store.pop() }, center: {
                Text("карточка клиента").font(Typo.body(12)).foregroundStyle(Pal.fg3)
            }, trailing: { Color.clear.frame(width: 44, height: 44) })
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Avatar(name: c.name, hue: c.displayHue, url: c.avatar, size: 92)
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 14)
                        Text(c.name).font(Typo.display(23)).tracking(-0.7).foregroundStyle(Pal.fg).multilineTextAlignment(.center).padding(.top, 10)
                        Text(String(localized: "\(handleText) · с \(sinceText)"))
                            .font(Typo.body(14)).foregroundStyle(Pal.fg2)
                    }
                    .padding(.top, 4)

                    HStack(spacing: 8) {
                        action("bubble.left", String(localized: "Написать")) { sheet = .write }
                        action("phone", String(localized: "Позвонить")) { sheet = .call }
                        action("bell", String(localized: "Напомнить")) { sheet = .remind }
                        action("creditcard", String(localized: "Оплатил")) { markPaid(c) }
                    }
                    .padding(.top, 18)

                    Cap(String(localized: "Статистика"))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        Tile(label: String(localized: "сообщений"), value: "\(msgs.count + older)")
                        Tile(label: String(localized: "от клиента"), value: "\(ins)")
                        Tile(label: String(localized: "от нас"), value: "\(outs)")
                        Tile(label: String(localized: "ответ"), value: Fmt.duration(avg), valueSize: 19)
                        Tile(label: String(localized: "в работе"), value: String(localized: "\(days) дн"), valueSize: 19)
                        Tile(label: String(localized: "оплачено"), value: paid > 0 ? Fmt.money(paid, currency: cur) : "—", valueSize: 17, valueColor: Pal.mint)
                    }
                    VStack(spacing: 0) {
                        GroupRow(first: true) { Text("Первым написал(а)").foregroundStyle(Pal.fg2); Spacer(); Text(whoFirst).foregroundStyle(Pal.fg) }
                        GroupRow { Text("Последнее сообщение").foregroundStyle(Pal.fg2); Spacer(); Text(msgs.last.map { Fmt.when($0.date) } ?? "—").foregroundStyle(Pal.fg) }
                        GroupRow { Text("Откуда").foregroundStyle(Pal.fg2); Spacer(); Text(net.name).foregroundStyle(Pal.fg) }
                        if older > 0 {
                            GroupRow { Text("Цифры по последним \(shownCount) сообщениям").font(Typo.body(13)).foregroundStyle(Pal.fg3); Spacer() }
                        }
                    }
                    .glassRect(24)
                    .padding(.top, 8)

                    Cap(String(localized: "Сделка"))
                    VStack(spacing: 0) {
                        Button { sheet = .folder } label: {
                            GroupRow(first: true) {
                                Text("Папка").foregroundStyle(Pal.fg2)
                                Spacer()
                                Circle().fill(Color(css: f?.color)).frame(width: 9, height: 9)
                                Text(f?.name ?? String(localized: "Без папки")).font(Typo.body(16, .medium)).foregroundStyle(Pal.fg)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        GroupRow {
                            Text("Сумма").foregroundStyle(Pal.fg2)
                            Spacer()
                            TextField("", text: $amountText, prompt: Text("0").foregroundColor(Pal.fg3))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(Typo.display(16))
                                .foregroundStyle(Pal.fg)
                                .frame(width: 130)
                                .focused($focus, equals: .amount)
                                .onChange(of: amountText) { _, v in
                                    let n = Int(v.filter(\.isNumber)) ?? 0
                                    store.dealDraft[contactId] = n > 0 ? n : nil
                                }
                            Text(Fmt.symbol(cur)).foregroundStyle(Pal.fg)
                        }
                        Button { promise(c) } label: {
                            GroupRow {
                                Image(systemName: "clock").font(.system(size: 16))
                                Text("Обещал(а) оплатить завтра").font(Typo.body(16, .semibold))
                                Spacer()
                            }
                            .foregroundStyle(Pal.apricot)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowPressStyle())
                        ForEach(deals.suffix(4).reversed()) { d in
                            dealRow(d, contactId: c.id, cur: cur)
                        }
                        if !deals.isEmpty {
                            GroupRow {
                                Text("Удержи запись, чтобы удалить ошибочную").font(Typo.body(12)).foregroundStyle(Pal.fg3)
                                Spacer()
                            }
                        }
                    }
                    .glassRect(24)

                    Cap(String(localized: "Метки"))
                    FlowLayout(spacing: 8) {
                        ForEach(store.labels, id: \.self) { l in
                            let on = (c.tags ?? []).contains(l)
                            Chip(text: on ? l + "  ✕" : l, on: false, height: 32, fontSize: 13, fill: on ? labelColor(l) : nil) { toggleTag(c, l) }
                                .accessibilityLabel(on ? String(localized: "Метка \(l), нажми, чтобы снять") : String(localized: "Метка \(l), нажми, чтобы поставить"))
                        }
                        Button { sheet = .label } label: {
                            Text("+ Метка").font(Typo.body(13, .semibold)).foregroundStyle(Pal.fg)
                                .padding(.horizontal, 14).frame(height: 32)
                                .overlay(Capsule().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Pal.fg.opacity(0.4)))
                        }
                        .buttonStyle(PressStyle())
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassRect(24)

                    Cap(String(localized: "Напоминание"))
                    Group {
                        if let rem {
                            GroupRow(first: true) {
                                Image(systemName: "clock").foregroundStyle(Pal.apricot)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Fmt.whenFull(rem.date)).font(Typo.body(16, .medium)).foregroundStyle(Pal.fg)
                                    Text(rem.text).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                                }
                                .padding(.vertical, 8)
                                Spacer()
                                PillButton(action: { Task { await store.perform([["type": "doneReminder", "id": rem.id]], contactId: c.id, ok: String(localized: "Напоминание выполнено")) } }) {
                                    Text("Готово").font(Typo.body(13, .medium))
                                }
                                Button { Task { await store.perform([["type": "removeReminder", "id": rem.id]], contactId: c.id, ok: String(localized: "Напоминание удалено")) } } label: {
                                    Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
                                }
                                .accessibilityLabel("Удалить напоминание")
                            }
                        } else {
                            Button { sheet = .remind } label: {
                                GroupRow(first: true) {
                                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                    Text("Поставить напоминание").font(Typo.body(16, .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(Pal.acc)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)

                    Cap(String(localized: "Заметка"))
                    TextField("", text: $note, prompt: Text("Что важно помнить о клиенте").foregroundColor(Pal.fg3), axis: .vertical)
                        .lineLimit(3...10)
                        .font(Typo.body(15))
                        .foregroundStyle(Pal.fg)
                        .focused($focus, equals: .note)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .glassRect(24)

                    Cap(String(localized: "Контакты"))
                    VStack(spacing: 0) {
                        ForEach(Array(convs.enumerated()), id: \.element.id) { i, conv in
                            let n = NetInfo.of(conv.network)
                            GroupRow(first: i == 0) {
                                Circle().fill(n.color).frame(width: 10, height: 10).padding(.horizontal, 6)
                                Text(n.name).foregroundStyle(Pal.fg)
                                Spacer()
                                Text(c.handle ?? c.name).foregroundStyle(Pal.fg2).lineLimit(1)
                            }
                        }
                        if let p = phoneOf(c, convs) {
                            GroupRow(first: convs.isEmpty) {
                                Image(systemName: "phone").foregroundStyle(Pal.fg.opacity(0.7))
                                Text("Телефон").foregroundStyle(Pal.fg)
                                Spacer()
                                Text(p).foregroundStyle(Pal.fg2).textSelection(.enabled)
                            }
                        }
                        if let e = c.email, !e.isEmpty {
                            GroupRow {
                                Image(systemName: "envelope").foregroundStyle(Pal.fg.opacity(0.7))
                                Text("Почта").foregroundStyle(Pal.fg)
                                Spacer()
                                Text(e).foregroundStyle(Pal.fg2).lineLimit(1).textSelection(.enabled)
                            }
                        }
                    }
                    .glassRect(24)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.loadState(force: true) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    if focus == .note { saveNote() }
                    focus = nil
                }
                .font(Typo.body(16, .semibold))
            }
        }
    }

    private func action(_ icon: String, _ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: { haptic(); run() }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundStyle(Pal.fg)
                    .frame(width: 54, height: 54)
                    .glass(.light, in: Circle(), interactive: true)
                Text(title).font(Typo.body(12, .medium)).foregroundStyle(Pal.fg)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
    }

    private func markPaid(_ c: Contact) {
        guard amount > 0 else {
            store.show(String(localized: "Сначала впиши сумму сделки"), ok: false)
            focus = .amount
            return
        }
        let promised = store.deals(of: c.id).last { $0.status == "promised" }
        var body: [String: Any] = ["type": "pay", "contactId": c.id, "productId": NSNull(), "amount": amount]
        if let promised { body["dealId"] = promised.id }
        let a = amount
        let moneyText: String = Fmt.money(Double(a), currency: store.state.workspace?.currency)
        let paidFolder: String = store.folder(key: "paid")?.name ?? String(localized: "Оплатил")
        let okText: String = String(localized: "Оплата \(moneyText) — в «\(paidFolder)»")
        Task {
            if await store.perform([body], contactId: c.id, ok: okText) {
                store.dealDraft[c.id] = nil
                amountText = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func promise(_ c: Contact) {
        let body: [String: Any] = ["type": "promise", "contactId": c.id, "productId": NSNull(), "amount": amount, "remindAt": isoString(RemPreset.tomorrow.date)]
        let laterFolder: String = store.folder(key: "later")?.name ?? String(localized: "Оплатит позже")
        let okText: String = String(localized: "В «\(laterFolder)», напомню завтра в 10:00")
        Task { await store.perform([body], contactId: c.id, ok: okText) }
    }

    private func toggleTag(_ c: Contact, _ t: String) {
        var tags = c.tags ?? []
        let had = tags.contains(t)
        if had { tags.removeAll { $0 == t } } else { tags.append(t) }
        let body: [String: Any] = ["type": "updateContact", "contactId": c.id, "tags": tags]
        Task { await store.perform([body], contactId: c.id, ok: had ? String(localized: "Метка «\(t)» снята") : String(localized: "Метка «\(t)» добавлена")) }
    }

    /// Строка оплаты/обещания: удержание — удалить (с «Отменить» нельзя: запись пропадает на сервере целиком).
    private func dealRow(_ d: Deal, contactId: String, cur: String?) -> some View {
        let icon: String = d.status == "paid" ? "checkmark.circle.fill" : (d.status == "refund" ? "arrow.uturn.left.circle" : "clock")
        let color: Color = d.status == "paid" ? Pal.mint : (d.status == "refund" ? Pal.danger : Pal.apricot)
        let title: String = d.status == "paid" ? String(localized: "Оплата") : (d.status == "refund" ? String(localized: "Возврат") : String(localized: "Обещал(а)"))
        return GroupRow {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).foregroundStyle(Pal.fg2)
            Spacer()
            Text(Fmt.money(d.amount, currency: cur)).font(Typo.display(14)).foregroundStyle(Pal.fg)
            Text(Fmt.dayLong(d.day)).font(Typo.body(13)).foregroundStyle(Pal.fg3)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if d.status == "promised" {
                Button(role: .destructive) { removeDeal(d, contactId: contactId, ok: String(localized: "Обещание снято")) } label: { Label("Снять обещание", systemImage: "xmark.circle") }
            } else {
                Button(role: .destructive) { removeDeal(d, contactId: contactId, ok: String(localized: "Запись об оплате удалена")) } label: { Label(d.status == "refund" ? String(localized: "Удалить возврат") : String(localized: "Удалить оплату"), systemImage: "trash") }
            }
        }
    }

    private func removeDeal(_ d: Deal, contactId: String, ok: String) {
        confirmDeal = DealRemoval(deal: d, ok: ok)
    }
}

/// Перенос чипов по строкам.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(maxW, widest), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
