import SwiftUI

/// Стекло макета: `.lg` — светлое (кнопки, поля, чипы), `.lgd` — тёмное (группы, карточки, листы).
/// На iOS 26 — настоящий Liquid Glass (`glassEffect`), ниже — материал с той же кромкой.
enum GlassKind {
    case light, dark, bar
}

private struct GlassFallback<S: Shape>: View {
    let shape: S
    let kind: GlassKind
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light: Bool = scheme == .light
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(tint(light: light))
            shape.stroke(LinearGradient(colors: edge(light: light), startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(light ? 0.08 : (kind == .dark ? 0.18 : 0.22)), radius: 12, y: 6)
    }

    private func tint(light: Bool) -> Color {
        switch kind {
        case .light: return light ? Color.white.opacity(0.45) : Color.white.opacity(0.10)
        case .dark: return light ? Color.white.opacity(0.62) : Color(red: 22 / 255, green: 18 / 255, blue: 30 / 255).opacity(0.55)
        case .bar: return light ? Color.white.opacity(0.55) : Color(red: 36 / 255, green: 28 / 255, blue: 42 / 255).opacity(0.40)
        }
    }

    private func edge(light: Bool) -> [Color] {
        if light { return [Color.black.opacity(0.10), Color.black.opacity(0.05)] }
        return [Color.white.opacity(kind == .dark ? 0.22 : 0.42), Color.white.opacity(0.08)]
    }
}

/// Стекло с учётом темы: в светлой — белёсый оттенок вместо тёмного.
private struct GlassMod<S: Shape>: ViewModifier {
    let kind: GlassKind
    let shape: S
    let interactive: Bool
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass26, in: shape)
        } else {
            content.background(GlassFallback(shape: shape, kind: kind))
        }
        #else
        content.background(GlassFallback(shape: shape, kind: kind))
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass26: Glass {
        let light: Bool = scheme == .light
        switch kind {
        case .light:
            return interactive ? Glass.regular.interactive() : Glass.regular
        case .dark:
            return Glass.regular.tint(light ? Color.white.opacity(0.5) : Color(red: 0.07, green: 0.06, blue: 0.11).opacity(0.55))
        case .bar:
            return Glass.regular.tint(light ? Color.white.opacity(0.4) : Color(red: 0.12, green: 0.09, blue: 0.15).opacity(0.35)).interactive()
        }
    }
    #endif
}

extension View {
    func glass<S: Shape>(_ kind: GlassKind = .light, in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassMod(kind: kind, shape: shape, interactive: interactive))
    }

    func glassCapsule(_ kind: GlassKind = .light, interactive: Bool = false) -> some View {
        glass(kind, in: Capsule(), interactive: interactive)
    }

    func glassRect(_ radius: CGFloat, _ kind: GlassKind = .dark) -> some View {
        glass(kind, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Главная кнопка макета (`.pri`): светло-сиреневая заливка с бликом.
struct PrimaryFill: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Pal.onAcc)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Pal.acc)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.7), lineWidth: 0.8).blendMode(.overlay))
                    .shadow(color: Color(red: 150 / 255, green: 160 / 255, blue: 1).opacity(0.3), radius: 9, y: 6)
            )
    }
}

extension View {
    func primaryFill(_ radius: CGFloat = 18) -> some View { modifier(PrimaryFill(radius: radius)) }
}

/// Нажатие с пружиной — у всех кастомных кнопок.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Строка группы (`.ln`) с разделителем сверху.
struct GroupRow<Content: View>: View {
    var first = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Pal.line).frame(height: 0.5) }
            HStack(spacing: 12) { content() }
                .font(Typo.body(16))
                .frame(minHeight: 52)
                .padding(.horizontal, 16)
        }
    }
}

/// Подпись секции (`.cap`).
struct Cap: View {
    let text: String
    var color: Color = Pal.fg2
    init(_ text: String, color: Color = Pal.fg2) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased())
            .font(Typo.body(12, .semibold))
            .tracking(0.96)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 22)
            .padding(.bottom, 8)
    }
}

/// Цветная иконка строки (`.ic`).
struct RowIcon: View {
    let system: String
    let color: Color
    var body: some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Pal.ink)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color))
    }
}

/// Плитка статистики (`.tile`).
struct Tile: View {
    let label: String
    let value: String
    var valueSize: CGFloat = 24
    var valueColor: Color = Pal.fg
    var labelSize: CGFloat = 12
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.body(labelSize)).foregroundStyle(Pal.fg2).lineLimit(1)
            Text(value).font(Typo.display(valueSize)).tracking(-0.03 * valueSize).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassRect(22)
    }
}

/// Переключатель макета (`.sw`).
struct GlassSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() }
            haptic()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Pal.mint : Pal.fg.opacity(0.18))
                Circle().fill(.white).frame(width: 28, height: 28).shadow(color: .black.opacity(0.25), radius: 3, y: 2).padding(2)
            }
            .frame(width: 52, height: 32)
        }
        .buttonStyle(.plain)
    }
}

/// Сегменты (`.seg`).
struct GlassSegment<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = item.0 }
                    haptic()
                } label: {
                    Text(item.1)
                        .font(Typo.body(14, .semibold))
                        .foregroundStyle(selection == item.0 ? Pal.ink : Pal.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selection == item.0 {
                                Capsule().fill(Color.white.opacity(0.92)).shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassCapsule()
    }
}

/// Круглая стеклянная кнопка (`.circ.lg`).
struct CircleButton: View {
    let system: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 19
    /// подпись для VoiceOver; если нет — по значку («Назад», «Закрыть»…)
    var label: String? = nil
    let action: () -> Void
    /// растёт с размером текста в настройках iPhone (не больше чем в 1,4 раза, чтобы шапки не разваливались)
    @ScaledMetric(relativeTo: .body) private var k: CGFloat = 1

    var body: some View {
        let s: CGFloat = min(max(k, 1), 1.4)
        Button(action: { haptic(); action() }) {
            Image(systemName: system)
                .font(.system(size: iconSize * s, weight: .semibold))
                .foregroundStyle(Pal.fg)
                .frame(width: size * s, height: size * s)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(.light, in: Circle(), interactive: true)
        .accessibilityLabel(label ?? CircleButton.defaultLabel(system))
    }

    static func defaultLabel(_ system: String) -> String {
        switch system {
        case "chevron.left": return String(localized: "Назад")
        case "xmark": return String(localized: "Закрыть")
        case "ellipsis", "ellipsis.circle": return String(localized: "Ещё")
        case "plus": return String(localized: "Добавить")
        case "magnifyingglass": return String(localized: "Поиск")
        case "phone", "phone.fill": return String(localized: "Позвонить")
        case "square.and.arrow.up": return String(localized: "Поделиться")
        case "trash": return String(localized: "Удалить")
        case "checkmark": return String(localized: "Готово")
        default: return String(localized: "Кнопка")
        }
    }
}

struct PillButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    var body: some View {
        Button(action: { haptic(); action() }) {
            HStack(spacing: 6) { label() }
                .font(Typo.body(15, .medium))
                .foregroundStyle(Pal.fg)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .glassCapsule(interactive: true)
    }
}
