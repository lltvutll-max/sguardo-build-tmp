import SwiftUI

struct ChatsView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dts
    @State private var net = "all"
    @State private var q = ""
    @State private var folderSheetFor: String?
    @State private var folderPicker = false
    /// чат, для которого открыт лист «Ещё» (свайп влево)
    @State private var moreFor: String?

    /// Сети в фильтре (чаты других сетей, если придут с сервера, видны во «Все»).
    static let nets: [String] = ["whatsapp", "telegram", "instagram", "threads"]

    private func matches(_ c: Conversation, query: String) -> Bool {
        let contact: Contact? = store.contact(c.contactId)
        if store.chatFolder != "all" && contact?.folderId != store.chatFolder { return false }
        if net != "all" && c.network != net { return false }
        if query.isEmpty { return true }
        var parts: [String] = [contact?.name ?? "", contact?.handle ?? "", contact?.phone ?? ""]
        parts.append(contentsOf: c.messages.map { $0.body })
        let hay: String = parts.joined(separator: " ").lowercased()
        return hay.contains(query)
    }

    private var rows: [Conversation] {
        let query: String = q.trimmingCharacters(in: .whitespaces).lowercased()
        var list: [Conversation] = store.state.conversations.filter { matches($0, query: query) }
        list.sort { (a: Conversation, b: Conversation) -> Bool in
            let pa: Bool = store.pinned.contains(a.id)
            let pb: Bool = store.pinned.contains(b.id)
            if pa != pb { return pa }
            return lastDate(a) > lastDate(b)
        }
        return list
    }

    private func lastDate(_ c: Conversation) -> Date { c.last?.date ?? store.contact(c.contactId)?.first ?? .distantPast }

    private var title: String {
        guard store.chatSelecting else { return String(localized: "Чаты") }
        let n: Int = store.chatSelected.count
        return n == 0 ? String(localized: "Выберите чаты") : String(localized: "Выбрано: \(n) чатов")
    }

    /// при очень крупном шрифте в шапке остаются только значки (подписи — для VoiceOver)
    private var compact: Bool { dts.isAccessibilitySize }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            if store.chatSelecting { selectHeader } else { header }
            Text(title)
                .font(Typo.display(30))
                .tracking(-0.9)
                .foregroundStyle(Pal.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .contentTransition(.numericText())
            search
            chips
            if store.chatSelecting { selectChips }
            list
        }
        .screenBackground(store.wall)
        .overlay(alignment: .bottom) {
            if store.chatSelecting {
                SelectionBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: Binding(get: { folderSheetFor.map(IDBox.init) }, set: { folderSheetFor = $0?.id })) { box in
            FolderSheet(contactId: box.id)
        }
        .sheet(isPresented: $store.chatBatchFolderSheet) {
            BatchFolderSheet(convIds: store.chatSelected)
        }
        .sheet(isPresented: $folderPicker) {
            FolderPickerSheet()
        }
        .confirmationDialog(moreTitle, isPresented: Binding(get: { moreFor != nil }, set: { if !$0 { moreFor = nil } }),
                            titleVisibility: .visible, presenting: moreFor.flatMap { store.conversation($0) }) { conv in
            moreActions(conv)
        }
    }

    private var folderTitle: String {
        guard store.chatFolder != "all", let f = store.folder(store.chatFolder) else { return String(localized: "Папки") }
        return f.name
    }

    private var header: some View {
        HStack(spacing: 8) {
            PillButton(action: { folderPicker = true }) {
                Image(systemName: store.chatFolder == "all" ? "folder" : "folder.fill").font(.icon(16))
                if !compact { Text(folderTitle).frame(maxWidth: 130) }
            }
            .accessibilityLabel(String(localized: "Папки: \(folderTitle)"))
            .accessibilityIdentifier("chats-folders")
            Spacer(minLength: 4)
            netMenu
            PillButton(action: { store.startSelecting() }) {
                Image(systemName: "checkmark.circle").font(.icon(16))
                if !compact { Text("Выбрать") }
            }
            .accessibilityLabel(String(localized: "Выбрать несколько чатов"))
            .accessibilityIdentifier("chats-select")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func netCount(_ n: String) -> Int {
        store.state.conversations.filter { $0.network == n }.count
    }

    private var netTitle: String {
        net == "all" ? String(localized: "Все") : NetInfo.of(net).name
    }

    @ViewBuilder private var netDots: some View {
        if net == "all" {
            HStack(spacing: -4) {
                Circle().fill(Color(hex: 0x25D366)).frame(width: 10, height: 10)
                Circle().fill(Color(hex: 0x2AABEE)).frame(width: 10, height: 10)
            }
        } else {
            Circle().fill(NetInfo.of(net).color).frame(width: 10, height: 10)
                .overlay(Circle().stroke(Pal.fg.opacity(0.5), lineWidth: 1))
        }
    }

    /// Фильтр по сетям: меню со всеми сетями и числом чатов в каждой.
    private var netMenu: some View {
        Menu {
            Picker("Сеть", selection: Binding(get: { net }, set: { (v: String) in withAnimation(.spring(response: 0.3)) { net = v } })) {
                Text("Все сети").tag("all")
                ForEach(ChatsView.nets, id: \.self) { (n: String) in
                    Text("\(NetInfo.of(n).name) · \(netCount(n))").tag(n)
                }
            }
        } label: {
            HStack(spacing: 6) {
                netDots
                Text(netTitle).font(Typo.body(14, .medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.icon(11, .semibold)).opacity(0.7)
            }
            .foregroundStyle(Pal.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .tint(Pal.fg)
        .glassCapsule(interactive: true)
        .accessibilityLabel(String(localized: "Сеть: \(netTitle)"))
        .accessibilityIdentifier("chats-net")
    }

    private var selectHeader: some View {
        let visible: [String] = rows.map(\.id)
        let all: Bool = !visible.isEmpty && visible.allSatisfy { store.chatSelected.contains($0) }
        return HStack(spacing: 8) {
            PillButton(action: { store.stopSelecting() }) {
                Text("Отменить")
            }
            Spacer()
            PillButton(action: {
                withAnimation(.spring(response: 0.3)) {
                    if all { store.chatSelected.subtract(visible) } else { store.chatSelected.formUnion(visible) }
                }
            }) {
                Image(systemName: all ? "circle" : "checkmark.circle.fill").font(.icon(16))
                Text(all ? String(localized: "Снять все") : String(localized: "Выбрать все"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.icon(15)).foregroundStyle(Pal.fg.opacity(0.7)).accessibilityHidden(true)
            TextField("", text: $q, prompt: Text("Поиск по клиентам и сообщениям").foregroundColor(Pal.fg3))
                .font(Typo.body(15))
                .foregroundStyle(Pal.fg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(String(localized: "Поиск по клиентам и сообщениям"))
            if !q.isEmpty {
                Button { q = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Pal.fg3).frame(minWidth: 32, minHeight: 32)
                }
                .accessibilityLabel(String(localized: "Очистить поиск"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .glassCapsule()
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let all = store.state.conversations
                let unreadAll = all.reduce(0) { $0 + $1.unread }
                Chip(text: String(localized: "Все"), count: unreadAll > 0 ? "• \(unreadAll)" : "\(all.count)", on: store.chatFolder == "all") {
                    withAnimation(.spring(response: 0.3)) { store.chatFolder = "all" }
                }
                ForEach(store.folders) { f in
                    let inF = all.filter { store.contact($0.contactId)?.folderId == f.id }
                    let unread = inF.reduce(0) { $0 + $1.unread }
                    Chip(text: f.name, dot: Color(css: f.color), count: unread > 0 ? "• \(unread)" : "\(inF.count)", on: store.chatFolder == f.id) {
                        withAnimation(.spring(response: 0.3)) { store.chatFolder = f.id }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.top, 12)
    }

    /// Быстрый выбор среди видимых чатов: заменяет текущий выбор.
    private func quickChip(_ text: String, _ ids: [String]) -> some View {
        let set = Set(ids)
        let on: Bool = !set.isEmpty && set == store.chatSelected
        return Chip(text: text, count: "\(ids.count)", on: on, height: 36, fontSize: 14) {
            withAnimation(.spring(response: 0.3)) { store.chatSelected = on ? [] : set }
        }
    }

    private var selectChips: some View {
        let items: [Conversation] = rows
        let unread: [String] = items.filter { $0.unread > 0 }.map(\.id)
        let read: [String] = items.filter { $0.unread == 0 }.map(\.id)
        let noReply: [String] = items.filter { (c: Conversation) -> Bool in c.last?.isOut == false }.map(\.id)
        let pinnedIds: [String] = items.filter { store.pinned.contains($0.id) }.map(\.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Выбрать:").font(Typo.body(14, .medium)).foregroundStyle(Pal.fg2)
                quickChip(String(localized: "Непрочитанные"), unread)
                quickChip(String(localized: "Прочитанные"), read)
                quickChip(String(localized: "Без ответа"), noReply)
                if !pinnedIds.isEmpty { quickChip(String(localized: "Закреплённые"), pinnedIds) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.top, 10)
    }

    private var footerHint: String {
        String(localized: "Смахните чат вправо — закрепить и прочитано, влево — в папку и «Ещё». Удержание — все действия. «Выбрать» сверху — сразу несколько чатов")
    }

    private var list: some View {
        let items = rows
        let selecting: Bool = store.chatSelecting
        return List {
            ForEach(items) { conv in
                ChatRow(conv: conv, selecting: selecting, selected: store.chatSelected.contains(conv.id))
                    .contextMenu { menu(conv) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !selecting { leadingSwipes(conv) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !selecting { trailingSwipes(conv) }
                    }
            }
            if items.isEmpty {
                emptyView
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if !selecting {
                Text(footerHint)
                    .font(Typo.body(13)).foregroundStyle(Pal.fg3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 4, for: .scrollContent)
        .contentMargins(.bottom, 110, for: .scrollContent)
        .refreshable { await store.loadState(force: true) }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
                .fill(Color.clear)
                .glass(.dark, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: пустые экраны

    private func resetFilters() {
        withAnimation(.spring(response: 0.3)) {
            q = ""
            net = "all"
            store.chatFolder = "all"
        }
    }

    @ViewBuilder private var emptyView: some View {
        let query: String = q.trimmingCharacters(in: .whitespaces)
        if store.state.conversations.isEmpty {
            if !store.stateLoaded && store.lastError == nil {
                ChatListSkeleton()
            } else if let e = store.lastError {
                EmptyState(icon: "wifi.exclamationmark", title: String(localized: "Не получилось загрузить чаты"), text: e,
                           actionTitle: String(localized: "Повторить"), action: { Task { await store.loadState(force: true) } })
            } else {
                EmptyState(icon: "bubble.left.and.bubble.right", title: String(localized: "Чатов пока нет"),
                           text: String(localized: "Подключите WhatsApp или Telegram в веб-версии Sguardo — переписки появятся здесь сами."),
                           actionTitle: String(localized: "Открыть веб-версию"), action: { openURL(API.webCabinet) })
            }
        } else if !query.isEmpty {
            let filtered: Bool = net != "all" || store.chatFolder != "all"
            EmptyState(icon: "magnifyingglass", title: String(localized: "Ничего не нашлось"),
                       text: filtered
                           ? String(localized: "По запросу «\(query)» нет чатов в выбранной папке или сети. Попробуйте поискать во всех чатах.")
                           : String(localized: "По запросу «\(query)» нет ни клиентов, ни сообщений. Проверьте написание."),
                       actionTitle: filtered ? String(localized: "Искать во всех чатах") : String(localized: "Сбросить поиск"),
                       action: { if filtered { net = "all"; store.chatFolder = "all" } else { q = "" } })
        } else if net != "all" {
            EmptyState(icon: "line.3.horizontal.decrease.circle", title: String(localized: "Нет чатов из \(NetInfo.of(net).name)"),
                       text: String(localized: "Здесь появятся переписки из этой сети, когда она подключена в веб-версии и клиенты напишут."),
                       actionTitle: String(localized: "Показать все сети"), action: { withAnimation { net = "all" } })
        } else {
            let name: String = store.folder(store.chatFolder)?.name ?? ""
            EmptyState(icon: "folder", title: String(localized: "В «\(name)» пока пусто"),
                       text: String(localized: "Чтобы переложить сюда клиента, смахните его чат влево и нажмите «В папку»."),
                       actionTitle: String(localized: "Показать все чаты"), action: { resetFilters() })
        }
    }

    // MARK: действия с чатом

    private func isUnread(_ conv: Conversation) -> Bool {
        conv.unread > 0 || Prefs.shared.isMarkedUnread(conv.id)
    }

    /// Прочитано ↔ непрочитано. Сервер умеет только «прочитано», поэтому «непрочитано» — отметка на этом телефоне
    /// (точка у чата, снимается при открытии).
    private func toggleRead(_ conv: Conversation) {
        let p: Prefs = Prefs.shared
        let id: String = conv.id
        if isUnread(conv) {
            let wasMarked: Bool = p.isMarkedUnread(id)
            withAnimation(.spring(response: 0.3)) { p.setMarkedUnread(id, false) }
            if conv.unread > 0 {
                store.markReadMany([id])
            } else {
                store.show(String(localized: "Прочитано"), undo: {
                    withAnimation(.spring(response: 0.3)) { p.setMarkedUnread(id, wasMarked) }
                })
            }
        } else {
            withAnimation(.spring(response: 0.3)) { p.setMarkedUnread(id, true) }
            store.show(String(localized: "Отмечен непрочитанным (на этом телефоне)"), undo: {
                withAnimation(.spring(response: 0.3)) { p.setMarkedUnread(id, false) }
            })
        }
    }

    private var moreTitle: String {
        guard let id = moreFor, let c = store.conversation(id) else { return "" }
        return store.contact(c.contactId)?.name ?? String(localized: "Клиент")
    }

    @ViewBuilder private func moreActions(_ conv: Conversation) -> some View {
        let isPinned: Bool = store.pinned.contains(conv.id)
        Button(isPinned ? String(localized: "Открепить") : String(localized: "Закрепить сверху")) { store.togglePinUndoable(conv.id) }
        Button(isUnread(conv) ? String(localized: "Отметить прочитанным") : String(localized: "Отметить непрочитанным")) { toggleRead(conv) }
        if store.canRemoveFromFolder(conv.contactId) {
            let name: String = store.folder(store.contact(conv.contactId)?.folderId)?.name ?? String(localized: "папки")
            Button(String(localized: "Убрать из «\(name)»")) { Task { await store.removeFromFolder(conv.contactId) } }
        }
        Button(String(localized: "Выбрать несколько")) { store.startSelecting(conv.id) }
        Button(String(localized: "Карточка клиента")) { store.open(.client(conv.contactId)) }
        Button(String(localized: "Отмена"), role: .cancel) {}
    }

    @ViewBuilder private func menu(_ conv: Conversation) -> some View {
        let isPinned: Bool = store.pinned.contains(conv.id)
        let unread: Bool = isUnread(conv)
        Button { store.togglePinUndoable(conv.id) } label: {
            Label(isPinned ? String(localized: "Открепить") : String(localized: "Закрепить сверху"), systemImage: isPinned ? "pin.slash" : "pin")
        }
        Button { toggleRead(conv) } label: {
            Label(unread ? String(localized: "Прочитано") : String(localized: "Непрочитано"), systemImage: unread ? "checkmark.message" : "message.badge")
        }
        Button { folderSheetFor = conv.contactId } label: { Label("В папку", systemImage: "folder") }
        if store.canRemoveFromFolder(conv.contactId) {
            let name: String = store.folder(store.contact(conv.contactId)?.folderId)?.name ?? String(localized: "папки")
            Button { Task { await store.removeFromFolder(conv.contactId) } } label: {
                Label("Убрать из «\(name)»", systemImage: "folder.badge.minus")
            }
        }
        if !store.chatSelecting {
            Button { store.startSelecting(conv.id) } label: { Label("Выбрать несколько", systemImage: "checkmark.circle") }
        }
        Button { store.open(.client(conv.contactId)) } label: { Label("Карточка клиента", systemImage: "person.crop.circle") }
    }

    /// Слева направо: «Закрепить» (полный свайп) и «Прочитано / Непрочитано».
    @ViewBuilder private func leadingSwipes(_ conv: Conversation) -> some View {
        let isPinned: Bool = store.pinned.contains(conv.id)
        let unread: Bool = isUnread(conv)
        Button {
            store.togglePinUndoable(conv.id)
        } label: { Label(isPinned ? String(localized: "Открепить") : String(localized: "Закрепить"), systemImage: isPinned ? "pin.slash.fill" : "pin.fill") }
            .tint(Color(hex: 0xE09A3E))
        Button {
            toggleRead(conv)
        } label: { Label(unread ? String(localized: "Прочитано") : String(localized: "Непрочитано"), systemImage: unread ? "checkmark.message.fill" : "message.badge.fill") }
            .tint(Color(hex: 0x2E9E6A))
    }

    /// Справа налево: «В папку» (полный свайп) и «Ещё» — остальное.
    @ViewBuilder private func trailingSwipes(_ conv: Conversation) -> some View {
        Button { folderSheetFor = conv.contactId } label: { Label("В папку", systemImage: "folder.fill") }
            .tint(Color(hex: 0x6A70E0))
        Button { moreFor = conv.id } label: { Label("Ещё", systemImage: "ellipsis.circle.fill") }
            .tint(Color(hex: 0x7A7685))
    }
}

/// Панель групповых действий вместо таб-бара в режиме выбора.
struct SelectionBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        let sel: Set<String> = store.chatSelected
        let ids: [String] = Array(sel)
        let none: Bool = sel.isEmpty
        let allPinned: Bool = !none && ids.allSatisfy { store.pinned.contains($0) }
        HStack(spacing: 2) {
            item("folder", "В папку", disabled: none) {
                store.chatBatchFolderSheet = true
            }
            item("folder.badge.minus", "Из папки", disabled: none) {
                let cids: [String] = store.contactIds(of: sel)
                store.stopSelecting()
                Task { await store.removeManyFromFolders(cids) }
            }
            item("checkmark.message", "Прочитано", disabled: none) {
                store.stopSelecting()
                store.markReadMany(ids)
            }
            item(allPinned ? "pin.slash" : "pin", allPinned ? LocalizedStringKey("Открепить") : LocalizedStringKey("Закрепить"), disabled: none) {
                store.stopSelecting()
                store.pinMany(ids)
            }
        }
        .padding(4)
        .glass(.bar, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    /// Серая кнопка не молчит: нажатие объясняет, почему она неактивна.
    private func item(_ icon: String, _ title: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            if disabled {
                store.show(String(localized: "Сначала отметьте чаты — нажмите на кружки слева"), ok: false)
            } else {
                action()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.icon(19))
                Text(title).font(Typo.body(12, .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Pal.fg.opacity(disabled ? 0.35 : 0.92))
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityHint(disabled ? Text("Сначала отметьте чаты") : Text(""))
    }
}

struct IDBox: Identifiable { let id: String }

struct ChatRow: View {
    @Environment(Store.self) private var store
    let conv: Conversation
    var selecting = false
    var selected = false

    var body: some View {
        let contact = store.contact(conv.contactId)
        let name = contact?.name ?? String(localized: "Клиент")
        let m = conv.last
        let marked: Bool = Prefs.shared.isMarkedUnread(conv.id)
        Button {
            if selecting {
                haptic()
                withAnimation(.spring(response: 0.25)) { store.toggleSelected(conv.id) }
            } else {
                store.open(.chat(conv.id))
            }
        } label: {
            HStack(spacing: 12) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.icon(23))
                        .foregroundStyle(selected ? Pal.acc : Pal.fg.opacity(0.45))
                        .transition(.scale.combined(with: .opacity))
                }
                ZStack(alignment: .bottomTrailing) {
                    Avatar(name: name, hue: contact?.displayHue ?? 200, url: contact?.avatar, size: 52)
                    NetBadge(net: conv.network).offset(x: 2, y: 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name).font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg).lineLimit(1)
                        if store.pinned.contains(conv.id) {
                            Image(systemName: "pin.fill").font(.icon(11)).foregroundStyle(Pal.fg3)
                        }
                        Spacer(minLength: 4)
                        if m?.isOut == true {
                            DoubleCheck(size: 11).foregroundStyle(Pal.mint)
                        }
                        Text(Fmt.when(m?.date ?? contact?.first ?? Date())).font(Typo.body(13)).foregroundStyle(Pal.fg2)
                    }
                    HStack(spacing: 8) {
                        Text(rowPreview(m))
                            .font(Typo.body(14)).foregroundStyle(Pal.fg2).lineLimit(1)
                        Spacer(minLength: 0)
                        if conv.unread > 0 {
                            Text("\(conv.unread)").font(Typo.body(12, .semibold)).foregroundStyle(Pal.onAcc)
                                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
                                .background(Capsule().fill(Pal.acc))
                                .transition(.scale)
                        } else if marked {
                            // «непрочитано» на этом телефоне — пустой кружок, как в Telegram
                            Circle().fill(Pal.acc).frame(width: 14, height: 14)
                                .transition(.scale)
                        }
                    }
                    HStack(spacing: 6) {
                        FolderTag(folder: store.folder(contact?.folderId))
                        ForEach(Array((contact?.tags ?? []).prefix(2)), id: \.self) { t in
                            Text(t).font(Typo.body(12, .medium)).foregroundStyle(Pal.fg.opacity(0.78))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Pal.fg.opacity(0.08)))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Pal.fg.opacity(selecting && selected ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(a11y(name: name, last: m, marked: marked))
        .accessibilityHint(selecting ? Text("Нажмите, чтобы отметить") : Text("Смахните вправо или влево — действия с чатом"))
        .accessibilityAddTraits(selecting && selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("chat-row")
    }

    private func a11y(name: String, last: Message?, marked: Bool) -> String {
        let netName: String = NetInfo.of(conv.network).name
        let preview: String = rowPreview(last)
        if conv.unread > 0 {
            return String(localized: "\(name), \(netName). Непрочитанных: \(conv.unread). \(preview)")
        }
        if marked {
            return String(localized: "\(name), \(netName). Отмечен непрочитанным. \(preview)")
        }
        return String(localized: "\(name), \(netName). \(preview)")
    }
}

func rowPreview(_ m: Message?) -> String {
    guard let m else { return "" }
    return m.isOut ? String(localized: "Вы: \(m.preview)") : m.preview
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Pal.fg.opacity(configuration.isPressed ? 0.06 : 0))
    }
}
