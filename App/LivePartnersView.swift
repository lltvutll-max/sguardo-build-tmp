import SwiftUI

struct CabinetModules: Decodable {
    struct Flags: Decodable {
        let outreach: Bool
        let partners: Bool
    }
    let modules: Flags
}

private struct ClubReport: Decodable {
    struct Partner: Decodable, Identifiable {
        let id: String
        let name: String
        let currency: String
        let leads: Int
        let payments: Int
        let revenue: Double
        let conversion: Double
    }
    let partners: [Partner]
}

struct PartnerDestination: View {
    @Environment(Store.self) private var store

    var body: some View {
        if store.fixture { PartnersView() } else { LivePartnersView() }
    }
}

struct LivePartnersView: View {
    @Environment(Store.self) private var store
    @State private var period = 30
    @State private var report: ClubReport?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CircleButton(system: "chevron.left", iconSize: 18) { store.pop() }
                Text("Партнёры").font(Typo.display(24)).foregroundStyle(Pal.fg)
                Spacer()
            }
            GlassSegment(items: [(7, String(localized: "Неделя")), (30, String(localized: "Месяц")), (90, String(localized: "Квартал"))], selection: $period)
            if let report {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if report.partners.isEmpty {
                            Text("В клубе пока нет партнёров").foregroundStyle(Pal.fg2)
                        }
                        ForEach(report.partners.sorted { $0.leads > $1.leads }) { partner in
                            row(partner)
                        }
                    }
                }
                .refreshable { await load(period) }
            } else if failed {
                Button("Повторить загрузку") { Task { await load(period) } }
                Spacer()
            } else {
                ProgressView().tint(Pal.fg)
                Spacer()
            }
        }
        .padding(16)
        .screenBackground(store.wall)
        .task(id: period) { await load(period) }
    }

    private func row(_ partner: ClubReport.Partner) -> some View {
        let leads: Int = partner.leads
        let pays: Int = partner.payments
        let conv: Int = Int((partner.conversion * 100).rounded())
        return         VStack(alignment: .leading, spacing: 8) {
            Text(partner.name).font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg)
            Text("Лиды: \(leads) · оплаты: \(pays) · \(conv)%")
                .font(Typo.body(13)).foregroundStyle(Pal.fg2)
            Text(partner.revenue, format: .currency(code: partner.currency))
                .font(Typo.body(15, .semibold)).foregroundStyle(Pal.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).glassRect(20)
    }

    private func load(_ days: Int) async {
        report = nil
        failed = false
        do {
            let result = try await API.get(ClubReport.self, "/api/partners/", query: [.init(name: "days", value: String(days))])
            guard !Task.isCancelled, days == period else { return }
            report = result
        } catch {
            if !Task.isCancelled, days == period { failed = true }
        }
    }
}
