import SwiftUI
import UIKit
import PhotosUI
import AVKit
import AVFoundation
import QuickLook
import UniformTypeIdentifiers

/// Подсказка-намерение по последнему входящему (как intentOf() в макете). Клиент её не видит.
struct Intent {
    enum Kind { case pay, think, reject, price, autoReply }
    let folderKey: String
    let title: String
    let kind: Kind
    let remind: Bool
    let promise: Bool

    /// Текст кнопки. folderName — реальное имя папки с сервера (по folderKey), иначе локализованный запасной вариант.
    func action(folderName: String?) -> String {
        switch kind {
        case .pay:
            let n: String = folderName ?? String(localized: "Оплатит позже")
            return String(localized: "В «\(n)» + напомнить завтра в 10:00")
        case .think:
            let n: String = folderName ?? String(localized: "Думает")
            return String(localized: "Переложить в «\(n)» + напомнить через 2 дня")
        case .reject:
            let n: String = folderName ?? String(localized: "Отказ")
            return String(localized: "Переложить в «\(n)»")
        case .price:
            let n: String = folderName ?? String(localized: "В диалоге")
            return String(localized: "Переложить в «\(n)»")
        case .autoReply:
            return String(localized: "Оставить и напомнить завтра")
        }
    }

    static func of(_ text: String) -> Intent? {
        let t = text.lowercased()
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: .regularExpression) != nil }
        if has("оплач|переведу|скину деньги|ödeme yap|ödeyece|i.ll pay|will pay") { // i18n: no
            return Intent(folderKey: "later", title: String(localized: "Обещает оплатить"), kind: .pay, remind: true, promise: true)
        }
        if has("подума|дорог|посоветуюсь|düşün|pahalı|think about") { // i18n: no
            return Intent(folderKey: "thinking", title: String(localized: "Думает"), kind: .think, remind: true, promise: false)
        }
        if has("не надо|не актуал|не интерес|istemiyor|gerek yok|ilgilenmiyor|not interested") { // i18n: no
            return Intent(folderKey: "rejected", title: String(localized: "Отказ"), kind: .reject, remind: false, promise: false)
        }
        if has("сколько|цена|стоим|прайс|fiyat|ne kadar|price") { // i18n: no
            return Intent(folderKey: "talking", title: String(localized: "Спрашивает цену"), kind: .price, remind: false, promise: false)
        }
        if has("teşekkür|iletişime geçtiğiniz|автоответ|auto.?reply") { // i18n: no
            return Intent(folderKey: "talking", title: String(localized: "Похоже на автоответ"), kind: .autoReply, remind: true, promise: false)
        }
        return nil
    }
}

enum RemPreset: String, CaseIterable {
    case hour, evening, tomorrow, twoDays, monday
    var title: String {
        switch self {
        case .hour: return String(localized: "Через час")
        case .evening: return String(localized: "Сегодня в 18:00")
        case .tomorrow: return String(localized: "Завтра в 10:00")
        case .twoDays: return String(localized: "Через 2 дня")
        case .monday: return String(localized: "В понедельник в 10:00")
        }
    }
    var date: Date {
        let cal = Calendar.current, now = Date()
        func at(_ d: Date, _ h: Int) -> Date { cal.date(bySettingHour: h, minute: 0, second: 0, of: d) ?? d }
        switch self {
        case .hour: return now.addingTimeInterval(3600)
        case .evening:
            let e = at(now, 18)
            return e < now ? e.addingTimeInterval(86400) : e
        case .tomorrow: return at(cal.date(byAdding: .day, value: 1, to: now) ?? now, 10)
        case .twoDays: return at(cal.date(byAdding: .day, value: 2, to: now) ?? now, 10)
        case .monday:
            let wd = cal.component(.weekday, from: now) // 1 — вс, 2 — пн
            var add = (9 - wd) % 7
            if add == 0 { add = 7 }
            return at(cal.date(byAdding: .day, value: add, to: now) ?? now, 10)
        }
    }
}

struct ChatView: View {
    @Environment(Store.self) private var store
    let convId: String
    @State private var trHint = false
    @State private var draft = ""
    /// свои сообщения в пути: часы — отправляется, красный «!» — не ушло (с «Повторить»)
    @State private var pending: [PendingMsg] = []
    /// лента у нижнего края (иначе показываем кнопку «вниз» и копим счётчик новых)
    @State private var atBottom = true
    @State private var newBelow = 0
    /// первое непрочитанное при открытии чата — перед ним разделитель «Непрочитанные сообщения»
    @State private var unreadAnchor: String?
    /// когда открыли чат (подгрузка истории в первые секунды не должна сбивать позицию у непрочитанных)
    @State private var openedAt = Date()
    @State private var scrollH: CGFloat = 0
    /// мультивыбор сообщений
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var forward: ForwardBox?
    @State private var confirmBatchDelete = false
    #if DEBUG
    @State private var fixtureMenu: Message?
    #endif
    @State private var sheet: ChatSheet?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var uploading = false
    @State private var replyTo: Message?
    @State private var viewer: ViewerState?
    @State private var confirmDelete: Message?
    @State private var recorder = VoiceRecorder()
    @State private var videoMode = false
    @StateObject private var cam = CameraModel()
    /// кружок: запись прямо над полем ввода (те же фазы, что у голосового)
    @State private var notePhase: VoiceRecorder.Phase = .idle
    @State private var noteFinish: NoteFinish?
    @State private var pressing = false
    @State private var pressSendMode = false
    @State private var holdTask: Task<Void, Never>?
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    /// удержание прошло порог — кнопка уже растёт под пальцем, пока микрофон/камера поднимаются
    @State private var holdLive = false
    /// отмена записи: на месте «+» коротко мелькает корзина
    @State private var trashFlash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlight: String?
    /// высота панели ввода (с ответом/подсказкой) — нижний отступ ленты, чтобы последнее сообщение не пряталось под ней
    @State private var bottomH: CGFloat = 0
    @FocusState private var inputFocused: Bool

    enum NoteFinish { case send, preview, discard }

    enum ChatSheet: String, Identifiable {
        case folder, remind, templates, attach, translate
        var id: String { rawValue }
    }

    var body: some View {
        let conv = store.conversation(convId)
        let contact = conv.flatMap { store.contact($0.contactId) }
        ZStack {
            if let conv, let contact {
                messagesView(conv)
                noteDim
                noteOverlay
                VStack(spacing: 0) {
                    if selecting {
                        selectionHeader
                    } else {
                        header(conv, contact)
                        translateStatus(contact)
                    }
                    Spacer()
                    Group {
                        if selecting {
                            selectionBar(conv)
                        } else {
                            bottom(conv, contact)
                        }
                    }
                    .background(GeometryReader { g in Color.clear.preference(key: ChatBottomHeightKey.self, value: g.size.height) })
                }
                .onPreferenceChange(ChatBottomHeightKey.self) { h in MainActor.assumeIsolated { if h > 0 { bottomH = h } } }
                if trHint, let lang = foreignLang(contact) {
                    ChatTranslateHint(langName: LangName.acc(lang)) { withAnimation { trHint = false } }
                }
                #if DEBUG
                if let m = fixtureMenu {
                    MessageMenuMock(message: m, canUnsend: canUnsend(m, conv))
                }
                #endif
            } else {
                VStack {
                    TopBar(back: { store.pop() }, center: { EmptyView() }, trailing: { EmptyView() })
                    EmptyNote(text: String(localized: "Чат не найден — возможно, его удалили"))
                    Spacer()
                }
            }
        }
        .screenBackground(store.wall)
        .onAppear {
            rememberUnread()
            store.markRead(convId)
            // подсказка о переводе — один раз, при первом входе в иностранный чат
            if store.translateOn, let c = contact, foreignLang(c) != nil, !UserDefaults.standard.bool(forKey: "trHintSeen") {
                UserDefaults.standard.set(true, forKey: "trHintSeen")
                withAnimation(.spring(response: 0.4).delay(0.3)) { trHint = true }
            }
            if let d = store.drafts[convId] { draft = d }
            #if DEBUG
            applyFixtureScreen()
            #endif
        }
        .onDisappear {
            store.drafts[convId] = draft
            holdTask?.cancel()
            holdTask = nil
            if recorder.isActive { recorder.cancel() }
            if notePhase != .idle { closeNote() }
            cam.shutdown()
        }
        .task(id: lastIncomingId) {
            // при открытии и при каждом новом входящем: история (не чаще раза в минуту) и перевод нового
            await store.loadHistory(convId)
            askAIForChatIfNeeded()
            await store.translateIncoming(convId)
        }
        .sheet(item: $sheet) { s in
            if let conv, let contact {
                switch s {
                case .folder: FolderSheet(contactId: contact.id)
                case .remind: ReminderSheet(contactId: contact.id)
                case .templates: TemplatesSheet { text in draft = text; inputFocused = true }
                case .translate: TranslateSheet(lang: foreignLang(contact) ?? (contact.lang ?? ""), convId: convId)
                case .attach:
                    AttachSheet(canNote: conv.network == "telegram",
                                onPhoto: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showPhotos = true } },
                                onFile: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showFiles = true } },
                                onTemplate: { sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = .templates } },
                                onVoice: { sheet = nil; store.show(String(localized: "Удерживай кнопку микрофона справа от поля — запись пойдёт, пока держишь")) },
                                onNote: {
                                    sheet = nil
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { videoMode = true }
                                    store.show(String(localized: "Удерживай кнопку камеры справа от поля — кружок пишется, пока держишь"))
                                })
                        .id(conv.id)
                }
            }
        }
        .sheet(item: $forward) { f in
            ForwardSheet(messages: f.messages, fromConv: convId) {
                withAnimation { selecting = false; selected = [] }
            }
        }
        .confirmationDialog("Удалить выбранные сообщения у клиента?", isPresented: $confirmBatchDelete, titleVisibility: .visible) {
            Button("Удалить у всех", role: .destructive) { deleteSelected() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сообщения пропадут и у клиента, и здесь. Вернуть будет нельзя.")
        }
        .fullScreenCover(item: $viewer) { v in
            MediaViewer(items: v.items, start: v.start) { viewer = nil }
                .environment(store)
        }
        .onChange(of: cam.ready) { _, ready in
            // камера включилась, а кнопку всё ещё держат (или замок) — начинаем запись
            if ready, notePhase == .recording || notePhase == .locked, !cam.recording { cam.record() }
        }
        .onChange(of: videoMode) { _, on in
            // режим кружка: заранее спрашиваем доступ и собираем сессию камеры — удержание стартует без задержки
            if on, !store.fixture, store.conversation(convId)?.network == "telegram" { cam.warmUp() }
        }
        .onChange(of: cam.outputURL) { _, url in
            if let url { noteRecorded(url) }
        }
        .onChange(of: cam.problem) { _, p in
            if let p, notePhase != .idle {
                store.show(p, ok: false)
                closeNote()
            }
        }
        .confirmationDialog("Удалить сообщение у клиента?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            if let m = confirmDelete {
                Button("Удалить у всех", role: .destructive) {
                    confirmDelete = nil
                    Task { await store.unsend(m.id, convId: convId) }
                }
            }
            Button("Отмена", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Сообщение пропадёт и у клиента, и здесь. Вернуть будет нельзя.")
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { Task { await sendFile(url) } }
        }
    }

    // MARK: переписка

    private func mediaItems(_ msgs: [Message]) -> [MediaItem] {
        var out: [MediaItem] = []
        for m in msgs {
            for (i, a) in (m.attachments ?? []).enumerated() where a.kind == "image" || a.kind == "video" {
                out.append(MediaItem(id: m.id + "#\(i)", raw: a.url, kind: a.kind, name: a.name ?? "", round: a.round == true, mime: a.mime))
            }
        }
        return out
    }

    private func openMedia(_ msgs: [Message], messageId: String, index: Int) {
        let items = mediaItems(msgs)
        let key = messageId + "#\(index)"
        let start: Int = items.firstIndex { $0.id == key } ?? 0
        guard !items.isEmpty else { return }
        viewer = ViewerState(items: items, start: start)
    }

    private func canUnsend(_ m: Message, _ conv: Conversation) -> Bool {
        guard m.isOut, m.externalId != nil, conv.network == "telegram" || conv.network == "whatsapp" else { return false }
        if store.user?.isOwner == true || store.fixture { return true }
        return m.authorId != nil && m.authorId == store.user?.id
    }

    private func messagesView(_ conv: Conversation) -> some View {
        let msgs: [Message] = store.messages(conv.id)
        let intent = currentIntent(conv)
        let extra: CGFloat = (intent != nil ? 104 : 0) + (replyTo != nil ? 56 : 0)
        let bottomPad: CGFloat = bottomH > 0 ? bottomH + 12 : 96 + extra
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if (conv.older ?? 0) > 0 && store.fullHistory[conv.id] == nil {
                        ProgressView().tint(.white).padding(.vertical, 8)
                    }
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                        messageRow(msgs, i, m, conv, proxy)
                    }
                    ForEach(pending) { p in
                        pendingBubble(p).id("pending-" + p.id)
                    }
                    bottomSentinel
                }
                .padding(.horizontal, 12)
                .padding(.top, 136)
                .padding(.bottom, bottomPad)
                // анимируем только новое внизу: подгрузка истории сверху появляется сразу, без «въезда» снизу
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: msgs.last?.id)
            }
            .coordinateSpace(.named("chatScroll"))
            .background(GeometryReader { g in Color.clear.preference(key: ChatScrollHeightKey.self, value: g.size.height) })
            .onPreferenceChange(ChatScrollHeightKey.self) { h in MainActor.assumeIsolated { if h > 0 { scrollH = h } } }
            .onPreferenceChange(ChatSentinelKey.self) { y in MainActor.assumeIsolated { sentinelMoved(y) } }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.loadState(force: true) }
            .overlay(alignment: .bottomTrailing) {
                ZStack { downButton(proxy) }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: atBottom)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: newBelow)
            }
            .onAppear { openPosition(proxy) }
            .onReceive(NotificationCenter.default.publisher(for: .sguardoBubbleGrew)) { n in
                // раскрыли расшифровку у последнего сообщения — докрутить, чтобы пузырь был целиком над полем ввода
                guard let id = n.object as? String, id == store.messages(conv.id).last?.id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onChange(of: bottomH) { old, new in
                // панель ввода выросла (ответ, подсказка) — низ ленты не должен уйти под неё (только если мы внизу)
                if new > old && atBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: msgs.last?.id) { old, new in lastChanged(old, new, proxy) }
            .onChange(of: historyCount) { old, new in historyChanged(old, new, proxy) }
            .onChange(of: pending.count) { old, new in
                if new > old { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: inputFocused) { _, f in
                if f && atBottom { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            }
        }
    }

    /// Строка ленты: день, разделитель непрочитанных, сам пузырь (в режиме выбора — с кружком слева).
    @ViewBuilder private func messageRow(_ msgs: [Message], _ i: Int, _ m: Message, _ conv: Conversation, _ proxy: ScrollViewProxy) -> some View {
        if i == 0 || !Calendar.current.isDate(msgs[i - 1].date, inSameDayAs: m.date) {
            Text(Fmt.dayLong(m.date))
                .font(Typo.body(12, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .glassCapsule()
                .padding(.vertical, 8)
        }
        if m.id == unreadAnchor {
            unreadDivider.id("unread-divider")
        }
        let isSel: Bool = selected.contains(m.id)
        HStack(spacing: 8) {
            if selecting {
                selectCircle(isSel)
            }
            Bubble(message: m,
                   highlighted: highlight == m.id || (selecting && isSel),
                   canUnsend: canUnsend(m, conv),
                   canForward: forwardable(m),
                   onReply: { startReply(m) },
                   onDelete: { confirmDelete = m },
                   onOpenMedia: { idx in openMedia(msgs, messageId: m.id, index: idx) },
                   onQuoteTap: { id in jump(to: id, proxy: proxy) },
                   onForward: { forward = ForwardBox(messages: [m]) },
                   onSelect: { startSelecting(m.id) })
                .allowsHitTesting(!selecting)
        }
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { toggleSelected(m.id) }, including: selecting ? .all : .subviews)
        .id(m.id)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }

    private var unreadDivider: some View {
        Text("Непрочитанные сообщения")
            .font(Typo.body(13, .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Rectangle().fill(Color.black.opacity(0.28)))
            .padding(.horizontal, -12)
            .padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func selectCircle(_ on: Bool) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            if on {
                Circle().fill(Pal.acc)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Pal.ink)
            }
        }
        .frame(width: 24, height: 24)
        .frame(width: 28)
        .transition(.move(edge: .leading).combined(with: .opacity))
        .accessibilityLabel(on ? String(localized: "Выбрано") : String(localized: "Не выбрано"))
    }

    /// Невидимая метка в самом низу ленты: по её положению понимаем, долистали ли до конца.
    private var bottomSentinel: some View {
        Color.clear.frame(height: 1)
            .background(GeometryReader { g in
                Color.clear.preference(key: ChatSentinelKey.self, value: g.frame(in: .named("chatScroll")).minY)
            })
            .id("bottom")
            .onDisappear { setAtBottom(false) }
    }

    /// Метка видна над панелью ввода (с запасом 120 pt) — считаем, что мы внизу.
    private func sentinelMoved(_ y: CGFloat) {
        guard scrollH > 0 else { return }
        let visibleBottom: CGFloat = scrollH - (bottomH > 0 ? bottomH : 64)
        setAtBottom(y < visibleBottom + 120)
    }

    private func setAtBottom(_ b: Bool) {
        if b != atBottom { atBottom = b }
        if b && newBelow != 0 { newBelow = 0 }
    }

    /// Запомнить первое непрочитанное входящее до того, как чат отметится прочитанным.
    private func rememberUnread() {
        guard unreadAnchor == nil, let c = store.conversation(convId), c.unread > 0 else { return }
        let incoming: [Message] = store.messages(convId).filter { !$0.isOut }
        guard !incoming.isEmpty else { return }
        let n: Int = min(c.unread, incoming.count)
        unreadAnchor = incoming[incoming.count - n].id
        newBelow = n
    }

    /// Открыть чат на первом непрочитанном, иначе — внизу.
    private func openPosition(_ proxy: ScrollViewProxy) {
        // defaultScrollAnchor с LazyVStack не всегда открывает чат внизу (снимки CI открывались сверху)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if unreadAnchor != nil {
                proxy.scrollTo("unread-divider", anchor: UnitPoint(x: 0.5, y: 0.2))
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        #if DEBUG
        if let id = fixtureScrollTarget() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.2)) }
        }
        #endif
    }

    /// Сколько сообщений в полной истории (-1 — ещё не загружена).
    private var historyCount: Int { store.fullHistory[convId]?.count ?? -1 }

    /// Последнее входящее: новое — повод догрузить историю и перевести его.
    private var lastIncomingId: String {
        let msgs: [Message] = store.conversation(convId)?.messages ?? []
        return msgs.last(where: { (m: Message) -> Bool in !m.isOut })?.id ?? ""
    }

    /// Подгрузилась история сверху: внизу — остаёмся внизу; только открыли на непрочитанных — возвращаемся к разделителю.
    /// Если человек уже листает сам — не трогаем.
    private func historyChanged(_ old: Int, _ new: Int, _ proxy: ScrollViewProxy) {
        guard new > old else { return }
        if atBottom {
            proxy.scrollTo("bottom", anchor: .bottom)
        } else if unreadAnchor != nil, Date().timeIntervalSince(openedAt) < 3 {
            proxy.scrollTo("unread-divider", anchor: UnitPoint(x: 0.5, y: 0.2))
        }
    }

    /// Первый вход в иностранный чат без согласия на ИИ: спрашиваем один раз за запуск.
    private func askAIForChatIfNeeded() {
        guard !store.aiConsent, !store.aiAskedAuto, store.translateOn else { return }
        guard let conv = store.conversation(convId), let c = store.contact(conv.contactId), foreignLang(c) != nil else { return }
        store.aiAskedAuto = true
        let id: String = convId
        store.askAI(then: {
            Task { await store.translateIncoming(id) }
        })
    }

    /// Плашка под шапкой: идёт перевод входящих / перевод не удался — с «Повторить».
    @ViewBuilder private func translateStatus(_ contact: Contact) -> some View {
        if store.translateOn, foreignLang(contact) != nil {
            if !store.aiConsent {
                aiOffPill
            } else if store.translating.contains(convId) {
                HStack(spacing: 8) {
                    ProgressView().tint(.white).controlSize(.small)
                    Text("Переводим сообщения…").font(Typo.body(13, .medium)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .glass(.dark, in: Capsule())
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityElement(children: .combine)
            } else if let err = store.translateFailed[convId] {
                translateErrorPill(err)
            }
        }
    }

    /// Перевод выключен (нет согласия на ИИ): тап — снова спросить.
    private var aiOffPill: some View {
        let id: String = convId
        return Button {
            haptic()
            store.askAI(then: {
                Task { await store.translateIncoming(id) }
            })
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 13)).foregroundStyle(.white)
                Text("Перевод через ИИ выключен").font(Typo.body(13)).foregroundStyle(.white).lineLimit(2)
                Text("Включить").font(Typo.body(13, .semibold)).foregroundStyle(Pal.acc)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .glass(.dark, in: Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(Text("Перевод через ИИ выключен. Включить"))
    }

    private func translateErrorPill(_ err: String) -> some View {
        Button {
            haptic()
            Task { await store.translateIncoming(convId) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(Pal.rose)
                Text("Перевод не загрузился: \(err)").font(Typo.body(13)).foregroundStyle(.white).lineLimit(2)
                Text("Повторить").font(Typo.body(13, .semibold)).foregroundStyle(Pal.acc)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .glass(.dark, in: Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(Text("Перевод не загрузился. Повторить"))
    }

    /// Пришло новое сообщение: внизу — докручиваем; читаем историю — не прыгаем, только счётчик на кнопке «вниз».
    private func lastChanged(_ old: String?, _ new: String?, _ proxy: ScrollViewProxy) {
        guard let old, let new, old != new else { return }
        let ms: [Message] = store.messages(convId)
        guard let k = ms.firstIndex(where: { $0.id == old }) else { return }
        let added: [Message] = Array(ms[(k + 1)...])
        guard !added.isEmpty else { return }
        let mine: Bool = added.last?.isOut ?? false
        if atBottom || mine {
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        } else {
            newBelow += added.filter { !$0.isOut }.count
        }
    }

    /// Круглая кнопка «вниз» справа над полем ввода, со счётчиком новых.
    @ViewBuilder private func downButton(_ proxy: ScrollViewProxy) -> some View {
        if !atBottom && !selecting {
            let lift: CGFloat = (bottomH > 0 ? bottomH : 64) + 10
            Button {
                haptic()
                newBelow = 0
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glass(.light, in: Circle(), interactive: true)
                    .overlay(alignment: .top) { downBadge }
            }
            .buttonStyle(PressStyle())
            .padding(.trailing, 12)
            .padding(.bottom, lift)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .accessibilityLabel(newBelow > 0 ? String(localized: "Вниз, новых сообщений: \(newBelow)") : String(localized: "Вниз"))
            .accessibilityIdentifier("scroll-down")
        }
    }

    @ViewBuilder private var downBadge: some View {
        if newBelow > 0 {
            Text(verbatim: newBelow > 99 ? "99+" : "\(newBelow)")
                .font(Typo.body(12, .bold))
                .monospacedDigit()
                .foregroundStyle(Pal.ink)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 22)
                .background(Capsule().fill(Pal.acc))
                .offset(y: -11)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: выбор сообщений

    private func startSelecting(_ id: String) {
        haptic(.medium)
        inputFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            replyTo = nil
            selected = [id]
            selecting = true
        }
    }

    private func toggleSelected(_ id: String) {
        guard selecting else { return }
        haptic()
        withAnimation(.easeOut(duration: 0.15)) {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        }
    }

    private func stopSelecting() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            selecting = false
            selected = []
        }
    }

    private var selectedMessages: [Message] {
        store.messages(convId).filter { selected.contains($0.id) }
    }

    /// Переслать можно текст и файлы, лежащие в кабинете (с mediaId); файлы бота Telegram хранятся в Telegram.
    private func forwardable(_ m: Message) -> Bool {
        if !m.body.isEmpty { return true }
        return (m.attachments ?? []).contains { $0.mediaId != nil }
    }

    private var selectionHeader: some View {
        HStack(spacing: 10) {
            Button { stopSelecting() } label: {
                Text("Отмена").font(Typo.body(15, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 44).contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .glassCapsule(interactive: true)
            Spacer(minLength: 0)
            Text("Выбрано: \(selected.count)").font(Typo.body(16, .semibold)).foregroundStyle(.white)
            Spacer(minLength: 0)
            Color.clear.frame(width: 80, height: 44)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(LinearGradient(colors: [Color(red: 10 / 255, green: 8 / 255, blue: 16 / 255).opacity(0.8), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    private func selectionBar(_ conv: Conversation) -> some View {
        let msgs: [Message] = selectedMessages
        let canDel: Bool = !msgs.isEmpty && msgs.allSatisfy { canUnsend($0, conv) }
        let canFwd: Bool = msgs.contains { forwardable($0) }
        return HStack(spacing: 6) {
            selAction("doc.on.doc", "Копировать", enabled: !msgs.isEmpty) { copyMessages(msgs) }
            selAction("arrowshape.turn.up.right", "Переслать", enabled: canFwd) { forward = ForwardBox(messages: msgs) }
            selAction("trash", "Удалить", enabled: canDel, tint: Pal.danger) { confirmBatchDelete = true }
        }
        .padding(6)
        .glassRect(22)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func selAction(_ icon: String, _ title: LocalizedStringKey, enabled: Bool, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: { haptic(); action() }) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(Typo.body(12, .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func copyMessages(_ msgs: [Message]) {
        let parts: [String] = msgs.sorted { $0.date < $1.date }.map { (m: Message) -> String in
            if !m.body.isEmpty { return m.body }
            if let t = m.transcript ?? store.transcripts[m.id], !t.text.isEmpty { return t.text }
            return m.preview
        }
        UIPasteboard.general.string = parts.joined(separator: "\n\n")
        store.show(String(localized: "Скопировано"))
        stopSelecting()
    }

    private func deleteSelected() {
        let ids: [String] = selectedMessages.map(\.id)
        stopSelecting()
        Task {
            for id in ids {
                if !(await store.unsend(id, convId: convId)) { break }
            }
        }
    }

    // MARK: свои сообщения в пути

    private func pendingBubble(_ p: PendingMsg) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Spacer(minLength: 60)
                HStack(alignment: .bottom, spacing: 6) {
                    Text(p.text).font(Typo.body(15.5)).foregroundStyle(Pal.ink).fixedSize(horizontal: false, vertical: true)
                    if !p.failed {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(Pal.ink.opacity(0.6))
                            .accessibilityLabel("Отправляется")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous).fill(Pal.acc.opacity(p.failed ? 0.5 : 0.7)))
                if p.failed {
                    failedMenu(p)
                }
            }
            if p.failed {
                Button { retry(p) } label: {
                    Text("Не отправлено · Повторить").font(Typo.body(12, .semibold)).foregroundStyle(Pal.danger)
                        .padding(.horizontal, 8).frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 44)
            }
        }
    }

    private func failedMenu(_ p: PendingMsg) -> some View {
        Menu {
            Button { retry(p) } label: { Label("Повторить", systemImage: "arrow.clockwise") }
            Button { UIPasteboard.general.string = p.text } label: { Label("Скопировать", systemImage: "doc.on.doc") }
            Button(role: .destructive) { dropPending(p) } label: { Label("Удалить", systemImage: "trash") }
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.red)
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Не отправлено: повторить или удалить")
    }

    private func dropPending(_ p: PendingMsg) {
        withAnimation { pending.removeAll { $0.id == p.id } }
    }

    private func jump(to id: String, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        highlight = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { if highlight == id { highlight = nil } } }
    }

    private func startReply(_ m: Message) {
        haptic(.medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { replyTo = m }
        inputFocused = true
    }

    private func header(_ conv: Conversation, _ contact: Contact) -> some View {
        let f = store.folder(contact.folderId)
        let rem = store.reminder(for: contact.id)
        let net = NetInfo.of(conv.network)
        let promised = store.deals(of: contact.id).last { $0.status == "promised" }
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                CircleButton(system: "chevron.left", iconSize: 18) { store.pop() }
                Button { store.open(.client(contact.id)) } label: {
                    VStack(spacing: 1) {
                        Text(contact.name).font(Typo.body(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 4) {
                            Circle().fill(net.color).frame(width: 7, height: 7)
                            Text(joinHandle(net.name, contact.handle))
                                .font(Typo.body(11)).foregroundStyle(Color.white.opacity(0.72)).lineLimit(1)
                            if store.translateOn, let lang = foreignLang(contact) {
                                langBadge(lang)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .glassCapsule(interactive: true)
                Button { store.open(.client(contact.id)) } label: {
                    Avatar(name: contact.name, hue: contact.displayHue, url: contact.avatar, size: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Карточка клиента")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(text: f?.name ?? String(localized: "Без папки"), dot: Color(css: f?.color), height: 30, fontSize: 12.5) { sheet = .folder }
                    if let promised, promised.amount > 0 {
                        Chip(text: Fmt.money(promised.amount, currency: store.state.workspace?.currency), height: 30, fontSize: 12.5) { store.open(.client(contact.id)) }
                            .contextMenu {
                                Button(role: .destructive) { undoPromise(contact.id, promised) } label: { Label("Снять обещание", systemImage: "xmark.circle") }
                            }
                    }
                    ForEach(contact.tags ?? [], id: \.self) { t in
                        tagChip(t, contact: contact)
                    }
                    if let rem {
                        Chip(text: "⏰ " + Fmt.remShort(rem.date), height: 30, fontSize: 12.5) { sheet = .remind }
                            .contextMenu {
                                Button { sheet = .remind } label: { Label("Перенести", systemImage: "clock") }
                                Button { done(rem, contact.id) } label: { Label("Готово", systemImage: "checkmark") }
                                Button(role: .destructive) { removeReminder(rem, contact.id) } label: { Label("Удалить напоминание", systemImage: "trash") }
                            }
                    } else {
                        Chip(text: String(localized: "🔔 Напомнить"), height: 30, fontSize: 12.5) { sheet = .remind }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [Color(red: 10 / 255, green: 8 / 255, blue: 16 / 255).opacity(0.8), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
    }

    /// Метка в шапке: крестик снимает её с клиента (с «Отменить»).
    private func tagChip(_ t: String, contact: Contact) -> some View {
        HStack(spacing: 4) {
            Text(t).font(Typo.body(12.5, .semibold)).lineLimit(1)
            Button { removeTag(t, contact) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
            }
            .accessibilityLabel("Снять метку \(t)")
        }
        .foregroundStyle(Pal.ink)
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 30)
        .background(Capsule().fill(labelColor(t)))
        .onTapGesture { store.open(.client(contact.id)) }
    }

    private func removeTag(_ t: String, _ c: Contact) {
        var tags = c.tags ?? []
        tags.removeAll { $0 == t }
        let body: [String: Any] = ["type": "updateContact", "contactId": c.id, "tags": tags]
        Task { await store.perform([body], contactId: c.id, ok: String(localized: "Метка «\(t)» снята")) }
    }

    private func done(_ r: Reminder, _ contactId: String) {
        Task { await store.perform([["type": "doneReminder", "id": r.id]], contactId: contactId, ok: String(localized: "Напоминание выполнено")) }
    }

    private func removeReminder(_ r: Reminder, _ contactId: String) {
        Task { await store.perform([["type": "removeReminder", "id": r.id]], contactId: contactId, ok: String(localized: "Напоминание удалено")) }
    }

    private func undoPromise(_ contactId: String, _ d: Deal) {
        Task { await store.perform([["type": "removeDeal", "id": d.id]], contactId: contactId, ok: String(localized: "Обещание снято")) }
    }

    private func currentIntent(_ conv: Conversation) -> Intent? {
        guard let m = conv.last, !m.isOut, !store.hintOff.contains(conv.id + "|" + m.id) else { return nil }
        return Intent.of(m.body)
    }

    private func bottom(_ conv: Conversation, _ contact: Contact) -> some View {
        let intent = currentIntent(conv)
        return VStack(spacing: 10) {
            if let intent, let m = conv.last, !isRecActive {
                intentCard(intent, m, conv, contact)
            }
            if let r = replyTo, !isRecActive {
                replyBar(r)
            }
            if store.translateOn, inputFocused, let lang = foreignLang(contact), !isRecActive {
                translateChip(lang)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer(conv)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: intent?.title)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: replyTo?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: inputFocused)
    }

    private func intentCard(_ intent: Intent, _ m: Message, _ conv: Conversation, _ contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle").font(.system(size: 15, weight: .bold)).foregroundStyle(Pal.acc)
                Text(intent.title).font(Typo.body(14, .semibold)).foregroundStyle(.white)
                Spacer()
                Text("клиент не увидит").font(Typo.body(12)).foregroundStyle(Pal.fg3)
            }
            HStack(spacing: 8) {
                Button { Task { await apply(intent, contact) } } label: {
                    Text(intent.action(folderName: store.folder(key: intent.folderKey)?.name)).font(Typo.body(13.5, .semibold)).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 40).primaryFill(14)
                }
                .buttonStyle(PressStyle())
                Button { withAnimation { store.hideHint(conv.id, lastMessageId: m.id) } } label: {
                    Text("Нет").font(Typo.body(14)).foregroundStyle(.white).padding(.horizontal, 14).frame(height: 40).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .glass(.light, in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassRect(22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func replyBar(_ r: Message) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 15)).foregroundStyle(Pal.acc)
            Rectangle().fill(Pal.acc).frame(width: 3).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(r.isOut ? String(localized: "Ответ на ваше сообщение") : String(localized: "Ответ клиенту")).font(Typo.body(12, .semibold)).foregroundStyle(Pal.acc)
                Text(r.preview).font(Typo.body(13)).foregroundStyle(Pal.fg2).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { withAnimation { replyTo = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Не отвечать")
        }
        .padding(.horizontal, 12).frame(height: 48)
        .glassRect(18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: перевод при отправке

    /// Язык клиента для перевода. Сервер может ошибиться (ссылка t.me сделала русского клиента «английским»),
    /// поэтому доверяем contact.lang, только если сами входящие это подтверждают.
    private func foreignLang(_ c: Contact) -> String? {
        guard let l = c.lang?.lowercased(), !l.isEmpty, !l.hasPrefix("ru") else { return nil }
        let msgs: [Message] = store.conversation(convId)?.messages ?? []
        return incomingLooksForeign(msgs) ? l : nil
    }

    /// Большинство из последних 6 входящих с текстом (≥12 букв без ссылок, @ и #) — не кириллица.
    private func incomingLooksForeign(_ msgs: [Message]) -> Bool {
        var foreign = 0
        var total = 0
        for m in msgs.reversed() where !m.isOut {
            if total >= 6 { break }
            let words: [Substring] = m.body.split(whereSeparator: { $0.isWhitespace })
            let clean: [Substring] = words.filter { (w: Substring) -> Bool in
                let lw: String = w.lowercased()
                return !(lw.hasPrefix("@") || lw.hasPrefix("#") || lw.contains("://") || lw.hasPrefix("www.") || lw.contains("t.me/"))
            }
            var letters = 0
            var cyr = 0
            for w in clean {
                for u in w.unicodeScalars where CharacterSet.letters.contains(u) {
                    letters += 1
                    if (0x0400...0x04FF).contains(Int(u.value)) { cyr += 1 }
                }
            }
            guard letters >= 12 else { continue }
            total += 1
            if cyr * 2 < letters { foreign += 1 }
        }
        return total > 0 && foreign * 2 > total
    }

    /// Переводить исходящие этого чата: только если клиент и правда пишет не по-русски.
    private var canTranslate: Bool {
        guard let conv = store.conversation(convId), let c = store.contact(conv.contactId) else { return false }
        return foreignLang(c) != nil
    }

    /// Значок языка в шапке: «🌐 EN». Тап — лист с объяснением и переключателем (перехватывает тап у карточки клиента).
    private func langBadge(_ lang: String) -> some View {
        let on: Bool = store.translateOut && store.aiConsent
        return HStack(spacing: 3) {
            Image(systemName: "globe").font(.system(size: 9, weight: .semibold))
            Text(String(lang.prefix(2)).uppercased()).font(Typo.body(10, .semibold))
        }
        .foregroundStyle(on ? Pal.ink : .white)
        .padding(.horizontal, 6).frame(height: 16)
        .background(Capsule().fill(on ? Color.white.opacity(0.85) : Color.white.opacity(0.18)))
        .contentShape(Rectangle().inset(by: -8))
        .highPriorityGesture(TapGesture().onEnded { haptic(); sheet = .translate })
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Перевод переписки")
    }

    /// Компактный переключатель над полем ввода (только пока поле в фокусе): «🌐 RU → EN» и тумблер.
    private func translateChip(_ lang: String) -> some View {
        let code: String = String(lang.prefix(2)).uppercased()
        let on: Bool = store.translateOut && store.aiConsent
        return HStack {
            Button {
                haptic()
                if store.aiConsent {
                    withAnimation(.spring(response: 0.3)) { store.translateOut.toggle() }
                } else {
                    store.askAI(then: { store.translateOut = true })
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 11, weight: .semibold))
                    Text(on ? "RU → \(code)" : String(localized: "без перевода")).font(Typo.body(12, .medium)).lineLimit(1)
                    ZStack(alignment: on ? .trailing : .leading) {
                        Capsule().fill(on ? Color.white.opacity(0.85) : Color.white.opacity(0.2))
                        Circle().fill(on ? Color.black.opacity(0.8) : Color.white).frame(width: 11, height: 11).padding(2)
                    }
                    .frame(width: 26, height: 15)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10).frame(height: 26)
                .glassCapsule(.dark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? String(localized: "перевод при отправке включён") : String(localized: "перевод при отправке выключен"))
            Spacer(minLength: 0)
        }
    }

    // MARK: поле ввода и запись

    private func composer(_ conv: Conversation) -> some View {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canNote = conv.network == "telegram"
        return ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 8) {
                switch recPhase {
                case .idle:
                    idleLeft.transition(.opacity)
                case .recording:
                    recordingBar.transition(barTransition)
                case .locked:
                    lockedBar.transition(.opacity)
                case .preview:
                    previewBar.transition(.opacity)
                }
                mainButton(conv, hasText: hasText, canNote: canNote)
            }
            if recPhase == .recording {
                lockHint
                    .offset(x: 0, y: -62)
                    .transition(lockTransition)
            }
        }
        .animation(recSpring, value: recPhase)
    }

    /// Пружина всех переходов записи; при «Уменьшить движение» — короткое затухание.
    private var recSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.8)
    }

    /// Полоса записи выезжает от кнопки, уходит, бледнея влево (как в Telegram).
    private var barTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: AnyTransition = .offset(x: 60).combined(with: .opacity)
        let removal: AnyTransition = .offset(x: -40).combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    private var lockTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .offset(y: 24).combined(with: .opacity).combined(with: .scale(scale: 0.6, anchor: .bottom))
    }

    @ViewBuilder private var idleLeft: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if trashFlash {
                trashBadge.transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            } else {
                CircleButton(system: "plus", iconSize: 20) { sheet = .attach }
                    .transition(.opacity)
            }
            textField
        }
    }

    private var trashBadge: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Pal.danger)
            .frame(width: 44, height: 44)
            .symbolEffect(.bounce, value: trashFlash)
            .accessibilityHidden(true)
    }

    /// Отмена записи: короткая корзина вместо «+» и плавный возврат поля ввода.
    private func flashTrash() {
        withAnimation(recSpring) { trashFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(recSpring) { trashFlash = false }
        }
    }

    private var textField: some View {
        HStack(spacing: 6) {
            TextField("", text: $draft, prompt: Text("Сообщение").foregroundColor(Pal.fg3), axis: .vertical)
                .lineLimit(1...5)
                .font(Typo.body(16))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .accessibilityIdentifier("composer")
            Button { sheet = .templates } label: {
                Image(systemName: "tag").font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.75)).frame(width: 32, height: 32)
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 6)
        .frame(minHeight: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var recordingBar: some View {
        let cancelProgress: Double = Double(min(1, max(0, -dragX / 110)))
        let blinkStep: Int = Int(recElapsed * 2)
        return HStack(spacing: 10) {
            Circle().fill(Pal.danger).frame(width: 10, height: 10)
                .opacity(blinkStep % 2 == 0 ? 1 : 0.25)
                .animation(.easeInOut(duration: 0.4), value: blinkStep)
            Text(durationText(recElapsed)).font(Typo.body(15, .medium)).monospacedDigit().foregroundStyle(.white)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text("влево — отмена").font(Typo.body(14))
            }
            .foregroundStyle(Pal.fg2)
            .opacity(1 - cancelProgress * 0.85)
            .offset(x: min(0, dragX * 0.8))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Замок над кнопкой: подтягивается за пальцем, стрелка гаснет, у порога замок «защёлкивается».
    private var lockHint: some View {
        let progress: CGFloat = min(1, max(0, -dragY / 80))
        let closing: Bool = progress > 0.75
        return VStack(spacing: 4) {
            Image(systemName: closing ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
                .opacity(Double(1 - progress))
                .offset(y: -progress * 4)
        }
        .foregroundStyle(.white)
        .frame(width: 44, height: 70)
        .glass(.light, in: Capsule())
        .scaleEffect(reduceMotion ? 1 : 1 + progress * 0.08)
        .offset(y: -progress * 26)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: closing)
        .accessibilityLabel("Вверх — запись без рук")
    }

    @ViewBuilder private var lockedBar: some View {
        if notePhase == .locked {
            HStack(spacing: 10) {
                Button { cancelNote() } label: {
                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel("Удалить кружок")
                Circle().fill(Pal.danger).frame(width: 9, height: 9)
                    .opacity(Int(cam.elapsed * 2) % 2 == 0 ? 1 : 0.35)
                Text(durationText(cam.elapsed)).font(Typo.body(15, .medium)).monospacedDigit().foregroundStyle(.white)
                Text("кружок · без рук").font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            voiceLockedBar
        }
    }

    private var voiceLockedBar: some View {
        HStack(spacing: 10) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить запись")
            Circle().fill(Pal.danger).frame(width: 9, height: 9)
                .opacity(Int(recorder.elapsed * 2) % 2 == 0 ? 1 : 0.35)
            Text(durationText(recorder.elapsed)).font(Typo.body(15, .medium)).monospacedDigit().foregroundStyle(.white)
            LevelBars(levels: recorder.levels, count: 22)
            Spacer(minLength: 0)
            Button { recorder.toPreview() } label: {
                Image(systemName: "stop.fill").font(.system(size: 14)).foregroundStyle(.white).frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .accessibilityLabel("Остановить и прослушать")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var previewBar: some View {
        if notePhase == .preview {
            HStack(spacing: 10) {
                Button { cancelNote() } label: {
                    Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel("Удалить кружок")
                Image(systemName: "video.circle.fill").font(.system(size: 20)).foregroundStyle(Pal.acc)
                Text("Кружок готов").font(Typo.body(15, .medium)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(durationText(cam.elapsed)).font(Typo.body(14, .medium)).monospacedDigit().foregroundStyle(Pal.fg2)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            voicePreviewBar
        }
    }

    private var voicePreviewBar: some View {
        HStack(spacing: 10) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(Pal.danger).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Удалить запись")
            Button { recorder.togglePlay() } label: {
                Image(systemName: recorder.playing ? "pause.fill" : "play.fill").font(.system(size: 14)).foregroundStyle(Pal.ink)
                    .frame(width: 32, height: 32).background(Circle().fill(Pal.acc))
            }
            .accessibilityLabel(recorder.playing ? String(localized: "Пауза") : String(localized: "Прослушать"))
            LevelBars(levels: recorder.levels, count: 26, progress: recorder.playing || recorder.playProgress > 0 ? recorder.playProgress : nil)
            Spacer(minLength: 0)
            Text(durationText(recorder.elapsed)).font(Typo.body(14, .medium)).monospacedDigit().foregroundStyle(Pal.fg2)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .glass(.light, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Правая кнопка: текст — отправить; запись без рук / прослушивание — отправить голосовое;
    /// иначе микрофон (или камера кружка в Telegram): удержать — записать, нажать — сменить режим.
    private func mainButton(_ conv: Conversation, hasText: Bool, canNote: Bool) -> some View {
        let phase: VoiceRecorder.Phase = recPhase
        // «живая» кнопка: идёт запись или удержание уже прошло порог (микрофон/камера ещё поднимаются)
        let live: Bool = phase == .recording || (holdLive && pressing && phase == .idle)
        let sendMode: Bool = hasText || phase == .locked || phase == .preview
        let icon: String = sendMode ? "arrow.up" : (videoMode && canNote ? "video" : "mic")
        let filled: Bool = sendMode || uploading || live
        let noteIcon: Bool = notePhase == .recording || (holdLive && videoMode && canNote)
        let recIcon: String = noteIcon ? "video.fill" : "mic.fill"
        return ZStack {
            if uploading { ProgressView().tint(Pal.ink) } else {
                Image(systemName: live ? recIcon : icon)
                    .font(.system(size: 19, weight: sendMode ? .bold : .regular))
                    .foregroundStyle(filled ? Pal.ink : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: videoMode)
            }
        }
        .frame(width: 44, height: 44)
        .background(buttonCore(live: live, filled: filled))
        .background(recordHalo(live: live))
        .scaleEffect(pressScale(live: live))
        .offset(x: live ? min(0, dragX) : 0, y: live ? min(0, dragY) : 0)
        .contentShape(Circle())
        .glass(.light, in: Circle(), interactive: true)
        .gesture(holdGesture(conv, canNote: canNote, sendMode: sendMode, hasText: hasText))
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: sendMode)
        .animation(recSpring, value: live)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: videoMode)
        .accessibilityLabel(sendMode ? String(localized: "Отправить") : (videoMode && canNote ? String(localized: "Кружок: удерживай, чтобы записать") : String(localized: "Голосовое: удерживай, чтобы записать")))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tapSend(conv, sendMode: sendMode, hasText: hasText) }
    }

    /// Заливка кнопки: во время записи — большой красный круг под пальцем (как в Telegram).
    private func buttonCore(live: Bool, filled: Bool) -> some View {
        let fill: Color = live ? Pal.danger : (filled ? Pal.acc : Color.clear)
        let grow: CGFloat = live && !reduceMotion ? 1.75 : 1
        return Circle().fill(fill).scaleEffect(grow)
    }

    /// Ореол вокруг круга: «дышит» по громкости микрофона.
    @ViewBuilder private func recordHalo(live: Bool) -> some View {
        if live && !reduceMotion {
            Circle()
                .fill(Pal.danger.opacity(0.24))
                .scaleEffect(2.0 + min(1, recLevel) * 0.7)
                .animation(.spring(response: 0.2, dampingFraction: 0.65), value: recLevel)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// Нажатие до порога — кнопка чуть проседает (видно, что палец «поймали»).
    private func pressScale(live: Bool) -> CGFloat {
        if reduceMotion || live || !pressing || pressSendMode { return 1 }
        return 0.9
    }

    private var recLevel: CGFloat { notePhase != .idle ? cam.level : recorder.level }

    private func tapSend(_ conv: Conversation, sendMode: Bool, hasText: Bool) {
        guard sendMode else {
            store.show(String(localized: "Удерживай кнопку, чтобы записать"))
            return
        }
        if hasText && recPhase == .idle {
            Task { await send(conv) }
        } else if notePhase == .locked {
            stopNote(.send)
        } else if notePhase == .preview, let url = cam.outputURL {
            closeNote(keepFile: true)
            Task { await sendNote(url) }
        } else {
            Task { await sendVoice() }
        }
    }

    /// Один жест на кнопке: в режиме «отправить» — нажатие, иначе удержание (запись) или короткое нажатие (смена режима).
    /// Маску жеста не переключаем: сброс жеста посреди удержания оставил бы кнопку «нажатой».
    private func holdGesture(_ conv: Conversation, canNote: Bool, sendMode: Bool, hasText: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !pressing {
                    pressing = true
                    pressSendMode = sendMode
                    if !sendMode { beginHold(canNote: canNote) }
                }
                guard recPhase == .recording else { return }
                // палец ведёт либо влево (отмена), либо вверх (замок) — второе направление гасим, чтобы круг не «плавал»
                let tx: CGFloat = min(0, v.translation.width)
                let ty: CGFloat = min(0, v.translation.height)
                if -tx > -ty {
                    dragX = tx
                    dragY = ty * 0.25
                } else {
                    dragX = tx * 0.25
                    dragY = ty
                }
                if v.translation.width < -110 {
                    holdLive = false
                    if notePhase == .recording { cancelNote() } else { cancelVoice() }
                    resetDrag()
                } else if v.translation.height < -80 {
                    holdLive = false
                    if notePhase == .recording {
                        withAnimation(recSpring) { notePhase = .locked }
                        haptic(.medium)
                    } else {
                        withAnimation(recSpring) { recorder.lock() }
                    }
                    resetDrag()
                }
            }
            .onEnded { v in
                pressing = false
                holdLive = false
                resetDrag()
                if pressSendMode {
                    // отпустили над кнопкой — отправляем
                    if abs(v.translation.width) < 40 && abs(v.translation.height) < 40 { tapSend(conv, sendMode: true, hasText: hasText) }
                    return
                }
                endHold(canNote: canNote)
            }
    }

    private func resetDrag() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { dragX = 0; dragY = 0 }
    }

    /// Отмена голосового свайпом: плавное исчезновение полосы + корзина.
    private func cancelVoice() {
        haptic(.rigid)
        withAnimation(recSpring) { recorder.cancel() }
        flashTrash()
    }

    private func beginHold(canNote: Bool) {
        holdTask?.cancel()
        let note: Bool = videoMode && canNote
        // кружок: камеру включаем сразу при касании — к порогу удержания превью уже почти готово
        if note && !store.fixture { cam.prepare() }
        holdTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard !Task.isCancelled, pressing else { return }
            holdTask = nil
            haptic(.medium)
            withAnimation(recSpring) { holdLive = true }
            if note {
                startNote()
                return
            }
            inputFocused = false
            let ok = await recorder.start()
            if !ok {
                holdLive = false
                store.show(String(localized: "Нет доступа к микрофону — разреши в настройках iPhone"), ok: false)
            } else if !pressing {
                // отпустили, пока микрофон поднимался (или система спрашивала доступ), — запись не начинаем
                recorder.cancel()
                store.show(String(localized: "Удерживай кнопку, чтобы записать"))
            }
        }
    }

    private func endHold(canNote: Bool) {
        if let t = holdTask {
            // короткое нажатие: в Telegram переключает голосовое/кружок, в других сетях — подсказка
            t.cancel()
            holdTask = nil
            if canNote {
                // камеру включили на касании «на всякий случай» — это было нажатие, выключаем
                if videoMode && !store.fixture { cam.shutdown() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { videoMode.toggle() }
                haptic()
                store.show(videoMode ? String(localized: "Режим кружка: удерживай кнопку, чтобы записать") : String(localized: "Режим голосового: удерживай, чтобы записать"))
            } else {
                store.show(String(localized: "Удерживай кнопку, чтобы записать голосовое"))
            }
            return
        }
        if notePhase == .recording {
            stopNote(.send)
        } else if recorder.phase == .recording {
            Task { await sendVoice() }
        }
    }

    // MARK: кружок над полем ввода

    private var recPhase: VoiceRecorder.Phase { notePhase != .idle ? notePhase : recorder.phase }
    private var recElapsed: TimeInterval { notePhase != .idle ? cam.elapsed : recorder.elapsed }
    private var isRecActive: Bool { recPhase != .idle }

    private func startNote() {
        inputFocused = false
        cam.problem = nil
        cam.reset()
        noteFinish = nil
        withAnimation(noteSpring) { notePhase = .recording }
        if store.fixture { return }
        // камера уже могла включиться (её запускают на касании) — тогда пишем сразу,
        // иначе запись начнётся, когда она включится (onChange cam.ready)
        if cam.ready {
            if !cam.recording { cam.record() }
        } else {
            cam.prepare()
        }
    }

    /// Вылет/улёт кружка: пружина помягче, чем у кнопки.
    private var noteSpring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    /// Остановить запись: отправить, показать для прослушивания или выбросить.
    private func stopNote(_ finish: NoteFinish) {
        guard notePhase == .recording || notePhase == .locked else { return }
        if store.fixture {
            if finish == .send { store.show(String(localized: "Отправлено")) }
            closeNote()
            return
        }
        let tooShort: Bool = !cam.recording || (finish == .send && cam.elapsed < 0.5)
        if tooShort {
            if finish != .discard { store.show(String(localized: "Слишком коротко — держи кнопку дольше"), ok: false) }
            noteFinish = .discard
            if cam.recording { cam.stop() } else { closeNote() }
            return
        }
        noteFinish = finish
        cam.stop()
    }

    private func cancelNote() {
        haptic(.rigid)
        flashTrash()
        if notePhase == .preview { closeNote() } else { stopNote(.discard) }
    }

    /// Файл кружка записан (отпустили, «стоп» или упёрлись в 60 с).
    private func noteRecorded(_ url: URL) {
        let finish: NoteFinish = noteFinish ?? (notePhase == .locked ? .preview : .send)
        noteFinish = nil
        switch finish {
        case .send:
            closeNote(keepFile: true)
            haptic(.medium)
            Task { await sendNote(url) }
        case .preview:
            cam.shutdown()
            withAnimation(noteSpring) { notePhase = .preview }
        case .discard:
            closeNote()
        }
    }

    private func closeNote(keepFile: Bool = false) {
        cam.shutdown()
        if keepFile {
            cam.outputURL = nil
            cam.elapsed = 0
        } else {
            cam.reset()
        }
        noteFinish = nil
        withAnimation(noteSpring) { notePhase = .idle }
    }

    /// Фон под кружком: размытие и затемнение ленты (появляется/уходит отдельно от самого круга).
    @ViewBuilder private var noteDim: some View {
        if notePhase != .idle {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.35)
            }
            .ignoresSafeArea()
            .allowsHitTesting(notePhase != .recording)
            .transition(.opacity)
        }
    }

    /// Живой круг камеры над полем ввода (поверх ленты), кольцо до 60 с; в режиме без рук — «сменить камеру» и «стоп».
    /// Вылетает пружиной из кнопки (правый нижний угол) и туда же «улетает» при отправке.
    @ViewBuilder private var noteOverlay: some View {
        if notePhase != .idle {
            VStack(spacing: 16) {
                noteCircle
                noteControls
            }
            .padding(.bottom, 118)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .transition(noteTransition)
            .accessibilityIdentifier("note-overlay")
        }
    }

    private var noteTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: AnyTransition = .scale(scale: 0.15, anchor: .bottomTrailing).combined(with: .opacity)
        let removal: AnyTransition = .scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    @ViewBuilder private var noteControls: some View {
        if notePhase == .locked {
            HStack(spacing: 22) {
                noteControl(icon: "arrow.triangle.2.circlepath.camera", label: String(localized: "Сменить камеру")) { haptic(); cam.switchCamera() }
                noteControl(icon: "stop.fill", label: String(localized: "Стоп"), tint: Pal.danger) { haptic(); stopNote(.preview) }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if notePhase == .recording {
            Text("Отпусти — отправится").font(Typo.body(13, .medium)).foregroundStyle(Pal.fg2)
                .transition(.opacity)
        }
    }

    private var noteCircle: some View {
        let side: CGFloat = 240
        let progress: Double = min(1, cam.elapsed / CameraModel.maxDuration)
        return ZStack {
            Circle().fill(Color.white.opacity(0.08))
            noteCircleContent
                .frame(width: side, height: side)
                .clipShape(Circle())
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 4).padding(-7)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Pal.acc, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-7)
                .animation(.linear(duration: 0.1), value: progress)
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .animation(.easeOut(duration: 0.25), value: cam.ready)
    }

    @ViewBuilder private var noteCircleContent: some View {
        if notePhase == .preview, let url = cam.outputURL {
            LoopingVideo(url: url)
        } else if store.fixture {
            Image(uiImage: fixtureNoteImage()).resizable().scaledToFill()
        } else if cam.ready {
            CameraPreview(session: cam.session)
                .transition(.opacity)
        } else {
            ZStack {
                Color.black.opacity(0.4)
                ProgressView().tint(.white)
            }
            .transition(.opacity)
        }
    }

    private func noteControl(icon: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(.light, in: Circle(), interactive: true)
        .accessibilityLabel(label)
    }

    // MARK: действия

    private func send(_ conv: Conversation) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let reply = replyTo
        draft = ""
        store.drafts[convId] = ""
        haptic(.medium)
        let p = PendingMsg(id: UUID().uuidString, text: text, replyTo: reply)
        withAnimation { pending.append(p); replyTo = nil }
        await deliver(p)
    }

    /// Отправка своего текста: ушло — пузырь «в пути» пропадает (настоящее сообщение уже в ленте), нет — красный «!».
    private func deliver(_ p: PendingMsg) async {
        let ok = await store.send(convId, text: p.text, replyTo: p.replyTo?.id, translate: canTranslate)
        withAnimation {
            if ok {
                pending.removeAll { $0.id == p.id }
            } else if let i = pending.firstIndex(where: { $0.id == p.id }) {
                pending[i].failed = true
            }
        }
    }

    private func retry(_ p: PendingMsg) {
        guard let i = pending.firstIndex(where: { $0.id == p.id }) else { return }
        haptic()
        withAnimation { pending[i].failed = false }
        let item: PendingMsg = pending[i]
        Task { await deliver(item) }
    }

    private func sendVoice() async {
        guard let url = recorder.finish() else {
            store.show(String(localized: "Слишком коротко — держи кнопку дольше"), ok: false)
            return
        }
        haptic(.medium)
        await uploadAndSend(url: url, name: "voice.m4a", mime: "audio/mp4", round: false)
    }

    private func sendNote(_ url: URL) async {
        await uploadAndSend(url: url, name: "note.mov", mime: "video/quicktime", round: true)
    }

    private func uploadAndSend(url: URL, name: String, mime: String, round: Bool) async {
        if store.fixture { store.show(String(localized: "Отправлено")); return }
        uploading = true
        defer {
            uploading = false
            try? FileManager.default.removeItem(at: url)
        }
        do {
            let data = try Data(contentsOf: url)
            let att = try await API.upload(data: data, name: name, mime: mime)
            let reply = replyTo
            if await store.send(convId, text: "", attachments: [att], round: round, replyTo: reply?.id) {
                withAnimation { replyTo = nil }
            }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    private func apply(_ intent: Intent, _ contact: Contact) async {
        guard let conv = store.conversation(convId), let m = conv.last else { return }
        let folderName = store.folder(key: intent.folderKey)?.name ?? intent.title
        var bodies: [[String: Any]] = []
        if intent.promise {
            let amount = store.dealDraft[contact.id] ?? Int(store.deals(of: contact.id).last { $0.status == "promised" }?.amount ?? 0)
            bodies.append(["type": "promise", "contactId": contact.id, "productId": NSNull(), "amount": amount, "remindAt": isoString(RemPreset.tomorrow.date)])
        } else {
            if let f = store.folder(key: intent.folderKey) {
                bodies.append(["type": "move", "contactId": contact.id, "folderId": f.id])
            }
            if intent.remind {
                let at = intent.folderKey == "thinking" ? RemPreset.twoDays.date : RemPreset.tomorrow.date
                bodies.append(["type": "remind", "contactId": contact.id, "at": isoString(at), "text": String(localized: "Написать клиенту")])
            }
        }
        let ok: String = intent.remind ? String(localized: "Готово: «\(folderName)», напоминание стоит") : String(localized: "Готово: «\(folderName)»")
        await store.perform(bodies, contactId: contact.id, ok: ok)
        store.hideHint(conv.id, lastMessageId: m.id)
    }

    private func sendPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        uploading = true
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let ext = isVideo ? "mp4" : "jpg"
            let mime = isVideo ? "video/mp4" : "image/jpeg"
            var payload = data
            if !isVideo, let img = UIImage(data: data), let jpg = img.jpegData(compressionQuality: 0.85) { payload = jpg }
            let att = try await API.upload(data: payload, name: "photo-\(Int(Date().timeIntervalSince1970)).\(ext)", mime: mime)
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.send(convId, text: text, attachments: [att], replyTo: replyTo?.id, translate: canTranslate) {
                draft = ""
                replyTo = nil
            }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    private func sendFile(_ url: URL) async {
        uploading = true
        defer { uploading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let att = try await API.upload(data: data, name: url.lastPathComponent, mime: mime)
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.send(convId, text: text, attachments: [att], replyTo: replyTo?.id, translate: canTranslate) {
                draft = ""
                replyTo = nil
            }
        } catch {
            store.show(friendly(error), ok: false)
        }
    }

    #if DEBUG
    /// Снимки CI: `-scrollto <id>` — прокрутить ленту к сообщению (кружки, проигрывание голосового).
    private func fixtureScrollTarget() -> String? {
        guard store.fixture else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-scrollto"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Снимки CI: ответ, запись голосового, прослушивание, просмотр фото, кружок.
    private func applyFixtureScreen() {
        guard store.fixture else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return }
        let msgs = store.messages(convId)
        switch args[i + 1] {
        case "chat-reply":
            replyTo = msgs.last { !$0.isOut }
        case "chat-tr":
            inputFocused = true
        case "chat-tr-sheet":
            sheet = .translate
        case "chat-voice":
            recorder.phase = .locked
            recorder.elapsed = 7
            recorder.levels = (0..<70).map { k in CGFloat(0.2 + 0.7 * abs(sin(Double(k) / 3))) }
        case "chat-preview":
            recorder.phase = .preview
            recorder.elapsed = 12
            recorder.playProgress = 0.4
            recorder.levels = (0..<70).map { k in CGFloat(0.15 + 0.8 * abs(sin(Double(k) / 4))) }
        case "viewer":
            let items = mediaItems(msgs)
            if !items.isEmpty { viewer = ViewerState(items: items, start: 0) }
        case "note", "note-rec":
            videoMode = true
            notePhase = .recording
            cam.elapsed = 9
        case "note-lock":
            videoMode = true
            notePhase = .locked
            cam.elapsed = 23
        case "chat-voice-rec":
            recorder.phase = .recording
            recorder.elapsed = 4
            dragX = -34
        case "chat-down":
            // после прокрутки вверх (-scrollto) пришли новые: кнопка «вниз» со счётчиком
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { newBelow = 3 } }
        case "chat-menu":
            fixtureMenu = msgs.first { $0.id == "m0_4" }
        case "chat-select":
            selecting = true
            selected = ["m0_1", "m0_4", "m0_5"]
        case "chat-failed":
            pending = [PendingMsg(id: "p1", text: "Пришлю ссылку на оплату сегодня вечером", replyTo: nil, failed: true)] // i18n: no
        case "chat-forward":
            if let m = msgs.first(where: { $0.id == "m0_4" }) { forward = ForwardBox(messages: [m]) }
        default: break
        }
    }
    #endif
}

// MARK: - пузырь

struct Bubble: View {
    let message: Message
    var highlighted = false
    var canUnsend = false
    var canForward = false
    var onReply: () -> Void = {}
    var onDelete: () -> Void = {}
    var onOpenMedia: (Int) -> Void = { _ in }
    var onQuoteTap: (String) -> Void = { _ in }
    var onForward: () -> Void = {}
    var onSelect: () -> Void = {}
    @State private var previewURL: URL?
    @State private var loadingFile = false
    @State private var swipe: CGFloat = 0

    var body: some View {
        let out = message.isOut
        let atts: [Attachment] = message.attachments ?? []
        let bare: Bool = atts.count == 1 && atts[0].round == true && message.body.isEmpty && message.replyTo == nil
        let voiceOnly: Bool = atts.count == 1 && atts[0].kind == "audio" && message.body.isEmpty
        let pad: CGFloat = bare || (atts.isEmpty && message.replyTo == nil) ? 0 : 4
        HStack {
            if out { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                if let q = message.replyTo {
                    quote(q, out: out)
                }
                ForEach(Array(atts.enumerated()), id: \.offset) { i, a in
                    attachment(a, index: i, out: out, showTime: voiceOnly)
                }
                if !message.body.isEmpty || atts.isEmpty {
                    textBlock(out: out)
                } else if !bare && !voiceOnly {
                    // кружок и голосовое показывают время сами (капсула у круга / строка под волной)
                    HStack { Spacer(); time(out: out) }.padding(.horizontal, 8).padding(.bottom, 2)
                }
            }
            .padding(.horizontal, pad)
            .padding(.vertical, pad)
            .background { if !bare { bubbleShape(out: out) } }
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Pal.acc, lineWidth: 2)
                }
            }
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contextMenu { menu(atts) }
            if !out { Spacer(minLength: 60) }
        }
        .overlay(alignment: .trailing) {
            if swipe < -8 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 16)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(swipe < -55 ? 0.3 : 0.15)))
                    .offset(x: 40)
                    .opacity(Double(min(1, -swipe / 55)))
            }
        }
        .offset(x: swipe)
        .simultaneousGesture(swipeGesture)
        .quickLookPreview($previewURL)
    }

    /// Смахнуть пузырь влево — ответить (как в Telegram).
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                let dx: CGFloat = v.translation.width
                guard dx < 0, abs(dx) > abs(v.translation.height) * 2 else { return }
                let was: Bool = swipe < -55
                swipe = max(-80, dx)
                if !was && swipe < -55 { haptic() }
            }
            .onEnded { _ in
                if swipe < -55 { onReply() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { swipe = 0 }
            }
    }

    /// Текст для «Скопировать»: сам текст, а у голосового/кружка — расшифровка, если она уже есть.
    private var copyText: String {
        if !message.body.isEmpty { return message.body }
        return message.transcript?.text ?? ""
    }

    /// Меню по удержанию (как в Telegram): Ответить, Копировать, Переслать, Выбрать, Удалить своё.
    /// Реакций и редактирования нет: сервер их пока не поддерживает.
    @ViewBuilder private func menu(_ atts: [Attachment]) -> some View {
        Button { onReply() } label: { Label("Ответить", systemImage: "arrowshape.turn.up.left") }
        if !copyText.isEmpty {
            Button { UIPasteboard.general.string = copyText } label: { Label("Копировать", systemImage: "doc.on.doc") }
        }
        if canForward {
            Button { onForward() } label: { Label("Переслать", systemImage: "arrowshape.turn.up.right") }
        }
        if let i = atts.firstIndex(where: { $0.kind == "image" || $0.kind == "video" }) {
            Button { onOpenMedia(i) } label: { Label("Открыть", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        Button { onSelect() } label: { Label("Выбрать", systemImage: "checkmark.circle") }
        if canUnsend {
            Button(role: .destructive) { onDelete() } label: { Label("Удалить у всех", systemImage: "trash") }
        }
    }

    private func quote(_ q: ReplyRef, out: Bool) -> some View {
        Button { onQuoteTap(q.id) } label: {
            HStack(spacing: 8) {
                Rectangle().fill(out ? Pal.ink.opacity(0.6) : Pal.acc).frame(width: 3).clipShape(Capsule())
                VStack(alignment: .leading, spacing: 1) {
                    Text(q.dir == "out" ? String(localized: "Вы") : String(localized: "Клиент")).font(Typo.body(12, .semibold))
                        .foregroundStyle(out ? Pal.ink.opacity(0.8) : Pal.acc)
                    Text(q.text).font(Typo.body(13)).lineLimit(2)
                        .foregroundStyle((out ? Pal.ink : Color.white).opacity(0.75))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: 260, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill((out ? Pal.ink : Color.white).opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func bubbleShape(out: Bool) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: out ? 20 : 6, bottomTrailingRadius: out ? 6 : 20, topTrailingRadius: 20, style: .continuous)
        if out {
            shape.fill(Pal.acc)
        } else {
            shape.fill(Color.white.opacity(0.13))
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    private func time(out: Bool) -> some View {
        HStack(spacing: 3) {
            Text(Fmt.hm(message.date)).font(Typo.body(11))
            if out { SentMark(size: 10) }
        }
        .foregroundStyle((out ? Pal.ink : Color.white).opacity(0.62))
    }

    private func textBlock(out: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(message.body.isEmpty ? String(localized: "Вложение") : message.body)
                .font(Typo.body(15.5))
                .foregroundStyle(out ? Pal.ink : .white)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let tr = message.translation, !tr.text.isEmpty {
                Text(out ? String(localized: "вы написали: \(tr.text)") : String(localized: "перевод: \(tr.text)"))
                    .font(Typo.body(13))
                    .foregroundStyle((out ? Pal.ink : Color.white).opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            time(out: out)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder private func attachment(_ a: Attachment, index: Int, out: Bool, showTime: Bool = false) -> some View {
        let url = API.media(a.url)
        switch a.kind {
        case "image":
            Button { onOpenMedia(index) } label: {
                RemoteImage(raw: a.url)
                    .frame(width: 230, height: 180)
                    .background(placeholder("photo"))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Фото, открыть")
        case "audio":
            AudioBubble(url: url, raw: a.url, out: out, message: message, showTime: showTime, mime: a.mime,
                        serverWave: a.waveform, serverDuration: a.duration)
        case "video" where a.round == true:
            RoundNoteBubble(raw: a.url, out: out, message: message, onOpen: { onOpenMedia(index) })
        case "video":
            Button { onOpenMedia(index) } label: {
                ZStack {
                    if a.round == true {
                        LinearGradient(colors: [Pal.sky.opacity(0.45), Color(hex: 0xFFB8D6).opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 1)
                    } else {
                        placeholder("video")
                    }
                    Image(systemName: "play.fill").font(.system(size: 24)).foregroundStyle(.white)
                        .frame(width: 54, height: 54).background(Circle().fill(Color.black.opacity(0.35)))
                }
                .frame(width: a.round == true ? 190 : 230, height: a.round == true ? 190 : 150)
                .clipShape(a.round == true ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(a.round == true ? String(localized: "Кружок, смотреть") : String(localized: "Видео, смотреть"))
        default:
            Button { if let url { Task { await openFile(url, a) } } } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(out ? Pal.ink.opacity(0.12) : Color.white.opacity(0.15))
                        if loadingFile { ProgressView() } else { Image(systemName: "doc").font(.system(size: 16)) }
                    }
                    .frame(width: 38, height: 38)
                    Text(a.name ?? String(localized: "Файл")).font(Typo.body(14, .medium)).lineLimit(2)
                }
                .foregroundStyle(out ? Pal.ink : .white)
                .padding(8)
                .frame(maxWidth: 240, alignment: .leading)
            }
            .buttonStyle(PressStyle())
        }
    }

    private func placeholder(_ icon: String) -> some View {
        ZStack {
            LinearGradient(colors: [Pal.sky.opacity(0.35), Color(hex: 0xFFB8D6).opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.white)
        }
    }

    /// Файл — во временную папку с правильным расширением (без него Quick Look показывает пустой экран).
    private func openFile(_ url: URL, _ a: Attachment) async {
        loadingFile = true
        defer { loadingFile = false }
        do {
            let data = try await API.download(url)
            var name = (a.name ?? "file").replacingOccurrences(of: "/", with: "_")
            if (name as NSString).pathExtension.isEmpty, let mime = a.mime, let ext = UTType(mimeType: mime)?.preferredFilenameExtension {
                name += "." + ext
            }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + name)
            try data.write(to: dest)
            previewURL = dest
        } catch {}
    }
}

struct URLBox: Identifiable { let url: URL; var id: String { url.absoluteString } }

/// Названия языков для подписи перевода — из системной локали на языке интерфейса.
enum LangName {
    static func acc(_ code: String) -> String {
        let c: String = String(code.lowercased().prefix(2))
        if let n = uiLocale.localizedString(forLanguageCode: c), !n.isEmpty { return n }
        return String(localized: "язык клиента")
    }
}


extension LangName {
    /// «на турецком» (падеж только для русского интерфейса)
    static func prep(_ code: String) -> String {
        let a = acc(code)
        guard uiLocale.language.languageCode?.identifier == "ru" else { return a }
        if a.hasSuffix("ий") { return String(a.dropLast(2)) + "ом" } // i18n: no
        return a
    }
}

/// Подсказка один раз: пишите по-русски — переведём.
struct ChatTranslateHint: View {
    let langName: String
    let done: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: done)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "globe").font(.system(size: 26, weight: .semibold))
                Text("Пишите по-русски").font(Typo.display(20))
                Text("Сообщения клиента переводятся на русский, а ваш ответ уйдёт на \(langName) автоматически. Перевод выключается значком языка в шапке чата.")
                    .font(Typo.body(15)).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
                Button(action: done) {
                    Text("Понятно").font(Typo.body(16, .semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(20)
            .glassRect(28)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}

/// Лист «Перевод переписки»: что происходит и переключатель перевода исходящих.
struct TranslateSheet: View {
    @Environment(Store.self) private var store
    let lang: String
    /// чат, из которого открыт лист: после согласия сразу переводим входящие
    var convId: String? = nil
    /// алерт согласия на ИИ — свой: поверх листа алерт RootView не показывается
    @State private var askAI = false

    private var outOn: Bool { store.translateOut && store.aiConsent }

    private func setOut(_ v: Bool) {
        if v && !store.aiConsent {
            askAI = true
            return
        }
        withAnimation(.spring(response: 0.3)) { store.translateOut = v }
    }

    var body: some View {
        SheetBox(title: String(localized: "Перевод переписки"), subtitle: String(localized: "Клиент пишет на \(LangName.prep(lang))")) {
            Text("Входящие переводим на русский автоматически — перевод под сообщением. Вы пишете по-русски, а клиенту уходит на \(LangName.acc(lang)).")
                .font(Typo.body(14)).foregroundStyle(Pal.fg2).lineSpacing(3)
                .padding(.horizontal, 8).padding(.bottom, 6)
            SheetOption(icon: "globe", title: String(localized: "Переводить мои ответы"), subtitle: outOn ? String(localized: "уйдёт на \(LangName.acc(lang))") : String(localized: "уйдёт как написано"), action: {
                setOut(!outOn)
            }) {
                GlassSwitch(isOn: Binding(get: { outOn }, set: { (v: Bool) in setOut(v) }))
            }
        }
        .alert(Text("Перевод и расшифровка через ИИ"), isPresented: $askAI) {
            Button("Разрешить") {
                store.aiConsentSaved = true
                store.translateOut = true
                if let id = convId { Task { await store.translateIncoming(id) } }
            }
            Button("Не сейчас", role: .cancel) {}
        } message: {
            Text("Для перевода и расшифровки текст и звук сообщений отправляются в сторонний ИИ-сервис (Groq). Разрешить?")
        }
    }
}

/// Высота нижней панели чата (поле ввода + ответ/подсказка).
private struct ChatBottomHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Высота ленты (видимая область ScrollView).
private struct ChatScrollHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Положение нижней метки ленты относительно видимой области (по нему — кнопка «вниз»).
private struct ChatSentinelKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Своё текстовое сообщение, которое ещё в пути или не ушло.
struct PendingMsg: Identifiable, Equatable {
    let id: String
    let text: String
    let replyTo: Message?
    var failed: Bool = false
}

/// Статус своего сообщения. Сервер пока не отдаёт «доставлено/прочитано», поэтому честно — одна галочка «отправлено».
struct SentMark: View {
    var size: CGFloat = 10
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size, weight: .bold))
            .accessibilityLabel("Отправлено")
    }
}

struct ForwardBox: Identifiable {
    let id = UUID()
    let messages: [Message]
}

/// «Переслать»: выбор другого чата кабинета. Уходит текст и файлы, лежащие в кабинете (mediaId);
/// файлы бота Telegram хранятся в самом Telegram, их переслать нельзя.
struct ForwardSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let messages: [Message]
    let fromConv: String
    var done: () -> Void = {}

    private var targets: [Conversation] {
        let list: [Conversation] = store.state.conversations.filter { $0.id != fromConv }
        let sorted: [Conversation] = list.sorted { (a: Conversation, b: Conversation) -> Bool in
            (a.last?.date ?? .distantPast) > (b.last?.date ?? .distantPast)
        }
        return Array(sorted.prefix(60))
    }

    var body: some View {
        SheetBox(title: String(localized: "Переслать"), subtitle: String(localized: "Выберите чат кабинета")) {
            if targets.isEmpty {
                Text("Других чатов пока нет").font(Typo.body(14)).foregroundStyle(Pal.fg2).padding(8)
            }
            ForEach(targets) { c in
                row(c)
            }
        }
    }

    private func row(_ c: Conversation) -> some View {
        let contact: Contact? = store.contact(c.contactId)
        let name: String = contact?.name ?? String(localized: "Клиент")
        let net = NetInfo.of(c.network)
        return Button { send(to: c, name: name) } label: {
            HStack(spacing: 12) {
                Avatar(name: name, hue: contact?.displayHue ?? 0, url: contact?.avatar, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Typo.body(15, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(net.name).font(Typo.body(12)).foregroundStyle(Pal.fg2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func send(to c: Conversation, name: String) {
        haptic()
        let items: [Message] = messages.sorted { $0.date < $1.date }
        dismiss()
        Task {
            var sent = 0
            var lost = 0
            for m in items {
                let all: [Attachment] = m.attachments ?? []
                let atts: [Attachment] = all.filter { $0.mediaId != nil }
                lost += all.count - atts.count
                if m.body.isEmpty && atts.isEmpty { continue }
                let round: Bool = atts.first?.round == true
                if await store.send(c.id, text: m.body, attachments: atts, round: round) { sent += 1 } else { break }
            }
            if sent > 0 && lost > 0 {
                store.show(String(localized: "Переслано в «\(name)», но часть файлов переслать нельзя"))
            } else if sent > 0 {
                store.show(String(localized: "Переслано в «\(name)»"))
            } else if lost > 0 {
                store.show(String(localized: "Эти файлы хранятся в Telegram, переслать их нельзя"), ok: false)
            }
            done()
        }
    }
}

#if DEBUG
/// Только для снимка CI: так выглядит меню по удержанию (системное контекстное меню на снимке симулятора не открыть).
struct MessageMenuMock: View {
    let message: Message
    let canUnsend: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(alignment: message.isOut ? .trailing : .leading, spacing: 10) {
                Bubble(message: message).allowsHitTesting(false)
                VStack(spacing: 0) {
                    item("Ответить", "arrowshape.turn.up.left")
                    Divider().overlay(Color.white.opacity(0.12))
                    item("Копировать", "doc.on.doc")
                    Divider().overlay(Color.white.opacity(0.12))
                    item("Переслать", "arrowshape.turn.up.right")
                    Divider().overlay(Color.white.opacity(0.12))
                    item("Выбрать", "checkmark.circle")
                    if canUnsend {
                        Divider().overlay(Color.white.opacity(0.12))
                        item("Удалить у всех", "trash", tint: Pal.danger)
                    }
                }
                .frame(width: 250)
                .glassRect(16)
            }
            .padding(.horizontal, 12)
        }
    }

    private func item(_ title: LocalizedStringKey, _ icon: String, tint: Color = .white) -> some View {
        HStack {
            Text(title).font(Typo.body(16))
            Spacer()
            Image(systemName: icon).font(.system(size: 16))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}
#endif
