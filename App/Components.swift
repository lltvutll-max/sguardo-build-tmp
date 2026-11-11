import SwiftUI

struct NetInfo {
    let name: String
    let color: Color
    let symbol: String

    static func of(_ net: String?) -> NetInfo {
        switch net {
        case "whatsapp": return NetInfo(name: "WhatsApp", color: Color(hex: 0x25D366), symbol: "phone.fill")
        case "instagram": return NetInfo(name: "Instagram", color: Color(hex: 0xDD2A7B), symbol: "camera.fill")
        case "threads": return NetInfo(name: "Threads", color: Color(hex: 0x111111), symbol: "at")
        case "tiktok": return NetInfo(name: "TikTok", color: Color(hex: 0x111111), symbol: "music.note")
        default: return NetInfo(name: "Telegram", color: Color(hex: 0x2AABEE), symbol: "paperplane.fill")
        }
    }
}

struct Avatar: View {
    let name: String
    let hue: Double
    var url: String? = nil
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle().fill(Color.avatar(hue: hue))
            Text(initials(name))
                .font(Typo.display(size * 0.3))
                .foregroundStyle(Pal.ink)
            if let url, !url.isEmpty {
                RemoteImage(raw: url, quiet: true)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.6).blendMode(.overlay))
    }
}

struct NetBadge: View {
    let net: String
    var body: some View {
        let n = NetInfo.of(net)
        Image(systemName: n.symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .accessibilityLabel(n.name)
            .background(Circle().fill(n.net == "instagram" ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF58529), Color(hex: 0xDD2A7B), Color(hex: 0x8134AF)], startPoint: .bottomLeading, endPoint: .topTrailing)) : AnyShapeStyle(n.color)))
            .overlay(Circle().stroke(Pal.ring, lineWidth: 2))
    }
}

extension NetInfo {
    var net: String {
        switch name {
        case "WhatsApp": return "whatsapp"
        case "Instagram": return "instagram"
        case "Threads": return "threads"
        case "TikTok": return "tiktok"
        default: return "telegram"
        }
    }
}

struct FolderTag: View {
    let folder: Folder?
    var body: some View {
        let c = Color(css: folder?.color)
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(folder?.name ?? String(localized: "Без папки")).font(Typo.body(12, .semibold)).lineLimit(1)
        }
        .foregroundStyle(c)
        .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Pal.fg.opacity(0.07)))
    }
}

struct Chip: View {
    let text: String
    var dot: Color? = nil
    var count: String? = nil
    var on = false
    var height: CGFloat = 36
    var fontSize: CGFloat = 14
    var textColor: Color? = nil
    var fill: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(text).font(Typo.body(fontSize, .semibold)).lineLimit(1)
                if let count { Text(count).font(Typo.body(fontSize, .semibold)).opacity(0.65) }
            }
            .foregroundStyle(on || fill != nil ? Pal.ink : (textColor ?? Pal.fg))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: height)
            .background {
                if on { Capsule().fill(Pal.chipOn) } else if let fill { Capsule().fill(fill) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .glassCapsule(interactive: true)
    }
}

/// «Telegram · handle» — без длинных цепочек `+` (их не переваривает проверка типов).
func joinHandle(_ base: String, _ handle: String?) -> String {
    guard let h = handle, !h.isEmpty else { return base }
    return base + " · " + h
}

// MARK: - форматирование

/// Локаль интерфейса: язык, на котором реально показано приложение (ru/en/de/…; для прочих языков — en) + регион телефона.
/// Даты и названия языков — по ней, чтобы при фолбэке на en не было «турецких» дат в английском интерфейсе.
let uiLocale: Locale = {
    let lang: String = Bundle.main.preferredLocalizations.first ?? "en"
    if let region = Locale.current.region?.identifier { return Locale(identifier: lang + "_" + region) }
    return Locale(identifier: lang)
}()

enum Fmt {
    static func hm(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(uiLocale))
    }

    static func dayLong(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(uiLocale))
    }

    /// Как `when()` в макете: сегодня — время, вчера, день недели, дата.
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let day0 = cal.startOfDay(for: Date())
        if d >= day0 { return hm(d) }
        if d >= day0.addingTimeInterval(-86400) { return String(localized: "вчера") }
        if d >= day0.addingTimeInterval(-6 * 86400) { return d.formatted(.dateTime.weekday(.abbreviated).locale(uiLocale)) }
        return dayLong(d)
    }

    static func remShort(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return hm(d) }
        return dayLong(d) + " " + hm(d)
    }

    static func whenFull(_ d: Date) -> String {
        let cal = Calendar.current
        let t: String = hm(d)
        if cal.isDateInToday(d) { return String(localized: "сегодня, \(t)") }
        if cal.isDateInTomorrow(d) { return String(localized: "завтра, \(t)") }
        let day: String = dayLong(d)
        return String(localized: "\(day), \(t)")
    }

    static func money(_ v: Double, currency: String? = "RUB") -> String {
        let f = NumberFormatter()
        f.locale = uiLocale
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
        return n + " " + symbol(currency)
    }

    static func symbol(_ c: String?) -> String {
        switch (c ?? "RUB").uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "TRY": return "₺"
        case "KZT": return "₸"
        case "UAH": return "₴"
        case "GEL": return "₾"
        default: return "₽"
        }
    }

    static func duration(_ s: TimeInterval?) -> String {
        guard let s else { return "—" }
        if s < 3600 {
            let n: Int = max(1, Int((s / 60).rounded()))
            return String(localized: "\(n) мин")
        }
        if s < 86400 {
            let n: Int = Int((s / 3600).rounded())
            return String(localized: "\(n) ч")
        }
        let n: Int = Int((s / 86400).rounded())
        return String(localized: "\(n) дн")
    }

    static func short(_ v: Double) -> String {
        if v >= 1_000_000 {
            let m: String = (v / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(uiLocale))
            return String(localized: "\(m) млн ₽")
        }
        let k: Int = Int((v / 1000).rounded())
        return String(localized: "\(k) тыс ₽")
    }
}

/// Лист с высотой по содержимому (как `.sheet` макета).
struct SheetBox<Content: View>: View {
    let title: String?
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var height: CGFloat = 300
    /// лист открыт из чата — чат всегда тёмный, и лист тоже
    @Environment(\.sgForceDark) private var forceDark

    var body: some View {
        let scheme: ColorScheme? = forceDark ? ColorScheme.dark : Prefs.shared.colorScheme
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title).font(Typo.display(18)).tracking(-0.36).foregroundStyle(Pal.fg).padding(.horizontal, 8).padding(.bottom, 2)
                }
                if let subtitle {
                    Text(subtitle).font(Typo.body(13)).foregroundStyle(Pal.fg2).padding(.horizontal, 8).padding(.bottom, 6)
                }
                content()
            }
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .background(GeometryReader { g in Color.clear.preference(key: SheetHeightKey.self, value: g.size.height) })
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(SheetHeightKey.self) { h in if h > 0 { height = min(h + 8, 720) } }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .modifier(SheetChrome())
        .preferredColorScheme(scheme)
    }
}

/// На iOS 26 лист — системное стекло; ниже — материал и скругление макета.
struct SheetChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.presentationCornerRadius(34).presentationBackground(.ultraThinMaterial)
        }
    }
}

private struct SheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Пункт листа (`.opt`).
struct SheetOption<Trailing: View>: View {
    let icon: String?
    var iconColor: Color = Pal.fg.opacity(0.7)
    let title: String
    var subtitle: String? = nil
    var on = false
    var color: Color = Pal.fg
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon).font(.icon(17)).foregroundStyle(iconColor).frame(minWidth: 22).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typo.body(16)).foregroundStyle(color).multilineTextAlignment(.leading)
                    if let subtitle { Text(subtitle).font(Typo.body(13)).foregroundStyle(Pal.fg3) }
                }
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Pal.fg.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

extension SheetOption where Trailing == EmptyView {
    init(icon: String?, iconColor: Color = Pal.fg.opacity(0.7), title: String, subtitle: String? = nil, on: Bool = false, color: Color = Pal.fg, action: @escaping () -> Void) {
        self.init(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle, on: on, color: color, action: action, trailing: { EmptyView() })
    }
}

/// Верхняя панель вложенных экранов: «назад» + что-то справа.
struct TopBar<Center: View, Trailing: View>: View {
    let back: () -> Void
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 10) {
            CircleButton(system: "chevron.left", iconSize: 18, action: back)
            Spacer(minLength: 0)
            center()
            Spacer(minLength: 0)
            trailing().frame(minWidth: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(Typo.body(15)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
    }
}

struct Bar: View {
    let fraction: Double
    var color: Color = Pal.acc
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Pal.fg.opacity(0.1))
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Две галочки «доставлено».
struct DoubleCheck: View {
    var size: CGFloat = 11
    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            Image(systemName: "checkmark").offset(x: size * 0.45)
        }
        .font(.system(size: size, weight: .bold))
        .padding(.trailing, size * 0.45)
    }
}
