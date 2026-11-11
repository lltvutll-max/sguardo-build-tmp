import Foundation
import Observation
import SwiftUI
import UIKit
import UserNotifications
import LocalAuthentication

enum Phase { case launching, login, ready }
enum Tab: String, CaseIterable { case chats, today, summary, profile }

enum Route: Hashable {
    case chat(String)          // id переписки
    case client(String)        // id клиента
    case folders
    case outreach
    case partners
    case partnerLead(Int, Int)
}

/// Почему рассылка недоступна (ответ сервера 402/403).
struct OutreachDenied: Equatable {
    let needPay: Bool
    let text: String
}

struct Toast: Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
    /// «Отменить» сразу после действия (не показывается под экраном блокировки)
    var undo: (() -> Void)? = nil

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Всё состояние приложения. Данные — с сервера (/api/state), действия — через /api/actions и /api/messages/send,
/// живые обновления — SSE /api/events. Локально храним только то, чего в вебе нет: закреплённые чаты, черновики, обои.
@MainActor
@Observable
final class Store {
    var phase: Phase = .launching
    /// Сервер удалил аккаунт, лист ещё открыт (note): живые запросы не шлём, иначе 401 разлогинит раньше времени.
    var accountDeleted = false
    var user: User?
    var state: AppState = .empty
    var account: AccountInfo?
    var toast: Toast?
    var loading = false
    var lastError: String?
    var tab: Tab = .chats
    var chatsPath: [Route] = []
    var todayPath: [Route] = []
    var summaryPath: [Route] = []
    var profilePath: [Route] = []
    var fullHistory: [String: [Message]] = [:]
    var outreach: OutreachList?
    /// рассылка недоступна: 402 — нужна оплата, 403 — только владельцу кабинета
    var outreachDenied: OutreachDenied?
    /// первая загрузка рассылки не удалась (нет списка — показываем экран с «повторить»)
    var outreachLoadError: String?
    /// фирмы, скрытые до того, как «удалить/очистить» уйдёт на сервер (после тоста с «Отменить»)
    var outreachHidden: Set<String> = []
    @ObservationIgnored private var outreachPendingBody: [String: Any]?
    @ObservationIgnored private var outreachPendingIds: Set<String> = []
    @ObservationIgnored private var outreachTask: Task<Void, Never>?
    /// только снимки CI (-fixture): что открыть на экране рассылки ("all", "settings", "clear")
    var outreachFixtureScreen = ""
    var locked = false
    /// идёт системная проверка Face ID (включение/выключение в настройках): её окно переводит сцену в .inactive
    var authenticating = false
    /// за время проверки приложение уходило в фон — замок после неё не снимаем
    var wentBackground = false
    var fixture = false
    /// переводить исходящие на язык клиента при отправке (как в веб-кабинете); сервер переводит, только если язык клиента ≠ языку менеджера
    var translateOut: Bool = UserDefaults.standard.object(forKey: "translateOut") as? Bool ?? true {
        didSet { UserDefaults.standard.set(translateOut, forKey: "translateOut") }
    }
    var translateOn: Bool { state.workspace?.translate ?? true }

    // локальные настройки
    var wall: Wall = Wall(rawValue: UserDefaults.standard.string(forKey: "wall") ?? "") ?? .eye
    var pinned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "pinned") ?? [])
    var hintOff: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hintOff") ?? [])
    var extraLabels: [String] = UserDefaults.standard.stringArray(forKey: "labels") ?? []
    var drafts: [String: String] = [:]
    var dealDraft: [String: Int] = [:]
    var pushOn: Bool = UserDefaults.standard.object(forKey: "push") as? Bool ?? false
    var quietOn: Bool = UserDefaults.standard.object(forKey: "quiet") as? Bool ?? true
    var faceOn: Bool = UserDefaults.standard.object(forKey: "face") as? Bool ?? false

    // выбор чатов (групповые действия) и фильтр по папке
    var chatFolder: String = "all"
    var chatSelecting = false
    var chatSelected: Set<String> = []
    var chatBatchFolderSheet = false
    @ObservationIgnored private var pendingRead: Set<String> = []
    @ObservationIgnored private var readTask: Task<Void, Never>?

    @ObservationIgnored private var etag: String?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var reloadPending = false

    // кэш и свежесть данных
    /// данные кабинета уже есть (с диска или с сервера) — до этого список чатов показывает заглушки
    var stateLoaded = false
    /// перевод входящих идёт / не удался (id переписки → текст ошибки)
    var translating: Set<String> = []
    var translateFailed: [String: String] = [:]
    @ObservationIgnored private var translateTried: Set<String> = []
    @ObservationIgnored private var translateAgain: Set<String> = []
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var lastStateAt: Date?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// писать кэш на диск можно (вошли в аккаунт, не фикстуры)
    @ObservationIgnored private var cacheOn = false
    /// номер сессии: ответы запросов, начатых до выхода из аккаунта, отбрасываем
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var historyAt: [String: Date] = [:]
    @ObservationIgnored private var historyLoading: Set<String> = []
    @ObservationIgnored private var outreachAt: Date?
    @ObservationIgnored private var outreachLoad: Task<Void, Never>?

    // MARK: - удобные выборки

    var folders: [Folder] { state.folders }
    func folder(_ id: String?) -> Folder? { state.folders.first { $0.id == id } }
    func folder(key: String) -> Folder? { state.folders.first { $0.key == key } }
    func contact(_ id: String) -> Contact? { state.contacts.first { $0.id == id } }
    func conversation(_ id: String) -> Conversation? { state.conversations.first { $0.id == id } }
    func conversations(of contactId: String) -> [Conversation] { state.conversations.filter { $0.contactId == contactId } }
    func mainConversation(of contactId: String) -> Conversation? {
        conversations(of: contactId).max { ($0.last?.date ?? .distantPast) < ($1.last?.date ?? .distantPast) }
    }
    func reminder(for contactId: String) -> Reminder? {
        state.reminders.filter { $0.contactId == contactId && !$0.done }.min { $0.date < $1.date }
    }
    func deals(of contactId: String) -> [Deal] { state.deals.filter { $0.contactId == contactId } }
    var totalUnread: Int { state.conversations.reduce(0) { $0 + $1.unread } }
    var openReminders: [Reminder] { state.reminders.filter { !$0.done } }

    /// Все метки: из клиентов кабинета + созданные в приложении.
    var labels: [String] {
        var seen = Set<String>(), out: [String] = []
        for t in state.contacts.flatMap({ $0.tags ?? [] }) + extraLabels where !seen.contains(t) {
            seen.insert(t); out.append(t)
        }
        return out
    }

    func messages(_ convId: String) -> [Message] {
        let recent = conversation(convId)?.messages ?? []
        guard let full = fullHistory[convId] else { return recent }
        var ids = Set(full.map(\.id))
        var merged = full
        for m in recent where !ids.contains(m.id) { merged.append(m); ids.insert(m.id) }
        return merged.sorted { $0.date < $1.date }
    }

    // MARK: - запуск

    func bootstrap() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-fixture") {
            fixture = true
            stateLoaded = true
            Fixture.apply(self)
            return
        }
        #endif
        if faceOn { lock() }
        // есть сессия и копия на диске — сразу показываем кабинет, сервер проверяем в фоне
        let restored: Bool = restoreFromDisk()
        do {
            let me = try await API.get(MeResponse.self, "/api/auth/me/")
            if let old = user, old.id != me.user.id { dropCachedData() }
            user = me.user
            cacheOn = true
            // без кэша — сразу в кабинет со скелетонами вместо спиннера на весь экран
            if phase != .ready { phase = .ready }
            startLive()
            Task { await loadAccount() }
            await loadState(force: true)
        } catch let e as APIError where e.status == 401 {
            if restored { dropCachedData() }
            phase = .login
        } catch {
            // нет сети: если cookie есть — пускаем в кабинет (с копией, если она есть) и пробуем позже
            if restored || !API.cookies.isEmpty {
                cacheOn = true
                if phase != .ready { phase = .ready }
                lastError = friendly(error)
                startLive()
            } else {
                phase = .login
            }
        }
    }

    /// Поднять последнюю копию кабинета с диска. true — показали.
    private func restoreFromDisk() -> Bool {
        guard !API.cookies.isEmpty, let snap = DiskCache.loadSnapshot() else { return false }
        user = snap.user
        state = snap.state
        fullHistory = snap.history
        outreach = DiskCache.loadOutreach()
        stateLoaded = true
        phase = .ready
        return true
    }

    /// Убрать данные прошлой копии (другой аккаунт или сессия истекла).
    private func dropCachedData() {
        saveTask?.cancel(); saveTask = nil
        cacheOn = false
        DiskCache.clear()
        user = nil
        state = .empty
        fullHistory = [:]
        outreach = nil
        stateLoaded = false
        lastStateAt = nil
        historyAt = [:]
        outreachAt = nil
        etag = nil
    }

    func didLogin() async {
        do {
            let me = try await API.get(MeResponse.self, "/api/auth/me/")
            user = me.user
        } catch {}
        etag = nil
        cacheOn = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { phase = .ready }
        startLive()
        Task { await loadAccount() }
        await loadState(force: true)
    }

    func logout() async {
        stopLive()
        if !fixture { _ = try? await API.send("POST", "/api/auth/logout/") }
        resetAll()
        withAnimation { phase = .login }
    }

    /// Удалить аккаунт на сервере (POST /api/account/delete/ {"confirm": true}).
    /// Возвращает note сервера (например, «аккаунт в Поводе остаётся») или nil. Локальные данные не трогает — см. finishAccountDeletion().
    func deleteAccount() async throws -> String? {
        if fixture { accountDeleted = true; return nil }
        let r: AccountDeleteResponse = try await API.post(AccountDeleteResponse.self, "/api/account/delete/", json: ["confirm": true])
        accountDeleted = true
        stopLive()
        API.clearCookies()
        guard let note = r.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        return note
    }

    /// После удаления аккаунта: стереть cookie, кэш и данные и выйти на экран входа.
    func finishAccountDeletion() {
        guard accountDeleted else { return }
        stopLive()
        resetAll()
        accountDeleted = false
        withAnimation { phase = .login }
        show(String(localized: "Аккаунт удалён"))
    }

    /// Полный сброс: следующий аккаунт на этом телефоне не увидит ничего от прошлого.
    func resetAll() {
        epoch += 1
        saveTask?.cancel(); saveTask = nil
        stateTask?.cancel(); stateTask = nil
        outreachLoad?.cancel(); outreachLoad = nil
        cacheOn = false
        DiskCache.clear()
        stateLoaded = false
        lastStateAt = nil
        historyAt = [:]; historyLoading = []
        outreachAt = nil
        translating = []; translateFailed = [:]; translateTried = []; translateAgain = []
        transcripts = [:]
        reloadPending = false
        API.clearCookies()
        URLCache.shared.removeAllCachedResponses()
        ImageLoader.shared.clear()
        API.session.configuration.urlCache?.removeAllCachedResponses()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        let tmp = FileManager.default.temporaryDirectory
        for f in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
        let d = UserDefaults.standard
        for k in ["pinned", "hintOff", "labels", "lastEmail", "push", "quiet", "face"] { d.removeObject(forKey: k) }
        Prefs.shared.resetLocal()
        user = nil
        state = .empty
        account = nil
        outreach = nil
        outreachDenied = nil; outreachLoadError = nil; outreachHidden = []
        outreachTask?.cancel(); outreachTask = nil; outreachPendingBody = nil; outreachPendingIds = []
        fullHistory = [:]
        drafts = [:]
        dealDraft = [:]
        pinned = []
        hintOff = []
        extraLabels = []
        pushOn = false
        quietOn = true
        faceOn = false
        locked = false
        lastError = nil
        etag = nil
        chatsPath = []; todayPath = []; summaryPath = []; profilePath = []
        tab = .chats
        readTask?.cancel(); readTask = nil; pendingRead = []
        chatFolder = "all"; chatSelecting = false; chatSelected = []; chatBatchFolderSheet = false
        toastTask?.cancel()
        toast = nil
    }

    // MARK: - данные

    /// Загрузить /api/state. Одновременно идёт только один запрос: повторные вызовы ждут его,
    /// а если за это время что-то изменилось (SSE, возврат в приложение) — после него один раз догружаем.
    func loadState(force: Bool = false) async {
        if fixture || accountDeleted { return }
        if let running = stateTask {
            reloadPending = true
            await running.value
            return
        }
        let t: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.fetchState(force: force)
        }
        stateTask = t
        await t.value
        stateTask = nil
        if reloadPending {
            reloadPending = false
            await loadState()
        }
    }

    /// Обновить, только если данные старше maxAge секунд (возврат в приложение, повторное открытие экрана).
    func refreshState(maxAge: TimeInterval) async {
        if let at = lastStateAt, Date().timeIntervalSince(at) < maxAge { return }
        await loadState()
    }

    private func fetchState(force: Bool) async {
        let started: Int = epoch
        loading = true
        defer { loading = false }
        do {
            var req = URLRequest(url: API.url("/api/state/"))
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if !force, let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            let (data, resp) = try await API.session.data(for: req)
            // за время запроса вышли из аккаунта — ответ уже чужой
            guard started == epoch, !accountDeleted else { return }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 304 { markStateFresh(); return }
            if http.statusCode == 401 { await logout(); return }
            if http.statusCode >= 400 { throw APIError(status: http.statusCode, message: API.errorText(data, status: http.statusCode)) }
            let r = try API.decode(StateResponse.self, data)
            etag = http.value(forHTTPHeaderField: "Etag")
            apply(r.state)
            if let u = r.user, u != user { user = u }
            markStateFresh()
        } catch {
            // ошибка не стирает уже показанные данные: копия остаётся на экране, сверху — баннер/повтор
            guard started == epoch else { return }
            lastError = friendly(error)
        }
    }

    private func markStateFresh() {
        if lastError != nil { lastError = nil }
        lastStateAt = Date()
        if !stateLoaded { stateLoaded = true }
    }

    private func apply(_ s: AppState) {
        var s = s
        // отложенное «прочитано» (ждёт конца тоста) не должно откатываться свежим состоянием с сервера
        if !pendingRead.isEmpty {
            for i in s.conversations.indices where pendingRead.contains(s.conversations[i].id) { s.conversations[i].unread = 0 }
        }
        if !stateLoaded { stateLoaded = true }
        // тот же ответ — ничего не перерисовываем (фоновое обновление без мигания)
        guard s != state else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { state = s }
        scheduleReminderNotifications()
        scheduleSave()
    }

    // MARK: - кэш на диске

    /// Записать копию через секунду после последнего изменения (пачка обновлений — одна запись).
    private func scheduleSave() {
        guard cacheOn, !fixture else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            self?.saveCacheNow()
        }
    }

    /// Записать копию сейчас (например, при уходе приложения в фон).
    func saveCacheNow() {
        saveTask?.cancel(); saveTask = nil
        guard cacheOn, !fixture, !accountDeleted, stateLoaded else { return }
        let limit: Int = DiskCache.historyLimit
        let history: [String: [Message]] = fullHistory.mapValues { (list: [Message]) -> [Message] in Array(list.suffix(limit)) }
        let snap = CachedSnapshot(version: DiskCache.version, user: user, state: state, history: history, savedAt: Date())
        DiskCache.save(snap, to: DiskCache.snapshotURL)
    }

    private func saveOutreachCache() {
        guard cacheOn, !fixture, !accountDeleted, let list = outreach else { return }
        DiskCache.save(list, to: DiskCache.outreachURL)
    }

    func loadAccount() async {
        if fixture { return }
        account = try? await API.get(AccountInfo.self, "/api/account/")
    }

    /// Полная история чата. Копия с диска показывается сразу; с сервера обновляем не чаще раза в 60 с на чат
    /// и без параллельных дублей. Ошибка не стирает уже показанную историю.
    func loadHistory(_ convId: String) async {
        guard !fixture, !accountDeleted, (conversation(convId)?.older ?? 0) > 0 else { return }
        if let at = historyAt[convId], Date().timeIntervalSince(at) < 60 { return }
        guard !historyLoading.contains(convId) else { return }
        historyLoading.insert(convId)
        defer { historyLoading.remove(convId) }
        let started: Int = epoch
        guard let r = try? await API.get(HistoryResponse.self, "/api/history/", query: [URLQueryItem(name: "c", value: convId)]) else { return }
        guard started == epoch else { return }
        historyAt[convId] = Date()
        if fullHistory[convId] != r.messages {
            fullHistory[convId] = r.messages
            scheduleSave()
        }
    }

    /// Действие кабинета (/api/actions): сервер возвращает новое состояние целиком.
    @discardableResult
    func act(_ body: [String: Any], ok: String? = nil) async -> Bool {
        if fixture { if let ok { show(ok) }; return true }
        do {
            let r = try await API.post(ActionResponse.self, "/api/actions/", json: body)
            apply(r.state)
            etag = nil
            if let ok { show(ok) }
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    func send(_ convId: String, text: String, attachments: [Attachment] = [], round: Bool = false, replyTo: String? = nil, translate: Bool = false) async -> Bool {
        if fixture { show(String(localized: "Отправлено")); return true }
        var json: [String: Any] = ["conversationId": convId, "text": text]
        if !attachments.isEmpty {
            let items: [[String: Any]] = attachments.compactMap { $0.mediaId }.map { (id: String) -> [String: Any] in
                round ? ["mediaId": id, "round": true] : ["mediaId": id]
            }
            json["attachments"] = items
        }
        if let replyTo { json["replyTo"] = replyTo }
        if translate && translateOut && translateOn && !text.isEmpty { json["translate"] = true }
        do {
            let r = try await API.post(ActionResponse.self, "/api/messages/send/", json: json)
            apply(r.state)
            etag = nil
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    /// Перевести входящие диалога на язык менеджера (POST /api/translate — сервер переводит только непереведённое, с кэшем).
    /// Запрос уходит, только если есть входящие без перевода, которые ещё не отправляли (кэш: id сообщения + язык);
    /// один запрос на чат за раз (пришло новое во время перевода — после него переводим ещё раз);
    /// при сбое или таймауте — ещё 2 попытки, потом ошибка с «Повторить» (translateFailed).
    /// Работа идёт в отдельной задаче: уход с экрана чата перевод не обрывает.
    func translateIncoming(_ convId: String) async {
        guard !fixture, !accountDeleted, translateOn else { return }
        if translating.contains(convId) { translateAgain.insert(convId); return }
        guard !untranslatedKeys(convId).isEmpty else { return }
        translating.insert(convId)
        translateFailed[convId] = nil
        let t: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.translateLoop(convId)
        }
        await t.value
    }

    private func translateLoop(_ convId: String) async {
        let started: Int = epoch
        var again = true
        while again {
            translateAgain.remove(convId)
            await translateOnce(convId, started: started)
            again = started == epoch && translateAgain.contains(convId) && translateFailed[convId] == nil
        }
        translateAgain.remove(convId)
        if started == epoch { translating.remove(convId) }
    }

    private func translateOnce(_ convId: String, started: Int) async {
        let todo: [String] = untranslatedKeys(convId)
        guard !todo.isEmpty else { return }
        var failure: Error?
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000) }
            guard started == epoch, !accountDeleted else { return }
            do {
                let r = try await API.post(ActionResponse.self, "/api/translate/", json: ["conversationId": convId], timeout: 60)
                guard started == epoch else { return }
                apply(r.state)
                etag = nil
                translateTried.formUnion(todo)
                return
            } catch {
                failure = error
                // 4xx (кроме таймаута и «слишком часто») повтор не исправит
                if let e = error as? APIError, e.status >= 400, e.status < 500, e.status != 408, e.status != 429 { break }
            }
        }
        guard started == epoch else { return }
        if let failure { translateFailed[convId] = friendly(failure) }
    }

    /// Ключи «id сообщения|язык» входящих с текстом, у которых нет перевода и которые ещё не отправляли на перевод.
    private func untranslatedKeys(_ convId: String) -> [String] {
        let lang: String = user?.locale ?? "ru"
        var out: [String] = []
        for m in messages(convId) where !m.isOut && !m.body.isEmpty {
            let done: Bool = !(m.translation?.text ?? "").isEmpty
            let key: String = m.id + "|" + lang
            if !done && !translateTried.contains(key) { out.append(key) }
        }
        return out
    }

    /// Расшифровки, полученные в этой сессии (сервер их тоже хранит и отдаёт в сообщениях).
    var transcripts: [String: Transcript] = [:]

    /// Расшифровать голосовое или кружок. nil — ошибка (показана тостом).
    func transcribe(_ messageId: String) async -> Transcript? {
        if let t = transcripts[messageId] { return t }
        if fixture {
            #if DEBUG
            let t = Transcript(text: Fixture.transcribeText, lang: Fixture.isEnglish ? "en" : "ru")
            #else
            let t = Transcript(text: "", lang: nil)
            #endif
            transcripts[messageId] = t
            return t
        }
        do {
            let t = try await API.post(Transcript.self, "/api/media/transcribe/", json: ["messageId": messageId])
            transcripts[messageId] = t
            return t
        } catch {
            show(friendly(error), ok: false)
            return nil
        }
    }

    /// Удалить своё сообщение у клиента (Telegram, WhatsApp по QR) и из переписки.
    @discardableResult
    func unsend(_ messageId: String, convId: String) async -> Bool {
        if fixture { show(String(localized: "Удалено у всех")); return true }
        do {
            let r = try await API.post(ActionResponse.self, "/api/messages/delete/", json: ["messageId": messageId])
            if var full = fullHistory[convId] {
                full.removeAll { $0.id == messageId }
                fullHistory[convId] = full
            }
            apply(r.state)
            etag = nil
            show(String(localized: "Удалено у всех"))
            return true
        } catch {
            show(friendly(error), ok: false)
            return false
        }
    }

    /// Действия по клиенту с кнопкой «Отменить»: после выполнения сравниваем состояние до и после
    /// и собираем обратные действия (папка, метки, напоминания, оплаты/обещания).
    @discardableResult
    func perform(_ bodies: [[String: Any]], contactId: String, ok: String) async -> Bool {
        let before = state
        var done = 0
        for b in bodies {
            if await act(b) { done += 1 } else { break }
        }
        guard done > 0 else { return false }
        let undo = Store.undoActions(before: before, after: state, contactId: contactId)
        if undo.isEmpty || fixture {
            show(ok)
        } else {
            show(ok, undo: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    var all = true
                    for b in undo {
                        let ok = await self.act(b)
                        if !ok { all = false }
                    }
                    if all { self.show(String(localized: "Отменено")) }
                }
            })
        }
        return done == bodies.count
    }

    /// Обратные действия по разнице состояний одного клиента.
    static func undoActions(before: AppState, after: AppState, contactId: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        let oldDeals: [String: Deal] = Dictionary(uniqueKeysWithValues: before.deals.filter { $0.contactId == contactId }.map { ($0.id, $0) })
        for d in after.deals where d.contactId == contactId {
            if let o = oldDeals[d.id] {
                if o.status != d.status || o.amount != d.amount {
                    var b: [String: Any] = ["type": "updateDeal", "id": d.id, "status": o.status]
                    if o.amount >= 1 { b["amount"] = Int(o.amount) }
                    out.append(b)
                }
            } else {
                out.append(["type": "removeDeal", "id": d.id])
            }
        }
        let oldRems: [String: Reminder] = Dictionary(uniqueKeysWithValues: before.reminders.filter { $0.contactId == contactId }.map { ($0.id, $0) })
        let newRemIds = Set(after.reminders.map(\.id))
        for r in after.reminders where r.contactId == contactId {
            if let o = oldRems[r.id] {
                if !o.done && r.done { out.append(["type": "remind", "contactId": contactId, "at": o.at, "text": o.text]) }
            } else {
                out.append(["type": "removeReminder", "id": r.id])
            }
        }
        for o in oldRems.values where !o.done && !newRemIds.contains(o.id) {
            out.append(["type": "remind", "contactId": contactId, "at": o.at, "text": o.text])
        }
        let oc = before.contacts.first { $0.id == contactId }
        let nc = after.contacts.first { $0.id == contactId }
        if let oc, let nc {
            let ot: [String] = oc.tags ?? []
            let nt: [String] = nc.tags ?? []
            if ot != nt { out.append(["type": "updateContact", "contactId": contactId, "tags": ot]) }
            if let f = oc.folderId, f != nc.folderId { out.append(["type": "move", "contactId": contactId, "folderId": f]) }
        }
        return out
    }

    // MARK: - выбор чатов и групповые действия

    /// «Без папки» на сервере нет: у клиента всегда одна папка. Базовая — «Новые» (key new, её нельзя удалить),
    /// поэтому «убрать из папки» = вернуть в неё.
    var baseFolder: Folder? { folder(key: "new") ?? state.folders.first }

    func canRemoveFromFolder(_ contactId: String) -> Bool {
        guard let base = baseFolder, let c = contact(contactId) else { return false }
        return c.folderId != base.id
    }

    func startSelecting(_ first: String? = nil) {
        withAnimation(.spring(response: 0.3)) {
            chatSelecting = true
            if let first { chatSelected = [first] } else { chatSelected = [] }
        }
    }

    func stopSelecting() {
        withAnimation(.spring(response: 0.3)) {
            chatSelecting = false
            chatSelected = []
        }
    }

    func toggleSelected(_ convId: String) {
        if chatSelected.contains(convId) { chatSelected.remove(convId) } else { chatSelected.insert(convId) }
    }

    /// Клиенты выбранных чатов (у клиента может быть несколько чатов — без повторов).
    func contactIds(of convIds: Set<String>) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for c in state.conversations where convIds.contains(c.id) && !seen.contains(c.contactId) {
            seen.insert(c.contactId); out.append(c.contactId)
        }
        return out
    }

    /// Убрать одного клиента из папки (вернуть в базовую) с «Отменить».
    func removeFromFolder(_ contactId: String) async {
        guard let base = baseFolder, let c = contact(contactId), c.folderId != base.id else { return }
        let from: String = folder(c.folderId)?.name ?? String(localized: "папки")
        await perform([["type": "move", "contactId": contactId, "folderId": base.id]], contactId: contactId, ok: String(localized: "Убран из «\(from)» — теперь в «\(base.name)»"))
    }

    /// Переложить нескольких клиентов в папку; «Отменить» возвращает каждого в его прежнюю папку.
    @discardableResult
    func moveMany(_ contactIds: [String], to folderId: String, ok: String? = nil) async -> Bool {
        let before: [String: String] = Dictionary(uniqueKeysWithValues: state.contacts.compactMap { (c: Contact) -> (String, String)? in
            guard let f = c.folderId else { return nil }
            return (c.id, f)
        })
        let todo: [String] = contactIds.filter { contact($0)?.folderId != folderId }
        guard !todo.isEmpty else { show(String(localized: "Они уже в этой папке")); return false }
        var done: [String] = []
        for cid in todo {
            if await act(["type": "move", "contactId": cid, "folderId": folderId]) { done.append(cid) } else { break }
        }
        guard !done.isEmpty else { return false }
        var back: [[String: Any]] = []
        for cid in done {
            if let f = before[cid] { back.append(["type": "move", "contactId": cid, "folderId": f]) }
        }
        let fname: String = folder(folderId)?.name ?? String(localized: "папку")
        let dn: Int = done.count
        let text: String = ok ?? String(localized: "В «\(fname)»: \(dn) клиентов")
        if fixture || back.isEmpty { show(text); return true }
        show(text, undo: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                var all = true
                for b in back {
                    let r = await self.act(b)
                    if !r { all = false }
                }
                if all { self.show(String(localized: "Отменено")) }
            }
        })
        return done.count == todo.count
    }

    /// Убрать нескольких клиентов из их папок (в базовую).
    func removeManyFromFolders(_ contactIds: [String]) async {
        guard let base = baseFolder else { return }
        let todo: [String] = contactIds.filter { contact($0)?.folderId != base.id }
        guard !todo.isEmpty else { show(String(localized: "Они и так без папки — в «\(base.name)»")); return }
        await moveMany(todo, to: base.id, ok: String(localized: "Убрано из папок: \(todo.count) клиентов — теперь в «\(base.name)»"))
    }

    /// Прочитать несколько чатов. Сервер не умеет «непрочитано», поэтому отметка уходит после тоста (9 с) —
    /// до этого «Отменить» просто возвращает счётчики.
    func markReadMany(_ convIds: [String]) {
        commitPendingRead()
        var old: [String: Int] = [:]
        for id in convIds {
            if let i = state.conversations.firstIndex(where: { $0.id == id }), state.conversations[i].unread > 0 {
                old[id] = state.conversations[i].unread
            }
        }
        guard !old.isEmpty else { show(String(localized: "Эти чаты уже прочитаны")); return }
        withAnimation(.spring(response: 0.3)) {
            for (id, _) in old {
                if let i = state.conversations.firstIndex(where: { $0.id == id }) { state.conversations[i].unread = 0 }
            }
        }
        let ids = Set(old.keys)
        pendingRead = ids
        readTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_300_000_000)
            if Task.isCancelled { return }
            self?.commitPendingRead()
        }
        show(String(localized: "Прочитано: \(old.count) чатов"), undo: { [weak self] in
            guard let self else { return }
            self.readTask?.cancel()
            self.readTask = nil
            self.pendingRead.subtract(ids)
            withAnimation(.spring(response: 0.3)) {
                for (id, n) in old {
                    if let i = self.state.conversations.firstIndex(where: { $0.id == id }) { self.state.conversations[i].unread = n }
                }
            }
            self.show(String(localized: "Отменено"))
        })
    }

    /// Отправить отложенные «прочитано» на сервер.
    func commitPendingRead() {
        readTask?.cancel()
        readTask = nil
        let ids = pendingRead
        pendingRead = []
        guard !ids.isEmpty, !fixture else { return }
        Task { [weak self] in
            for id in ids { await self?.act(["type": "read", "conversationId": id]) }
        }
    }

    /// Закрепить выбранные (если все уже закреплены — открепить) с «Отменить».
    func pinMany(_ convIds: [String]) {
        guard !convIds.isEmpty else { return }
        let old = pinned
        let allOn: Bool = convIds.allSatisfy { pinned.contains($0) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if allOn { pinned.subtract(convIds) } else { pinned.formUnion(convIds) }
        }
        UserDefaults.standard.set(Array(pinned), forKey: "pinned")
        let n: Int = convIds.count
        show(allOn ? String(localized: "Откреплено: \(n) чатов") : String(localized: "Закреплено сверху: \(n) чатов"), undo: { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.pinned = old }
            UserDefaults.standard.set(Array(old), forKey: "pinned")
        })
    }

    func markRead(_ convId: String) {
        guard let c = conversation(convId), c.unread > 0 else { return }
        if let i = state.conversations.firstIndex(where: { $0.id == convId }) { state.conversations[i].unread = 0 }
        Task { await act(["type": "read", "conversationId": convId]) }
    }

    /// quiet — фоновая подгрузка (из Профиля): ошибки не показываем тостом
    /// maxAge > 0 — не грузить заново, если список свежее стольких секунд (повторное открытие экрана).
    /// Параллельные вызовы ждут уже идущий запрос; ошибка при уже показанном списке его не стирает.
    func loadOutreach(quiet: Bool = false, maxAge: TimeInterval = 0) async {
        if fixture || accountDeleted { return }
        if maxAge > 0, outreach != nil, let at = outreachAt, Date().timeIntervalSince(at) < maxAge { return }
        if let running = outreachLoad {
            await running.value
            return
        }
        let t: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.fetchOutreach(quiet: quiet)
        }
        outreachLoad = t
        await t.value
        outreachLoad = nil
    }

    private func fetchOutreach(quiet: Bool) async {
        let started: Int = epoch
        do {
            let list: OutreachList = try await API.get(OutreachList.self, "/api/outreach/")
            guard started == epoch else { return }
            outreach = list
            outreachAt = Date()
            outreachDenied = nil
            outreachLoadError = nil
            saveOutreachCache()
        } catch {
            guard started == epoch else { return }
            if outreachDeny(error) { return }
            if outreach == nil { outreachLoadError = friendly(error) }
            if !quiet { show(friendly(error), ok: false) }
        }
    }

    /// Действие рассылки (POST /api/outreach): сервер отвечает свежим списком. nil — не получилось (тост уже показан).
    @discardableResult
    func outreachAction(_ body: [String: Any], ok: String? = nil) async -> OutreachList? {
        if fixture {
            if let ok { show(ok) }
            return outreach
        }
        do {
            let r = try await API.post(OutreachList.self, "/api/outreach/", json: body)
            outreach = r
            outreachAt = Date()
            saveOutreachCache()
            outreachDenied = nil
            if let ok { show(ok) }
            return r
        } catch {
            if outreachDeny(error) { return nil }
            show(friendly(error), ok: false)
            return nil
        }
    }

    /// 402/403 → экран «нужна оплата» / «доступно владельцу кабинета» вместо тоста.
    private func outreachDeny(_ error: Error) -> Bool {
        guard let e = error as? APIError, e.status == 402 || e.status == 403 else { return false }
        outreachDenied = OutreachDenied(needPay: e.status == 402, text: e.message)
        return true
    }

    /// Убрать фирмы из рассылки с «Отменить» 9 с: сразу скрываем на телефоне, запрос уходит после тоста.
    func outreachRemoveLater(ids: Set<String>, body: [String: Any], text: String) {
        commitOutreachRemoval()
        guard !ids.isEmpty else { return }
        withAnimation(.spring(response: 0.3)) { outreachHidden.formUnion(ids) }
        outreachPendingIds = ids
        outreachPendingBody = body
        outreachTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_300_000_000)
            if Task.isCancelled { return }
            self?.commitOutreachRemoval()
        }
        show(text, undo: { [weak self] in
            guard let self else { return }
            self.outreachTask?.cancel()
            self.outreachTask = nil
            self.outreachPendingBody = nil
            self.outreachPendingIds = []
            withAnimation(.spring(response: 0.3)) { self.outreachHidden.subtract(ids) }
            self.show(String(localized: "Отменено"))
        })
    }

    /// Отправить отложенное удаление/очистку на сервер (по таймеру или перед следующим таким действием).
    func commitOutreachRemoval() {
        guard let body = outreachPendingBody else { return }
        let ids = outreachPendingIds
        outreachPendingBody = nil
        outreachPendingIds = []
        outreachTask?.cancel()
        outreachTask = nil
        if fixture { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await self.outreachAction(body)
            // удалось — фирм уже нет в ответе; не удалось — возвращаем их на экран (ошибка показана тостом)
            self.outreachHidden.subtract(ids)
        }
    }

    func loadOutreachSettings() async -> OutreachSettings? {
        if fixture { return outreach?.settings ?? OutreachSettings.defaults }
        do {
            let r = try await API.get(OutreachSettingsReply.self, "/api/outreach/settings/")
            return r.settings
        } catch {
            if !outreachDeny(error) { show(friendly(error), ok: false) }
            return nil
        }
    }

    func saveOutreachSettings(_ st: OutreachSettings) async -> Bool {
        if fixture {
            outreach?.settings = st
            show(String(localized: "Настройки рассылки сохранены"))
            return true
        }
        let body: [String: Any] = ["dailyLimit": st.dailyLimit, "gapMin": st.gapMin, "startHour": st.startHour, "endHour": st.endHour, "days": st.days]
        do {
            let r = try await API.post(OutreachSettingsReply.self, "/api/outreach/settings/", json: body)
            outreach?.settings = r.settings
            show(String(localized: "Настройки рассылки сохранены"))
            await loadOutreach(quiet: true)
            return true
        } catch {
            if !outreachDeny(error) { show(friendly(error), ok: false) }
            return false
        }
    }

    // MARK: - живые обновления

    func startLive() {
        guard !fixture, !accountDeleted else { return }
        stopLive()
        eventsTask = Task { [weak self] in await self?.eventsLoop() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.loadState()
            }
        }
    }

    func stopLive() {
        eventsTask?.cancel(); eventsTask = nil
        pollTask?.cancel(); pollTask = nil
    }

    private func eventsLoop() async {
        while !Task.isCancelled {
            do {
                var req = URLRequest(url: API.url("/api/events/"))
                req.timeoutInterval = 600
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, resp) = try await API.session.bytes(for: req)
                if (resp as? HTTPURLResponse)?.statusCode == 200 {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix("data:") && line.contains("changed") { await loadState() }
                    }
                }
            } catch {}
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: - локальные настройки

    func setWall(_ w: Wall) {
        withAnimation(.easeInOut(duration: 0.35)) { wall = w }
        UserDefaults.standard.set(w.rawValue, forKey: "wall")
    }

    func togglePin(_ convId: String) {
        if pinned.contains(convId) { pinned.remove(convId) } else { pinned.insert(convId) }
        UserDefaults.standard.set(Array(pinned), forKey: "pinned")
    }

    /// Закрепить/открепить с «Отменить».
    func togglePinUndoable(_ convId: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { togglePin(convId) }
        let on = pinned.contains(convId)
        show(on ? String(localized: "Закреплён сверху") : String(localized: "Откреплён"), undo: { [weak self] in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self?.togglePin(convId) }
        })
    }

    func hideHint(_ convId: String, lastMessageId: String) {
        hintOff.insert(convId + "|" + lastMessageId)
        UserDefaults.standard.set(Array(hintOff.suffix(300)), forKey: "hintOff")
    }

    func addLabel(_ name: String) {
        guard !labels.contains(name) else { return }
        extraLabels.append(name)
        UserDefaults.standard.set(extraLabels, forKey: "labels")
    }

    func removeExtraLabel(_ name: String) {
        extraLabels.removeAll { $0 == name }
        UserDefaults.standard.set(extraLabels, forKey: "labels")
    }

    func setPush(_ on: Bool) {
        pushOn = on
        UserDefaults.standard.set(on, forKey: "push")
        if on {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                Task { @MainActor in
                    if !granted {
                        self.pushOn = false
                        UserDefaults.standard.set(false, forKey: "push")
                        self.show(String(localized: "Уведомления выключены в настройках iPhone"), ok: false)
                    } else {
                        self.scheduleReminderNotifications()
                    }
                }
            }
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
    }

    func setQuiet(_ on: Bool) {
        quietOn = on
        UserDefaults.standard.set(on, forKey: "quiet")
        scheduleReminderNotifications()
    }

    func setFace(_ on: Bool) {
        faceOn = on
        UserDefaults.standard.set(on, forKey: "face")
    }

    /// Экран блокировки: вместе с ним убираем тост (кнопку «Отменить» нельзя нажать из-под замка).
    func lock() {
        locked = true
        toastTask?.cancel()
        toast = nil
    }

    /// Включить/выключить Face ID — только после успешной проверки владельца телефона.
    /// Раньше выключить было нельзя: системное окно Face ID переводит сцену в .inactive, обработчик ставил замок,
    /// экран блокировки запускал вторую проверку и срывал первую — настройка оставалась включённой.
    func requestFace(_ on: Bool) {
        guard !authenticating else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            show(String(localized: "На этом телефоне нет Face ID или код-пароля"), ok: false)
            return
        }
        authenticating = true
        wentBackground = false
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: on ? String(localized: "Включить вход по Face ID") : String(localized: "Выключить вход по Face ID")) { ok, _ in
            Task { @MainActor in
                if ok {
                    self.setFace(on)
                    // снимаем замок, только если он поставлен не уходом в фон
                    if !self.wentBackground { self.locked = false }
                    self.show(on ? String(localized: "Вход по Face ID включён") : String(localized: "Вход по Face ID выключен"))
                } else {
                    self.show(String(localized: "Не подтверждено — настройка не изменилась"), ok: false)
                }
                // сцена возвращается в .active чуть позже колбэка — снимаем флаг с запасом
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.authenticating = false
            }
        }
    }

    /// Напоминания кабинета → локальные уведомления (тихие часы 23:00–08:00 переносят на 08:00).
    func scheduleReminderNotifications() {
        guard pushOn, !fixture else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let cal = Calendar.current
        let upcoming = openReminders.filter { $0.date > Date() }.sorted { $0.date < $1.date }.prefix(60)
        for r in upcoming {
            var at = r.date
            if quietOn {
                let h = cal.component(.hour, from: at)
                if h >= 23 || h < 8 {
                    var day = cal.startOfDay(for: at)
                    if h >= 23 { day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
                    at = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? at
                }
            }
            let content = UNMutableNotificationContent()
            content.title = contact(r.contactId)?.name ?? String(localized: "Напоминание")
            content.body = r.text.isEmpty ? String(localized: "Написать клиенту") : r.text
            content.sound = .default
            content.userInfo = ["contactId": r.contactId]
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            let req = UNNotificationRequest(identifier: "rem-" + r.id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(req)
        }
    }

    // MARK: - тосты

    func show(_ text: String, ok: Bool = true, undo: (() -> Void)? = nil) {
        // под экраном блокировки тост с действием не показываем
        let action: (() -> Void)? = locked ? nil : undo
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = Toast(text: text, ok: ok, undo: action) }
        if !ok { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        toastTask?.cancel()
        let wait: UInt64 = action == nil ? 2_600_000_000 : 9_000_000_000  // «Отменить» держится 9 с
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: wait)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func open(_ route: Route) {
        switch tab {
        case .chats: chatsPath.append(route)
        case .today: todayPath.append(route)
        case .summary: summaryPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func pop() {
        switch tab {
        case .chats: if !chatsPath.isEmpty { chatsPath.removeLast() }
        case .today: if !todayPath.isEmpty { todayPath.removeLast() }
        case .summary: if !summaryPath.isEmpty { summaryPath.removeLast() }
        case .profile: if !profilePath.isEmpty { profilePath.removeLast() }
        }
    }

    var currentPathEmpty: Bool {
        switch tab {
        case .chats: return chatsPath.isEmpty
        case .today: return todayPath.isEmpty
        case .summary: return summaryPath.isEmpty
        case .profile: return profilePath.isEmpty
        }
    }
}
