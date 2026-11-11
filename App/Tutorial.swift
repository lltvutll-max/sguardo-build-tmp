import SwiftUI

// MARK: - экраны первого запуска

struct OnboardPage {
    let icon: String
    let color: Color
    let title: String
    let text: String
}

/// 4 экрана «что умеет приложение». Показываются один раз после входа и из «Профиль → Как пользоваться».
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var page = 0

    private var pages: [OnboardPage] {
        [
            OnboardPage(icon: "bubble.left.and.bubble.right.fill", color: Pal.acc,
                        title: String(localized: "Все чаты в одном месте"),
                        text: String(localized: "WhatsApp, Telegram, Instagram и Threads — в одном списке. Отвечайте клиентам, не переключаясь между приложениями.")),
            OnboardPage(icon: "folder.fill", color: Pal.sky,
                        title: String(localized: "Папки и метки"),
                        text: String(localized: "Папка — этап сделки: новые, думает, оплатил. Метка — любая пометка, например «VIP». Смахните чат влево — «В папку».")),
            OnboardPage(icon: "globe", color: Pal.mint,
                        title: String(localized: "Перевод в чате"),
                        text: String(localized: "Клиент пишет на другом языке — его сообщения переводятся сами, а ваш ответ уйдёт на его языке. Значок 🌐 в шапке чата включает и выключает перевод.")),
            OnboardPage(icon: "mic.fill", color: Pal.apricot,
                        title: String(localized: "Голосовые и кружки"),
                        text: String(localized: "Удерживайте кнопку записи — пишется голосовое. В Telegram короткое нажатие переключает на кружок. Голосовое клиента можно прочитать текстом — кнопка «→A».")),
        ]
    }

    var body: some View {
        let list: [OnboardPage] = pages
        let last: Bool = page >= list.count - 1
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { Prefs.shared.finishOnboarding() } label: {
                    Text("Пропустить").font(Typo.body(15, .medium)).foregroundStyle(Pal.fg2)
                        .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("onboard-skip")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            TabView(selection: $page) {
                ForEach(list.indices, id: \.self) { i in
                    pageView(list[i]).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                haptic()
                if last {
                    Prefs.shared.finishOnboarding()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { page += 1 }
                }
            } label: {
                Text(last ? String(localized: "Начать работу") : String(localized: "Дальше"))
                    .font(Typo.body(17, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .frame(minHeight: 52)
                    .primaryFill(20)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .accessibilityIdentifier("onboard-next")
        }
        .screenBackground(store.wall)
    }

    private func pageView(_ p: OnboardPage) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: p.icon)
                    .font(.icon(44, .semibold))
                    .foregroundStyle(p.color)
                    .frame(width: 120, height: 120)
                    .glass(.dark, in: Circle())
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                Text(p.title)
                    .font(Typo.display(26))
                    .tracking(-0.6)
                    .foregroundStyle(Pal.fg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(p.text)
                    .font(Typo.body(17))
                    .foregroundStyle(Pal.fg2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - подсказки на месте (coach marks)

enum CoachDemo { case swipeRight, swipeLeft, hold, select, translate, holdBubble, record }

struct CoachStep {
    let demo: CoachDemo
    let title: String
    let text: String
}

enum CoachSteps {
    static var chats: [CoachStep] {
        [
            CoachStep(demo: .swipeRight, title: String(localized: "Смахните чат вправо"),
                      text: String(localized: "Закрепить сверху и отметить прочитанным или непрочитанным. Смахнёте до конца — сработает первое действие.")),
            CoachStep(demo: .swipeLeft, title: String(localized: "Смахните чат влево"),
                      text: String(localized: "«В папку» — переложить клиента на другой этап. «Ещё» — убрать из папки, карточка клиента и другое.")),
            CoachStep(demo: .hold, title: String(localized: "Удержите чат"),
                      text: String(localized: "Откроется меню со всеми действиями: закрепить, прочитано, папка, карточка клиента.")),
            CoachStep(demo: .select, title: String(localized: "Кнопка «Выбрать» сверху"),
                      text: String(localized: "Отметьте сразу несколько чатов — и переложите их в папку, прочитайте или закрепите одним нажатием.")),
        ]
    }

    static var chat: [CoachStep] {
        [
            CoachStep(demo: .translate, title: String(localized: "Перевод 🌐"),
                      text: String(localized: "Если клиент пишет на другом языке, в шапке появится значок 🌐 с языком. Его сообщения переводятся, ваш ответ уйдёт на его языке. Нажмите на значок, чтобы выключить.")),
            CoachStep(demo: .holdBubble, title: String(localized: "Удержите сообщение"),
                      text: String(localized: "Ответить, скопировать или удалить у всех. Смахните пузырь влево — быстрый ответ.")),
            CoachStep(demo: .record, title: String(localized: "Кнопка записи"),
                      text: String(localized: "Удерживайте — пишется голосовое, отпустите — отправится. Влево — отмена, вверх — запись без рук. В Telegram короткое нажатие переключает микрофон и камеру (кружок).")),
        ]
    }
}

/// Затемнение + карточка с живой мини-демонстрацией жеста. Тап по фону или «Дальше» — следующий шаг.
struct CoachOverlay: View {
    let key: String
    let steps: [CoachStep]
    @State private var i: Int

    init(key: String, steps: [CoachStep], start: Int = 0) {
        self.key = key
        self.steps = steps
        _i = State(initialValue: max(0, min(start, steps.count - 1)))
    }

    var body: some View {
        let step: CoachStep = steps[min(i, steps.count - 1)]
        let last: Bool = i >= steps.count - 1
        let stepNo: Int = i + 1
        let stepTotal: Int = steps.count
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { next() }
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                CoachDemoView(demo: step.demo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .id(i)
                    .accessibilityHidden(true)
                Text(step.title)
                    .font(Typo.body(19, .semibold))
                    .foregroundStyle(Pal.fg)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.text)
                    .font(Typo.body(15))
                    .foregroundStyle(Pal.fg2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(stepNo) из \(stepTotal)")
                    .font(Typo.body(13, .medium))
                    .foregroundStyle(Pal.fg3)
                HStack(spacing: 10) {
                    if !last {
                        Button { Prefs.shared.markSeen(key) } label: {
                            Text("Пропустить").font(Typo.body(15, .medium)).foregroundStyle(Pal.fg2)
                                .frame(maxWidth: .infinity).frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                    Button { next() } label: {
                        Text(last ? String(localized: "Понятно") : String(localized: "Дальше"))
                            .font(Typo.body(16, .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .primaryFill(18)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("coach-next")
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Pal.page)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Pal.line, lineWidth: 1))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
            .accessibilityElement(children: .contain)
        }
        .transition(.opacity)
    }

    private func next() {
        haptic()
        if i >= steps.count - 1 {
            Prefs.shared.markSeen(key)
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { i += 1 }
        }
    }
}

/// Мини-анимации жестов для подсказок (без настоящих данных).
struct CoachDemoView: View {
    let demo: CoachDemo
    @State private var on = false

    var body: some View {
        content
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.4)) { on = true }
            }
    }

    @ViewBuilder private var content: some View {
        switch demo {
        case .swipeRight: swipeDemo(right: true)
        case .swipeLeft: swipeDemo(right: false)
        case .hold: holdDemo
        case .select: selectDemo
        case .translate: translateDemo
        case .holdBubble: bubbleDemo
        case .record: recordDemo
        }
    }

    private func miniRow(checked: Bool? = nil) -> some View {
        HStack(spacing: 10) {
            if let checked {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.icon(18))
                    .foregroundStyle(checked ? Pal.acc : Pal.fg3)
            }
            Circle().fill(Color.avatar(hue: 210)).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Pal.fg.opacity(0.55)).frame(width: 90, height: 8)
                Capsule().fill(Pal.fg.opacity(0.25)).frame(width: 140, height: 7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 260, height: 54)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.page))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Pal.line, lineWidth: 1))
    }

    private func actionBlock(_ icon: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.icon(15, .semibold))
            Text(title).font(Typo.body(11, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .frame(width: 70, height: 54)
        .background(color)
    }

    private func swipeDemo(right: Bool) -> some View {
        let shift: CGFloat = on ? (right ? 140 : -140) : 0
        return ZStack {
            HStack(spacing: 0) {
                if right {
                    actionBlock("pin.fill", String(localized: "Закрепить"), Color(hex: 0xE09A3E))
                    actionBlock("checkmark.message.fill", String(localized: "Прочитано"), Color(hex: 0x2E9E6A))
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    actionBlock("folder.fill", String(localized: "В папку"), Color(hex: 0x6A70E0))
                    actionBlock("ellipsis", String(localized: "Ещё"), Color(hex: 0x7A7685))
                }
            }
            .frame(width: 260, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            miniRow().offset(x: shift)
            Image(systemName: "hand.point.up.left.fill")
                .font(.icon(26))
                .foregroundStyle(Pal.fg)
                .shadow(color: .black.opacity(0.3), radius: 4)
                .offset(x: (right ? -40 : 40) + shift, y: 30)
        }
    }

    private var holdDemo: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                miniRow().frame(width: 150).clipped()
                Circle().stroke(Pal.acc, lineWidth: 3)
                    .frame(width: on ? 46 : 22, height: on ? 46 : 22)
                    .opacity(on ? 0.2 : 0.9)
            }
            .frame(width: 150)
            .scaleEffect(on ? 1.04 : 1)
            menuMock([String(localized: "Закрепить"), String(localized: "В папку"), String(localized: "Карточка")])
                .opacity(on ? 1 : 0.15)
        }
    }

    private func menuMock(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.indices, id: \.self) { k in
                Text(items[k])
                    .font(Typo.body(12, .medium))
                    .foregroundStyle(Pal.fg)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(width: 104, height: 28, alignment: .leading)
                if k < items.count - 1 { Rectangle().fill(Pal.line).frame(width: 104, height: 0.5) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.page))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Pal.line, lineWidth: 1))
    }

    private var selectDemo: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.icon(14))
                Text("Выбрать").font(Typo.body(13, .semibold))
            }
            .foregroundStyle(Pal.fg)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Pal.fg.opacity(on ? 0.2 : 0.1)))
            miniRow(checked: on).scaleEffect(0.85).frame(height: 46)
            miniRow(checked: true).scaleEffect(0.85).frame(height: 46)
        }
    }

    private var translateDemo: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.icon(12, .semibold))
                Text("EN").font(Typo.body(13, .semibold))
            }
            .foregroundStyle(Pal.ink)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color(hex: 0xA8EDCB)))
            .scaleEffect(on ? 1.1 : 1)
            Text(on ? String(localized: "Здравствуйте! Сколько стоит?") : "Hello! How much is it?")
                .font(Typo.body(14))
                .foregroundStyle(Pal.fg)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.fg.opacity(0.1)))
        }
    }

    private var bubbleDemo: some View {
        HStack(spacing: 10) {
            Text("Оплатила, проверьте 🙏")
                .font(Typo.body(13))
                .foregroundStyle(Pal.fg)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.fg.opacity(0.12)))
                .scaleEffect(on ? 1.05 : 1)
                .offset(x: on ? -8 : 0)
            menuMock([String(localized: "Ответить"), String(localized: "Скопировать"), String(localized: "Удалить у всех")])
                .opacity(on ? 1 : 0.15)
        }
    }

    private var recordDemo: some View {
        HStack(spacing: 18) {
            Image(systemName: "chevron.left.2").font(.icon(15, .semibold)).foregroundStyle(Pal.fg3)
            ZStack {
                Circle().fill(Pal.acc.opacity(0.25)).frame(width: on ? 92 : 60, height: on ? 92 : 60)
                Circle().fill(Pal.acc).frame(width: 56, height: 56)
                Image(systemName: on ? "video.fill" : "mic.fill").font(.icon(22, .semibold)).foregroundStyle(Pal.onAcc)
            }
            .frame(width: 96, height: 96)
            VStack(spacing: 2) {
                Image(systemName: "lock.fill").font(.icon(13))
                Image(systemName: "chevron.up").font(.icon(13, .semibold))
            }
            .foregroundStyle(Pal.fg3)
        }
    }
}

// MARK: - выбор папки со списка чатов

/// «Папки» в шапке чатов: показать чаты одной папки или перейти к настройке папок.
struct FolderPickerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private func count(_ folderId: String?) -> Int {
        let all: [Conversation] = store.state.conversations
        guard let folderId else { return all.count }
        return all.filter { store.contact($0.contactId)?.folderId == folderId }.count
    }

    private func chatsText(_ n: Int) -> String { String(localized: "\(n) чатов") }

    var body: some View {
        SheetBox(title: String(localized: "Папки"), subtitle: String(localized: "Показать чаты одной папки")) {
            SheetOption(icon: "tray.full", title: String(localized: "Все чаты"), subtitle: chatsText(count(nil)), on: store.chatFolder == "all", action: {
                withAnimation(.spring(response: 0.3)) { store.chatFolder = "all" }
                dismiss()
            }) {
                if store.chatFolder == "all" { Image(systemName: "checkmark").foregroundStyle(Pal.acc) }
            }
            ForEach(store.folders) { f in
                SheetOption(icon: "circle.fill", iconColor: Color(css: f.color), title: f.name, subtitle: chatsText(count(f.id)), on: store.chatFolder == f.id, action: {
                    withAnimation(.spring(response: 0.3)) { store.chatFolder = f.id }
                    dismiss()
                }) {
                    if store.chatFolder == f.id { Image(systemName: "checkmark").foregroundStyle(Pal.acc) }
                }
            }
            SheetOption(icon: "slider.horizontal.3", iconColor: Pal.acc, title: String(localized: "Настроить папки и метки"), color: Pal.acc, action: {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.open(.folders) }
            })
        }
    }
}
