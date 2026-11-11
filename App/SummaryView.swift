import SwiftUI

struct SummaryView: View {
    @Environment(Store.self) private var store
    @State private var period = "month"

    private struct NetRow: Identifiable { let net: String; let n: Int; var id: String { net } }
    private struct FolderRow: Identifiable { let folder: Folder; let n: Int; var id: String { folder.id } }

    private struct Stats {
        var revenue: Double = 0
        var promised = 0
        var newClients = 0
        var wrote = 0
        var replied = 0
        var ins = 0
        var outs = 0
        var byNet: [NetRow] = []
        var byFolder: [FolderRow] = []
        var total = 0
    }

    private func revenueNote(_ rev: Double, _ promised: Int) -> String {
        let base: String = rev > 0 ? String(localized: "по отмеченным оплатам") : String(localized: "отметь «Оплатил» в карточке клиента — сумма появится тут")
        return promised > 0 ? base + " · " + String(localized: "обещали: \(promised)") : base
    }

    private func barWidth(_ total: CGFloat, count: Int, n: Int, all: Int) -> CGFloat {
        let free: CGFloat = total - CGFloat(max(0, count - 1)) * 2
        let share: CGFloat = CGFloat(n) / CGFloat(max(1, all))
        return max(2, free * share)
    }

    private func percent(_ n: Int, _ total: Int) -> String {
        let p: Double = Double(n) / Double(max(1, total)) * 100
        return "\(Int(p.rounded()))%"
    }

    private func compute() -> Stats {
        let s = store.state
        let span: TimeInterval = period == "week" ? 7 * 86400 : (period == "month" ? 30 * 86400 : 1e12)
        let from = Date().addingTimeInterval(-span)
        var st = Stats()
        st.revenue = s.deals.filter { $0.status == "paid" && $0.day >= from }.reduce(0) { $0 + $1.amount }
        st.promised = s.deals.filter { $0.status == "promised" }.count
        let newContacts = s.contacts.filter { $0.first >= from }
        st.newClients = newContacts.count
        let ev = s.events.filter { $0.date >= from }
        if !s.events.isEmpty {
            st.ins = ev.filter { $0.type == "message_in" }.count
            st.outs = ev.filter { $0.type == "message_out" }.count
            var firstOut: [String: Date] = [:]
            for e in ev where e.type == "message_out" { firstOut[e.contactId] = min(firstOut[e.contactId] ?? e.date, e.date) }
            st.wrote = firstOut.count
            st.replied = Set(ev.filter { e in e.type == "message_in" && (firstOut[e.contactId].map { o in e.date > o } ?? false) }.map(\.contactId)).count
        } else {
            let msgs = s.conversations.flatMap { c in c.messages.filter { $0.date >= from }.map { (c.contactId, $0) } }
            st.ins = msgs.filter { !$0.1.isOut }.count
            st.outs = msgs.count - st.ins
            st.wrote = Set(msgs.filter { $0.1.isOut }.map { $0.0 }).count
            st.replied = s.conversations.filter { c in
                guard let o = c.messages.firstIndex(where: { $0.isOut && $0.date >= from }) else { return false }
                return c.messages[o...].contains { !$0.isOut }
            }.count
        }
        var nets: [String: Int] = [:]
        for c in newContacts { nets[c.source ?? "telegram", default: 0] += 1 }
        st.byNet = nets.sorted { $0.value > $1.value }.map { NetRow(net: $0.key, n: $0.value) }
        st.byFolder = s.folders.map { f in FolderRow(folder: f, n: s.contacts.filter { $0.folderId == f.id }.count) }.filter { $0.n > 0 }
        st.total = s.contacts.count
        return st
    }

    var body: some View {
        let st = compute()
        let cur = store.state.workspace?.currency
        let mx = max(1, st.byNet.map(\.n).max() ?? 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Сводка").font(Typo.display(30)).tracking(-0.9).foregroundStyle(Pal.fg).padding(.horizontal, 4)
                GlassSegment(items: [("week", String(localized: "Неделя")), ("month", String(localized: "Месяц")), ("all", String(localized: "Всё время"))], selection: $period)
                    .padding(.top, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Выручка").font(Typo.body(14)).foregroundStyle(Pal.fg2)
                    Text(Fmt.money(st.revenue, currency: cur))
                        .font(Typo.display(38, .bold)).tracking(-1.9).foregroundStyle(Pal.fg)
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(revenueNote(st.revenue, st.promised))
                        .font(Typo.body(13)).foregroundStyle(Pal.fg2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .glassRect(24)
                .padding(.top, 14)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    Tile(label: String(localized: "Новых клиентов"), value: "\(st.newClients)", labelSize: 13)
                    Tile(label: String(localized: "Мы написали"), value: "\(st.wrote)", labelSize: 13)
                    Tile(label: String(localized: "Ответили"), value: "\(st.replied)", valueColor: Pal.mint, labelSize: 13)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Сообщений").font(Typo.body(13)).foregroundStyle(Pal.fg2)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(st.ins)").font(Typo.display(24)).foregroundStyle(Pal.fg)
                            Text("вх · \(st.outs) исх").font(Typo.body(14, .medium)).foregroundStyle(Pal.fg2).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .glassRect(22)
                }
                .padding(.top, 10)

                Cap(String(localized: "Откуда новые клиенты"))
                VStack(spacing: 14) {
                    if st.byNet.isEmpty {
                        Text("За этот период новых нет").font(Typo.body(15)).foregroundStyle(Pal.fg2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(st.byNet) { row in
                        VStack(spacing: 6) {
                            HStack {
                                Text(NetInfo.of(row.net).name).font(Typo.body(14)).foregroundStyle(Pal.fg)
                                Spacer()
                                Text("\(row.n)").font(Typo.body(14, .bold)).foregroundStyle(Pal.fg)
                            }
                            Bar(fraction: Double(row.n) / Double(mx), color: row.net == "whatsapp" ? Pal.mint : Pal.sky)
                        }
                    }
                }
                .padding(16)
                .glassRect(24)

                Cap(String(localized: "Где сейчас клиенты"))
                VStack(alignment: .leading, spacing: 12) {
                    GeometryReader { g in
                        HStack(spacing: 2) {
                            ForEach(st.byFolder) { row in
                                Rectangle().fill(Color(css: row.folder.color))
                                    .frame(width: barWidth(g.size.width, count: st.byFolder.count, n: row.n, all: st.total))
                            }
                        }
                    }
                    .frame(height: 12)
                    .clipShape(Capsule())
                    FlowLayout(spacing: 10) {
                        ForEach(st.byFolder) { row in
                            HStack(spacing: 6) {
                                Circle().fill(Color(css: row.folder.color)).frame(width: 8, height: 8)
                                Text(row.folder.name).font(Typo.body(13)).foregroundStyle(Pal.fg)
                                Text("\(row.n)").font(Typo.body(13, .bold)).foregroundStyle(Pal.fg)
                                Text(percent(row.n, st.total)).font(Typo.body(13)).foregroundStyle(Pal.fg3)
                            }
                        }
                    }
                }
                .padding(16)
                .glassRect(24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 130)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: period)
        }
        .refreshable { await store.loadState(force: true) }
        .screenBackground(store.wall)
    }
}
