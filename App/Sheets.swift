import SwiftUI
import UIKit

struct FolderSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contactId: String

    var body: some View {
        let c = store.contact(contactId)
        let curName: String = store.folder(c?.folderId)?.name ?? String(localized: "папки")
        SheetBox(title: String(localized: "Переложить в папку")) {
            if store.canRemoveFromFolder(contactId), let base = store.baseFolder {
                SheetOption(icon: "folder.badge.minus", iconColor: Pal.rose, title: String(localized: "Убрать из «\(curName)»"), subtitle: String(localized: "вернётся в «\(base.name)»"), action: {
                    dismiss()
                    Task { await store.removeFromFolder(contactId) }
                })
            }
            ForEach(store.folders) { f in
                SheetOption(icon: "circle.fill", iconColor: Color(css: f.color), title: f.name, on: c?.folderId == f.id, action: {
                    dismiss()
                    guard c?.folderId != f.id else { return }
                    Task { await store.perform([["type": "move", "contactId": contactId, "folderId": f.id]], contactId: contactId, ok: String(localized: "Папка «\(f.name)»")) }
                }) {
                    if c?.folderId == f.id { Image(systemName: "checkmark").foregroundStyle(Pal.acc) }
                }
            }
        }
    }
}

/// Переложить сразу несколько выбранных чатов (их клиентов) в папку или убрать из папок.
struct BatchFolderSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let convIds: Set<String>

    var body: some View {
        let ids: [String] = store.contactIds(of: convIds)
        SheetBox(title: String(localized: "Переложить в папку"), subtitle: String(localized: "Выбрано: \(ids.count) клиентов")) {
            if let base = store.baseFolder, ids.contains(where: { store.canRemoveFromFolder($0) }) {
                SheetOption(icon: "folder.badge.minus", iconColor: Pal.rose, title: String(localized: "Убрать из папок"), subtitle: String(localized: "вернутся в «\(base.name)»"), action: {
                    dismiss()
                    store.stopSelecting()
                    Task { await store.removeManyFromFolders(ids) }
                })
            }
            ForEach(store.folders) { f in
                let here: Int = ids.filter { store.contact($0)?.folderId == f.id }.count
                SheetOption(icon: "circle.fill", iconColor: Color(css: f.color), title: f.name, subtitle: here > 0 ? String(localized: "уже тут: \(here)") : nil, action: {
                    dismiss()
                    store.stopSelecting()
                    Task { await store.moveMany(ids, to: f.id) }
                })
            }
        }
    }
}

struct ReminderSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contactId: String
    @State private var text: String = String(localized: "Написать клиенту")
    @State private var custom = Date().addingTimeInterval(3 * 3600)
    @State private var showCustom = false

    var body: some View {
        let c = store.contact(contactId)
        let existing = store.reminder(for: contactId)
        SheetBox(title: String(localized: "Напомнить о клиенте"), subtitle: c?.name) {
            HStack {
                TextField("", text: $text, prompt: Text("Текст напоминания").foregroundColor(Pal.fg3))
                    .font(Typo.body(15)).foregroundStyle(Pal.fg)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.horizontal, 4).padding(.bottom, 6)
            ForEach(RemPreset.allCases, id: \.self) { p in
                SheetOption(icon: "clock", title: p.title, subtitle: Fmt.whenFull(p.date), action: { save(p.date) })
            }
            SheetOption(icon: "calendar", title: String(localized: "Выбрать дату и время"), action: { withAnimation { showCustom.toggle() } })
            if showCustom {
                let customWhen: String = Fmt.whenFull(custom)
                DatePicker("", selection: $custom, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .tint(Pal.acc)
                Button { save(custom) } label: {
                    Text(String(localized: "Напомнить \(customWhen)")).font(Typo.body(16, .semibold)).frame(maxWidth: .infinity).frame(height: 50).primaryFill(16)
                }
                .buttonStyle(PressStyle())
            }
            if let existing {
                Text("Сейчас стоит: \(Fmt.whenFull(existing.date)) — «\(existing.text)»")
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3).padding(.horizontal, 12).padding(.top, 8)
                SheetOption(icon: "checkmark.circle", iconColor: Pal.mint, title: String(localized: "Выполнено"), subtitle: String(localized: "напоминание закроется"), action: {
                    dismiss()
                    Task { await store.perform([["type": "doneReminder", "id": existing.id]], contactId: contactId, ok: String(localized: "Напоминание выполнено")) }
                })
                SheetOption(icon: "trash", iconColor: Pal.danger, title: String(localized: "Удалить напоминание"), color: Pal.danger, action: {
                    dismiss()
                    Task { await store.perform([["type": "removeReminder", "id": existing.id]], contactId: contactId, ok: String(localized: "Напоминание удалено")) }
                })
            }
        }
    }

    private func save(_ at: Date) {
        dismiss()
        let atWhen: String = Fmt.whenFull(at)
        let t = text.trimmingCharacters(in: .whitespaces)
        var bodies: [[String: Any]] = []
        if let old = store.reminder(for: contactId) { bodies.append(["type": "removeReminder", "id": old.id]) }
        bodies.append(["type": "remind", "contactId": contactId, "at": isoString(at), "text": t.isEmpty ? String(localized: "Написать клиенту") : t])
        Task { await store.perform(bodies, contactId: contactId, ok: String(localized: "Напомню \(atWhen)")) }
    }
}

struct TemplatesSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    private var fallback: [String] { [
        String(localized: "Здравствуйте! Спасибо, что написали. Подскажите, что вас интересует?"),
        String(localized: "Отправляю реквизиты для оплаты. После оплаты пришлите, пожалуйста, скрин."),
        String(localized: "Напоминаю о нашем разговоре — актуально?"),
        String(localized: "Спасибо за оплату! Всё получили."),
    ] }

    var body: some View {
        let list: [(String, String)] = store.state.templates.isEmpty
            ? fallback.map { (t: String) -> (String, String) in ("", t) }
            : store.state.templates.map { (t: Template) -> (String, String) in (t.title, t.text) }
        SheetBox(title: String(localized: "Шаблоны ответов"), subtitle: store.state.templates.isEmpty ? String(localized: "Свои шаблоны заводятся в веб-версии") : nil) {
            ForEach(list.indices, id: \.self) { i in
                Button {
                    dismiss(); onPick(list[i].1)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if !list[i].0.isEmpty { Text(list[i].0).font(Typo.body(13, .semibold)).foregroundStyle(Pal.acc) }
                        Text(list[i].1).font(Typo.body(15)).foregroundStyle(Pal.fg).multilineTextAlignment(.leading).lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

struct AttachSheet: View {
    var canNote = false
    let onPhoto: () -> Void
    let onFile: () -> Void
    let onTemplate: () -> Void
    let onVoice: () -> Void
    let onNote: () -> Void

    var body: some View {
        SheetBox(title: String(localized: "Прикрепить")) {
            SheetOption(icon: "photo", title: String(localized: "Фото или видео"), action: onPhoto)
            SheetOption(icon: "folder", title: String(localized: "Файл"), action: onFile)
            SheetOption(icon: "mic", title: String(localized: "Голосовое"), subtitle: String(localized: "удерживай микрофон справа от поля"), action: onVoice)
            if canNote {
                SheetOption(icon: "video.circle", title: String(localized: "Кружок"), subtitle: String(localized: "видео в круге до минуты, только Telegram"), action: onNote)
            }
            SheetOption(icon: "tag", title: String(localized: "Шаблон"), action: onTemplate)
        }
    }
}

/// «Написать»: только каналы, которые реально есть у клиента.
struct WriteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let contactId: String

    var body: some View {
        let c = store.contact(contactId)
        let convs = store.conversations(of: contactId)
        let phone = phoneOf(c, convs)
        SheetBox(title: String(localized: "Написать"), subtitle: String(localized: "Каналы, которые есть у клиента")) {
            ForEach(convs) { conv in
                let n = NetInfo.of(conv.network)
                SheetOption(icon: "circle.fill", iconColor: n.color, title: String(localized: "\(n.name) — в Sguardo"), subtitle: c?.handle ?? c?.name, action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.open(.chat(conv.id)) }
                }) { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Pal.fg3) }
            }
            if let phone, convs.contains(where: { $0.network == "whatsapp" }) || c?.phone != nil {
                SheetOption(icon: "arrow.up.right.square", title: String(localized: "Открыть в WhatsApp"), subtitle: phone, action: {
                    if let u = URL(string: "https://wa.me/" + phone.filter(\.isNumber)) { openURL(u) }
                })
            }
            if let h = telegramHandle(c, convs), let u = URL(string: "https://t.me/" + h) {
                SheetOption(icon: "arrow.up.right.square", title: String(localized: "Открыть в Telegram"), subtitle: "@" + h, action: { openURL(u) })
            }
            if let email = c?.email, !email.isEmpty {
                SheetOption(icon: "envelope", title: String(localized: "Почта"), subtitle: email, action: {
                    if let u = URL(string: "mailto:" + email) { openURL(u) }
                }) {
                    Button { UIPasteboard.general.string = email; store.show(String(localized: "Скопировано")) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 15)).foregroundStyle(Pal.fg2).frame(width: 36, height: 36)
                    }
                }
            }
            if (c?.email ?? "").isEmpty {
                Text("Почты и других сетей у клиента нет — добавятся, когда он напишет оттуда")
                    .font(Typo.body(12)).foregroundStyle(Pal.fg3).padding(.horizontal, 10).padding(.top, 6)
            }
        }
    }
}

struct CallSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let contactId: String

    var body: some View {
        let c = store.contact(contactId)
        let convs = store.conversations(of: contactId)
        SheetBox(title: String(localized: "Позвонить")) {
            if let phone = phoneOf(c, convs) {
                Text(phone)
                    .font(Typo.display(24))
                    .foregroundStyle(Pal.fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                SheetOption(icon: "phone", title: String(localized: "Обычный звонок"), action: {
                    if let u = URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" }) { openURL(u) }
                })
                SheetOption(icon: "message", title: String(localized: "Звонок в WhatsApp"), subtitle: String(localized: "откроет чат, там кнопка звонка"), action: {
                    if let u = URL(string: "https://wa.me/" + phone.filter(\.isNumber)) { openURL(u) }
                })
                SheetOption(icon: "doc.on.doc", title: String(localized: "Скопировать номер"), action: {
                    UIPasteboard.general.string = phone
                    store.show(String(localized: "Скопировано"))
                })
            } else {
                Text("У клиента нет номера телефона — он пишет из \(NetInfo.of(convs.first?.network).name). Можно попросить номер в чате.")
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).lineSpacing(3)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                if let conv = store.mainConversation(of: contactId) {
                    SheetOption(icon: "bubble.left", title: String(localized: "Попросить номер в чате"), subtitle: String(localized: "текст встанет в поле ввода, отправишь сама"), action: {
                        store.drafts[conv.id] = String(localized: "Подскажите, пожалуйста, номер телефона — так будет удобнее созвониться.")
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.open(.chat(conv.id)) }
                    })
                }
            }
        }
    }
}

struct LabelSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let contactId: String?
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetBox(title: String(localized: "Новая метка")) {
            HStack(spacing: 8) {
                TextField("", text: $name, prompt: Text("Например: опт").foregroundColor(Pal.fg3))
                    .font(Typo.body(16)).foregroundStyle(Pal.fg)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.horizontal, 14).frame(height: 46)
                    .glass(.light, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button(action: add) {
                    Text("Добавить").font(Typo.body(15, .semibold)).padding(.horizontal, 16).frame(height: 46).primaryFill(15)
                }
                .buttonStyle(PressStyle())
            }
            .padding(4)
        }
        .onAppear { focused = true }
    }

    private func add() {
        let v = String(name.trimmingCharacters(in: .whitespaces).prefix(30))
        guard !v.isEmpty else { return }
        store.addLabel(v)
        dismiss()
        if let contactId, let c = store.contact(contactId) {
            var tags = c.tags ?? []
            if !tags.contains(v) { tags.append(v) }
            Task { await store.perform([["type": "updateContact", "contactId": contactId, "tags": tags]], contactId: contactId, ok: String(localized: "Метка «\(v)» добавлена")) }
        } else {
            store.show(String(localized: "Метка «\(v)» добавлена"))
        }
    }
}

/// Удаление аккаунта (App Store 5.1.1(v)): POST /api/account/delete/ {"confirm": true}.
/// Владелец удаляет кабинет целиком (второй шаг — ввести слово «удалить»), помощник — только свою учётку.
struct DeleteSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Step { case ask, typeWord, done }
    @State private var step: Step = .ask
    @State private var typed: String = ""
    @State private var busy: Bool = false
    @State private var errorText: String?
    @State private var note: String?
    /// Сервер удалил аккаунт — при закрытии листа чистим телефон и выходим на вход.
    @State private var deleted: Bool = false
    @FocusState private var wordFocused: Bool

    private var isOwner: Bool { store.user?.isOwner == true }
    /// Слово подтверждения на языке интерфейса (на сервер всегда уходит {"confirm": true}).
    private var confirmWord: String { String(localized: "удалить") }
    private var wordOK: Bool {
        let t: String = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: uiLocale)
        if t.isEmpty { return false }
        return t == confirmWord.lowercased(with: uiLocale) || t == "удалить"  // i18n: no
    }

    var body: some View {
        SheetBox(title: nil) {
            switch step {
            case .ask: askStep
            case .typeWord: wordStep
            case .done: doneStep
            }
        }
        .interactiveDismissDisabled(busy || step == .done)
        .onDisappear { if deleted { store.finishAccountDeletion() } }
    }

    private var askText: String {
        isOwner
            ? String(localized: "Удалить аккаунт и кабинет? Отключим все каналы, удалим переписку, контакты, файлы и помощников — вернуть нельзя")
            : String(localized: "Удалить свой аккаунт? Кабинет и переписка останутся у владельца")
    }

    private var askStep: some View {
        VStack(spacing: 8) {
            header(title: String(localized: "Удалить аккаунт?"), text: askText)
            errorLine
            dangerButton(title: isOwner ? String(localized: "Продолжить") : String(localized: "Удалить аккаунт"), enabled: !busy) {
                if isOwner { errorText = nil; step = .typeWord } else { startSubmit() }
            }
            cancelButton
        }
    }

    private var wordStep: some View {
        VStack(spacing: 8) {
            header(title: String(localized: "Точно удалить?"), text: String(localized: "Чтобы подтвердить, введите слово «\(confirmWord)»."))
            TextField(confirmWord, text: $typed)
                .font(Typo.body(17)).foregroundStyle(Pal.fg)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($wordFocused)
                .onSubmit { if wordOK { startSubmit() } }
                .padding(.horizontal, 14).frame(minHeight: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.fg.opacity(0.08)))
                .accessibilityLabel(String(localized: "Слово для подтверждения"))
                .accessibilityIdentifier("delete-word")
            errorLine
            dangerButton(title: String(localized: "Удалить навсегда"), enabled: wordOK && !busy) {
                startSubmit()
            }
            cancelButton
        }
        .onAppear { wordFocused = true }
    }

    private var doneStep: some View {
        VStack(spacing: 8) {
            header(title: String(localized: "Аккаунт удалён"), text: note ?? "")
            Button { dismiss() } label: {
                Text("Понятно").font(Typo.body(16, .semibold)).foregroundStyle(Pal.onAcc)
                    .frame(maxWidth: .infinity).frame(minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.acc))
            }
            .buttonStyle(PressStyle())
        }
    }

    private func header(title: String, text: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(Typo.display(18)).foregroundStyle(Pal.fg).multilineTextAlignment(.center)
            if !text.isEmpty {
                Text(text)
                    .font(Typo.body(15)).foregroundStyle(Pal.fg2).multilineTextAlignment(.center).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var errorLine: some View {
        if let e = errorText {
            Text(e).font(Typo.body(14)).foregroundStyle(Pal.danger).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity).padding(.bottom, 6)
        }
    }

    private func dangerButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { haptic(); action() } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(Pal.ink) }
                Text(title).font(Typo.body(16, .semibold))
            }
            .foregroundStyle(Pal.ink)
            .frame(maxWidth: .infinity).frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Pal.danger.opacity(enabled ? 1 : 0.4)))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("delete-confirm")
    }

    private var cancelButton: some View {
        Button { dismiss() } label: {
            Text("Отмена").font(Typo.body(16, .semibold)).foregroundStyle(Pal.fg).frame(maxWidth: .infinity).frame(minHeight: 50)
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
    }

    /// busy ставится синхронно — двойной тап не отправит два запроса.
    private func startSubmit() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task { await submit() }
    }

    private func submit() async {
        do {
            let n: String? = try await store.deleteAccount()
            busy = false
            deleted = true
            if let n {
                note = n
                step = .done
            } else {
                dismiss()
            }
        } catch let e as APIError {
            busy = false
            switch e.status {
            case 401:
                dismiss()
                await store.logout()
                store.show(String(localized: "Нужно войти заново"), ok: false)
            case 403:
                errorText = String(localized: "Аккаунт администратора сервиса удалить нельзя")
            default:
                errorText = e.message
            }
        } catch {
            busy = false
            errorText = friendly(error)
        }
    }
}

// MARK: - контакты клиента

func phoneOf(_ c: Contact?, _ convs: [Conversation]) -> String? {
    if let p = c?.phone, !p.isEmpty { return p }
    if convs.contains(where: { $0.network == "whatsapp" }), let h = c?.handle, h.filter(\.isNumber).count >= 7 { return h }
    return nil
}

func telegramHandle(_ c: Contact?, _ convs: [Conversation]) -> String? {
    guard convs.contains(where: { $0.network == "telegram" }), var h = c?.handle, !h.isEmpty else { return nil }
    if h.hasPrefix("@") { h.removeFirst() }
    if h.allSatisfy({ $0.isNumber || $0 == "+" }) { return nil }
    if h.contains(" ") { return nil }
    return h
}
