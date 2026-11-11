import SwiftUI

/// Заглушки на время первой загрузки (копии на диске ещё нет): серые строки вместо пустого экрана и спиннера.

struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Pal.fg.opacity(0.12))
            .frame(width: width, height: height)
    }
}

/// Мягкое «дыхание» заглушек; при «Уменьшить движение» — без анимации.
struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.5 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Строка-заглушка в форме строки списка чатов.
struct ChatRowSkeleton: View {
    var nameWidth: CGFloat = 140
    var textWidth: CGFloat = 210

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Pal.fg.opacity(0.12)).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SkeletonBar(width: nameWidth, height: 13)
                    Spacer(minLength: 8)
                    SkeletonBar(width: 36, height: 10)
                }
                SkeletonBar(width: textWidth, height: 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Список чатов при самой первой загрузке.
struct ChatListSkeleton: View {
    var rows: Int = 8

    private func nameWidth(_ i: Int) -> CGFloat {
        let widths: [CGFloat] = [140, 110, 165, 95, 130, 150, 120, 105]
        return widths[i % widths.count]
    }

    private func textWidth(_ i: Int) -> CGFloat {
        let widths: [CGFloat] = [210, 170, 230, 150, 190, 205, 160, 220]
        return widths[i % widths.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { (i: Int) in
                ChatRowSkeleton(nameWidth: nameWidth(i), textWidth: textWidth(i))
            }
        }
        .modifier(SkeletonPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загружаем чаты…"))
    }
}

/// Карточки-заглушки (рассылка и другие списки карточек).
struct CardListSkeleton: View {
    var rows: Int = 4

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { (_: Int) in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBar(width: 170, height: 14)
                    SkeletonBar(width: 240, height: 11)
                    SkeletonBar(width: 120, height: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Pal.fg.opacity(0.06)))
            }
        }
        .modifier(SkeletonPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загружаем…"))
    }
}
