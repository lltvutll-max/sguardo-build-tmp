import SwiftUI
import UIKit

// Токены из утверждённого макета (sguardo-demo-template.html, :root).
// Цвета двухрежимные: тёмная тема — как в макете, светлая — тёмный текст и более насыщенные акценты
// (контраст ≥4:1 и с белым фоном, и с тёмным текстом на заливке). Чат всегда тёмный (см. destinations()).
enum Pal {
    static let ink = Color(hex: 0x0A0A0A)
    static let fg = dyn(0xFFFFFF, 0x15121F)
    static let fg2 = dyn(0xFFFFFF, 0x15121F, darkAlpha: 0.7, lightAlpha: 0.72)
    static let fg3 = dyn(0xFFFFFF, 0x15121F, darkAlpha: 0.5, lightAlpha: 0.56)
    static let acc = dyn(0xC9CEFF, 0x6A70E0)
    static let mint = dyn(0xA8EDCB, 0x268A5C)
    static let rose = dyn(0xFFB8B0, 0xD2554B)
    static let apricot = dyn(0xFFD59E, 0xB8730F)
    static let sky = dyn(0xA9D8FF, 0x2F7FC4)
    static let lav = dyn(0xDCC6FF, 0x8A5CD6)
    static let teal = dyn(0x9EE6E0, 0x1E8C85)
    static let danger = dyn(0xFF9F94, 0xD13B2E)
    static let line = dyn(0xFFFFFF, 0x15121F, darkAlpha: 0.1, lightAlpha: 0.1)
    static let page = dyn(0x0B0A12, 0xF3F1F8)
    static let chipOn = dyn(0xF4F2FF, 0xDCDDFB)
    /// текст на акцентной заливке (кнопки, счётчики): тёмный в тёмной теме, белый в светлой
    static let onAcc = dyn(0x0A0A0A, 0xFFFFFF)
    /// обводка значка сети на аватарке — под цвет фона списка
    static let ring = dyn(0x1A1622, 0xF6F4FB)

    /// Палитра меток и цветов папок (как в вебе).
    static let labelHex = ["#FFD59E", "#A9D8FF", "#DCC6FF", "#FFB8B0", "#A8EDCB", "#9EE6E0"]
    static let folderHex = ["#A9D8FF", "#DCC6FF", "#FFD59E", "#FFB8B0", "#A8EDCB", "#9EE6E0", "#FF9F94", "#B9B2B5", "#C9CEFF"]

    /// Цвет, который сам меняется со светлой/тёмной темой (по colorScheme окружения).
    static func dyn(_ dark: UInt32, _ light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        let d: UIColor = uiColor(dark, darkAlpha)
        let l: UIColor = uiColor(light, lightAlpha)
        return Color(uiColor: UIColor(dynamicProvider: { (t: UITraitCollection) -> UIColor in
            t.userInterfaceStyle == .light ? l : d
        }))
    }

    static func uiColor(_ hex: UInt32, _ alpha: CGFloat) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Font {
    /// Иконка, которая растёт вместе с размером текста в настройках iPhone (вместо .system(size:)).
    static func icon(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let style: Font.TextStyle
        switch size {
        case ..<11.5: style = .caption2
        case ..<12.5: style = .caption
        case ..<13.5: style = .footnote
        case ..<15.5: style = .subheadline
        case ..<17.5: style = .body
        case ..<20.5: style = .title3
        case ..<24.5: style = .title2
        default: style = .title
        }
        return Font.system(style).weight(weight)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// "#RRGGBB" / "#RGB" из данных кабинета; непонятное — серый.
    init(css: String?) {
        var s = (css ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 6, let v = UInt32(s, radix: 16) {
            self.init(hex: v)
        } else {
            self.init(hex: 0xB9B2B5)
        }
    }

    /// hsl(h 75% 82%) из макета — пастельный фон аватарки.
    static func avatar(hue: Double) -> Color {
        let l = 0.82, s = 0.75
        let v = l + s * min(l, 1 - l)
        let sv = v == 0 ? 0 : 2 * (1 - l / v)
        return Color(hue: (hue.truncatingRemainder(dividingBy: 360)) / 360, saturation: sv, brightness: v)
    }
}

enum Typo {
    /// Unbounded — заголовки и цифры.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Unbounded-Bold"
        case .medium, .regular, .light: name = "Unbounded-Medium"
        default: name = "Unbounded-SemiBold"
        }
        return .custom(name, size: size)
    }

    /// Onest — текст.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Onest-Bold"
        case .semibold: name = "Onest-SemiBold"
        case .medium: name = "Onest-Medium"
        default: name = "Onest-Regular"
        }
        return .custom(name, size: size)
    }
}

/// Хэш строки как в вебе (hue в макете) — для меток без цвета.
func stableHash(_ s: String) -> Int {
    var h = 0
    for u in s.unicodeScalars { h = (h &* 31 &+ Int(u.value)) % 360 }
    return abs(h)
}

func labelColor(_ name: String) -> Color {
    Color(css: Pal.labelHex[stableHash(name) % Pal.labelHex.count])
}

func initials(_ name: String) -> String {
    let cleaned = name.unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == " " }
    let parts = String(String.UnicodeScalarView(cleaned)).split(separator: " ").map(String.init)
    guard let first = parts.first, !first.isEmpty else { return "?" }
    if parts.count > 1, let a = first.first, let b = parts[1].first { return "\(a)\(b)".uppercased() }
    return String(first.prefix(2)).uppercased()
}

func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}
