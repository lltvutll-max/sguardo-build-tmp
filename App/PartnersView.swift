import SwiftUI

/// «Партнёры» — пример для клуба (как в утверждённом макете): данных партнёров в бэкенде пока нет,
/// поэтому раздел подписан «пример для клуба», цифры генерируются так же, как в макете.
enum PartnerDemo {
    static let names = ["Алина К.", "Марина Л.", "Ольга Р.", "Светлана Д.", "Юлия М.", "Наталья В.", "Екатерина С.", "Ирина П.", "Татьяна Г.", "Анастасия Б.", // i18n: no
                        "Виктория Н.", "Дарья Ф.", "Елена Ж.", "Полина Ш.", "Ксения Т.", "Вера О.", "Людмила Е.", "Яна Ц.", "Софья А.", "Кира Х.", // i18n: no
                        "Алёна З.", "Валерия У.", "Маргарита Ч.", "Лилия И.", "Карина Ю.", "Диана Щ.", "Оксана Э.", "Евгения Я.", "Регина Б.", "Нина Й."] // i18n: no
    static var folders: [(String, String)] { [(String(localized: "Новые"), "#A9D8FF"), (String(localized: "В диалоге"), "#DCC6FF"), (String(localized: "Думает"), "#FFD59E"), (String(localized: "Оплатит позже"), "#FFB8B0"), (String(localized: "Оплатил"), "#A8EDCB"), (String(localized: "Повторный клиент"), "#9EE6E0")] }
    static let leadNames = ["Мария Орлова", "Андрей Ким", "Елизавета Р.", "Павел Смирнов", "Ольга Тихонова", "Роман Белов", "Инна Захарова", "Георгий Л.", "Софья Миронова", "Артём Ф."] // i18n: no
    static var sources: [String] { [String(localized: "Реклама в Instagram"), String(localized: "Сторис партнёра"), String(localized: "Рекомендация"), String(localized: "Пост в Telegram"), "Threads"] }

    struct Partner: Identifiable { let i: Int; let name: String; let leads: Int; let paid: Int; let rev: Double; let conv: Int; let resp: Int; let open: Int; let sd: Int; var id: Int { i } }
    struct Step: Hashable { let folder: Int; let note: String; let date: String }
    struct Lead: Identifiable { let k: Int; let name: String; let folder: Int; let sum: Double; let paid: Double; let first: String; let days: String; let msgs: Int; let buys: Int; let src: String; let chan: String; let came: String; let path: [Step]; let next: String; var id: Int { k } }

    static func partners(_ per: String) -> [Partner] {
        let mult: Double = per == "week" ? 0.25 : (per == "q" ? 3.0 : 1.0)
        var out: [Partner] = []
        for (i, n) in names.enumerated() {
            let sd: Int = (i * 37 + 11) % 97
            let base: Double = 60.0 - Double(i) * 1.6 + Double(sd % 9)
            let leads: Int = max(2, Int((base * mult).rounded()))
            let rate: Double = 0.18 + Double(sd % 13) / 100.0
            let paid: Int = max(0, Int((Double(leads) * rate).rounded()))
            let price: Int = 4200 + (sd % 7) * 600
            let conv: Int = Int((Double(paid) / Double(leads) * 100.0).rounded())
            let open: Int = Int((Double(leads) * 0.3).rounded())
            out.append(Partner(i: i, name: n, leads: leads, paid: paid, rev: Double(paid * price), conv: conv, resp: 3 + sd % 14, open: open, sd: sd))
        }
        return out
    }

    static func leads(_ p: Partner) -> [Lead] {
        var out: [Lead] = []
        for k in 0..<8 {
            let z: Int = (p.sd * (k + 5) + k * 13) % 89
            let fi: Int = (z + k) % folders.count
            let sum: Double = Double(4500 + (z % 6) * 1200)
            var paid: Double = 0
            if fi >= 4 { paid = sum } else if fi == 3 { paid = (sum / 2).rounded() }
            let paidMoney: String = Fmt.money(paid > 0 ? paid : sum)
            let paidText: String = String(localized: "оплата \(paidMoney)")
            let replyMin: Int = 2 + z % 18
            let notes: [String] = [String(localized: "написал(а) первым"), String(localized: "ответили за \(replyMin) мин"), String(localized: "спросил(а) про цену"), String(localized: "обещал(а) оплатить"), paidText, String(localized: "вторая покупка")]
            var path: [Step] = []
            for j in 0...fi {
                let day: Int = 1 + (z + j * 3) % 27
                path.append(Step(folder: j, note: notes[j], date: j < 2 ? String(localized: "\(day) окт") : String(localized: "\(day) ноя")))
            }
            let next: String
            if fi >= 4 { next = String(localized: "Попросить отзыв, предложить следующую покупку") } else if fi == 3 { next = String(localized: "Напомнить об оплате завтра в 10:00") } else { next = String(localized: "Ответить и отправить программу") }
            let chans: [String] = ["Telegram", "Instagram", "WhatsApp"]
            let daysN: Int = 1 + z % 21
            let cameDay: Int = 1 + z % 27
            let buys: Int = fi == 5 ? 2 : (fi == 4 ? 1 : 0)
            out.append(Lead(k: k, name: leadNames[(p.i + k) % leadNames.count], folder: fi, sum: sum, paid: paid, first: String(localized: "\(replyMin) мин"), days: String(localized: "\(daysN) дн"),
                            msgs: 6 + z % 40, buys: buys, src: sources[z % sources.count], chan: chans[(z + k) % 3], came: String(localized: "\(cameDay) окт"), path: path, next: next))
        }
        return out
    }
}

struct PartnersView: View {
    @Environment(Store.self) private var store
    @State private var per = "month"
    @State private var sort = "rev"
    @State private var selected: Int?

    private func value(_ p: PartnerDemo.Partner) -> Double {
        sort == "rev" ? p.rev : (sort == "leads" ? Double(p.leads) : Double(p.conv))
    }

    var body: some View {
        let P = PartnerDemo.partners(per)
        let sorted = P.sorted { value($0) > value($1) }
        let mx = max(1, sorted.first.map(value) ?? 1)
        VStack(spacing: 0) {
            HStack {
                CircleButton(system: "chevron.left", iconSize: 18) { store.pop() }
                Spacer()
                Text("пример для клуба").font(Typo.body(12, .semibold)).foregroundStyle(Pal.apricot)
                    .padding(.horizontal, 12).frame(height: 32).glassCapsule()
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("Партнёры").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg)
                        Spacer()
                        Text("30 человек").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                    }
                    .padding(.horizontal, 4).padding(.top, 14)
                    GlassSegment(items: [("week", String(localized: "Неделя")), ("month", String(localized: "Месяц")), ("q", String(localized: "Квартал"))], selection: $per).padding(.top, 14)
                    HStack(spacing: 8) {
                        Tile(label: String(localized: "лидов"), value: "\(P.reduce(0) { $0 + $1.leads })", valueSize: 20)
                        Tile(label: String(localized: "оплат"), value: "\(P.reduce(0) { $0 + $1.paid })", valueSize: 20)
                        Tile(label: String(localized: "выручка"), value: Fmt.short(P.reduce(0) { $0 + $1.rev }), valueSize: 16)
                    }
                    .padding(.top, 12)
                    HStack {
                        Cap(String(localized: "Рейтинг"))
                        HStack(spacing: 6) {
                            ForEach(["rev", "leads", "conv"], id: \.self) { k in
                                let l: String = k == "rev" ? String(localized: "выручка") : (k == "leads" ? String(localized: "лиды") : "%")
                                Button { withAnimation(.spring(response: 0.35)) { sort = k } } label: {
                                    Text(l).font(Typo.body(12, .semibold)).foregroundStyle(sort == k ? Pal.onAcc : Pal.fg)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(Capsule().fill(sort == k ? Pal.acc : Pal.fg.opacity(0.1)))
                                }
                                .buttonStyle(PressStyle())
                            }
                        }
                        .padding(.top, 12)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { j, p in
                            let pLeads: Int = p.leads
                            let pPaid: Int = p.paid
                            let pConv: Int = p.conv
                            Button { selected = p.i } label: {
                                VStack(spacing: 0) {
                                    if j > 0 { Rectangle().fill(Pal.line).frame(height: 0.5) }
                                    HStack(spacing: 10) {
                                        Text("\(j + 1)").font(Typo.display(13)).foregroundStyle(Pal.fg3).frame(width: 24, alignment: .leading)
                                        Avatar(name: p.name, hue: Double(stableHash(p.name)), size: 36)
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text(p.name).font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg).lineLimit(1)
                                                Spacer()
                                                Text(sort == "rev" ? Fmt.short(p.rev) : (sort == "leads" ? "\(p.leads)" : "\(p.conv)%")).font(Typo.display(14)).foregroundStyle(Pal.fg)
                                            }
                                            Bar(fraction: max(0.03, value(p) / mx), color: j < 3 ? Pal.apricot : Pal.acc, height: 5)
                                            Text("Лиды: \(pLeads) · оплаты: \(pPaid) · \(pConv)%").font(Typo.body(12)).foregroundStyle(Pal.fg2)
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(RowPressStyle())
                        }
                    }
                    .glassRect(24)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sort)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .screenBackground(store.wall)
        .sheet(item: Binding(get: { selected.map { IDBox(id: String($0)) } }, set: { selected = $0.flatMap { Int($0.id) } })) { b in
            PartnerSheet(partner: P[Int(b.id) ?? 0], rank: (sorted.firstIndex { $0.i == Int(b.id) } ?? 0) + 1) { k in
                selected = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.open(.partnerLead(Int(b.id) ?? 0, k)) }
            }
        }
    }
}

struct PartnerSheet: View {
    let partner: PartnerDemo.Partner
    let rank: Int
    let openLead: (Int) -> Void

    var body: some View {
        let p = partner
        SheetBox(title: nil) {
            HStack(spacing: 12) {
                Avatar(name: p.name, hue: Double(stableHash(p.name)), size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(Typo.display(18)).foregroundStyle(Pal.fg)
                    Text("место \(rank) из 30 по выручке").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
            }
            .padding(.horizontal, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                Tile(label: String(localized: "лиды"), value: "\(p.leads)", valueSize: 17, labelSize: 11)
                Tile(label: String(localized: "оплаты"), value: "\(p.paid)", valueSize: 17, labelSize: 11)
                Tile(label: String(localized: "конверсия"), value: "\(p.conv)%", valueSize: 17, labelSize: 11)
                Tile(label: String(localized: "выручка"), value: Fmt.short(p.rev), valueSize: 15, labelSize: 11)
                Tile(label: String(localized: "ответ"), value: String(localized: "\(p.resp) мин"), valueSize: 17, labelSize: 11)
                Tile(label: String(localized: "в работе"), value: "\(p.open)", valueSize: 17, labelSize: 11)
            }
            .padding(.top, 14).padding(.horizontal, 4)
            Cap(String(localized: "Оплаты по неделям")).padding(.horizontal, 4)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<8, id: \.self) { w in
                    UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 6, style: .continuous)
                        .fill(w == 7 ? Pal.acc : Pal.acc.opacity(0.35))
                        .frame(height: CGFloat(18 + (p.sd * (w + 3)) % 60))
                }
            }
            .frame(height: 80, alignment: .bottom)
            .padding(.horizontal, 6)
            Cap(String(localized: "Лиды партнёра")).padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(PartnerDemo.leads(p)) { l in
                    let f = PartnerDemo.folders[l.folder]
                    Button { openLead(l.k) } label: {
                        GroupRow(first: l.k == 0) {
                            Avatar(name: l.name, hue: Double(stableHash(l.name)), size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name).font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg)
                                Text("● " + f.0).font(Typo.body(12, .semibold)).foregroundStyle(Color(css: f.1))
                            }
                            Spacer()
                            Text(Fmt.money(l.sum)).font(Typo.display(13)).foregroundStyle(Pal.fg)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .glassRect(24)
            .padding(.horizontal, 4)
            Text("Переписки партнёров не видны — только цифры").font(Typo.body(12)).foregroundStyle(Pal.fg3).frame(maxWidth: .infinity).padding(.top, 10)
        }
    }
}

struct PartnerLeadView: View {
    @Environment(Store.self) private var store
    let partner: Int
    let lead: Int

    var body: some View {
        let p = PartnerDemo.partners("month")[min(partner, 29)]
        let L = PartnerDemo.leads(p)[min(lead, 7)]
        let f = PartnerDemo.folders[L.folder]
        VStack(spacing: 0) {
            HStack {
                CircleButton(system: "chevron.left", iconSize: 18) { store.pop() }
                Spacer()
                Text(String(localized: "партнёр: \(p.name)")).font(Typo.body(12, .semibold)).foregroundStyle(Pal.fg)
                    .padding(.horizontal, 12).frame(height: 32).glassCapsule()
            }
            .padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 8) {
                        Avatar(name: L.name, hue: Double(stableHash(L.name)), size: 84)
                        Text(L.name).font(Typo.display(22)).foregroundStyle(Pal.fg)
                        HStack(spacing: 6) {
                            Circle().fill(Color(css: f.1)).frame(width: 8, height: 8)
                            Text(f.0).font(Typo.body(13, .semibold))
                        }
                        .foregroundStyle(Color(css: f.1))
                        .padding(.horizontal, 14).frame(height: 30).glassCapsule()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        Tile(label: String(localized: "сумма сделки"), value: Fmt.money(L.sum), valueSize: 20)
                        Tile(label: String(localized: "оплачено"), value: L.paid > 0 ? Fmt.money(L.paid) : "—", valueSize: 20, valueColor: L.paid > 0 ? Pal.mint : Pal.fg)
                        Tile(label: String(localized: "первый ответ"), value: L.first, valueSize: 20)
                        Tile(label: String(localized: "в работе"), value: L.days, valueSize: 20)
                        Tile(label: String(localized: "сообщений"), value: "\(L.msgs)", valueSize: 20)
                        Tile(label: String(localized: "покупок"), value: "\(L.buys)", valueSize: 20)
                    }
                    .padding(.top, 18)
                    Cap(String(localized: "Откуда пришёл"))
                    VStack(spacing: 0) {
                        GroupRow(first: true) { Text("Источник").foregroundStyle(Pal.fg2); Spacer(); Text(L.src).foregroundStyle(Pal.fg) }
                        GroupRow { Text("Канал").foregroundStyle(Pal.fg2); Spacer(); Text(L.chan).foregroundStyle(Pal.fg) }
                        GroupRow { Text("Первое сообщение").foregroundStyle(Pal.fg2); Spacer(); Text(L.came).foregroundStyle(Pal.fg) }
                    }
                    .glassRect(24)
                    Cap(String(localized: "Путь по папкам"))
                    VStack(spacing: 0) {
                        ForEach(L.path, id: \.self) { s in
                            let sf = PartnerDemo.folders[s.folder]
                            HStack(alignment: .top, spacing: 12) {
                                Circle().fill(Color(css: sf.1)).frame(width: 12, height: 12).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sf.0).font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg)
                                    Text(s.note).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                                }
                                Spacer()
                                Text(s.date).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                            }
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .glassRect(24)
                    Cap(String(localized: "Дальше"))
                    HStack(spacing: 10) {
                        Image(systemName: "clock").foregroundStyle(Pal.apricot)
                        Text(L.next).font(Typo.body(15)).foregroundStyle(Pal.fg)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .glassRect(22)
                    Text("Переписки партнёров владелице не видны — только цифры")
                        .font(Typo.body(12)).foregroundStyle(Pal.fg3).frame(maxWidth: .infinity).padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .screenBackground(store.wall)
    }
}
