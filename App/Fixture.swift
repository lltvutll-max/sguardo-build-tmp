#if DEBUG
import Foundation

/// Только для снимков симулятора в CI (`-fixture`): выдуманный кабинет без сети. В сборку для TestFlight не попадает.
enum Fixture {
    @MainActor
    static func apply(_ s: Store) {
        let now = Date()
        func ago(_ min: Double) -> String { isoString(now.addingTimeInterval(-min * 60)) }
        let folders: [Folder] = [
            Folder(id: "f_new", key: "new", name: "Новые", color: "#A9D8FF"),
            Folder(id: "f_talking", key: "talking", name: "В диалоге", color: "#DCC6FF"),
            Folder(id: "f_thinking", key: "thinking", name: "Думает", color: "#FFD59E"),
            Folder(id: "f_later", key: "later", name: "Оплатит позже", color: "#FFB8B0"),
            Folder(id: "f_paid", key: "paid", name: "Оплатил", color: "#A8EDCB"),
            Folder(id: "f_repeat", key: "repeat", name: "Повторный клиент", color: "#9EE6E0"),
            Folder(id: "f_rejected", key: "rejected", name: "Отказ", color: "#B9B2B5"),
        ]
        struct P { let name: String; let handle: String; let net: String; let folder: String; let tags: [String]; let phone: String?; let msgs: [(String, String, Double)]; let unread: Int }
        let people: [P] = [
            P(name: "Анна Белова", handle: "annabel", net: "telegram", folder: "f_new", tags: ["VIP"], phone: nil,
              msgs: [("in", "Здравствуйте! Сколько стоит курс?", 50)], unread: 1),
            P(name: "+7 988 473-73-30", handle: "+79884737330", net: "whatsapp", folder: "f_talking", tags: [], phone: "+79884737330",
              msgs: [("in", "Добрый день, можно записаться на четверг?", 300), ("out", "Здравствуйте! Да, в 15:00 свободно", 290), ("in", "Отлично, оплачу завтра", 280)], unread: 0),
            P(name: "On Gayrimenkul", handle: "+905301112233", net: "whatsapp", folder: "f_talking", tags: ["Рассылка TR"], phone: "+905301112233",
              msgs: [("out", "Merhaba, On Gayrimenkul! 👋 Google'da firmanızı gördük", 1500)], unread: 0),
            P(name: "Мария Орлова", handle: "m_orlova", net: "telegram", folder: "f_thinking", tags: ["Сайт"], phone: nil,
              msgs: [("out", "Отправила программу и цены", 3000), ("in", "Спасибо, я подумаю до пятницы", 2900)], unread: 0),
            P(name: "Lena Ekicioğlu", handle: "+905551234567", net: "whatsapp", folder: "f_talking", tags: ["Рассылка TR"], phone: "+905551234567",
              msgs: [("out", "Merhaba! Sitenizi inceledik", 4000), ("in", "Lena İnşaat ile iletişime geçtiğiniz için teşekkür ederiz", 3990)], unread: 1),
            P(name: "Павел Смирнов", handle: "psmirnov", net: "telegram", folder: "f_paid", tags: ["VIP"], phone: "+79161234567",
              msgs: [("in", "Оплатил, проверьте", 6000), ("out", "Спасибо за оплату! Всё получили.", 5990)], unread: 0),
            P(name: "Emir Yapı", handle: "+905339998877", net: "whatsapp", folder: "f_talking", tags: [], phone: "+905339998877",
              msgs: [("out", "Merhaba, Emir Yapı! 👋", 9000)], unread: 0),
            P(name: "Ольга Тихонова", handle: "olgat", net: "telegram", folder: "f_later", tags: [], phone: nil,
              msgs: [("in", "Скиньте реквизиты, переведу в понедельник", 12000), ("out", "Отправляю реквизиты для оплаты", 11990)], unread: 0),
        ]
        var contacts: [Contact] = [], convs: [Conversation] = [], events: [AppEvent] = []
        for (i, p) in people.enumerated() {
            let cid = "c\(i)", vid = "v\(i)"
            let firstMin = (p.msgs.first?.2 ?? 100) + 60 * 24 * Double(i)
            contacts.append(Contact(id: cid, name: p.name, handle: p.handle, hue: Double((i * 47) % 360), source: p.net, networks: [p.net],
                                    folderId: p.folder, assignee: "", note: i == 3 ? "Хочет групповые занятия" : "", phone: p.phone, email: i == 5 ? "pavel@example.com" : nil,
                                    tags: p.tags, lang: (i == 0 || i == 4) ? "tr" : "ru", avatar: nil, firstContactAt: ago(firstMin)))
            var msgs: [Message] = p.msgs.enumerated().map { j, m in
                Message(id: "m\(i)_\(j)", dir: m.0, text: m.1, at: ago(m.2), author: nil, attachments: nil, translation: nil)
            }
            if i == 0 { msgs = mediaChat(ago) }
            convs.append(Conversation(id: vid, contactId: cid, network: p.net, messages: msgs, older: 0, unread: p.unread, channelId: "ch_\(p.net)"))
            events.append(AppEvent(id: "e\(i)", type: "lead_created", contactId: cid, at: ago(firstMin), meta: nil))
            for (j, m) in p.msgs.enumerated() {
                events.append(AppEvent(id: "e\(i)_\(j)", type: m.0 == "in" ? "message_in" : "message_out", contactId: cid, at: ago(m.2), meta: nil))
            }
        }
        let tomorrow10 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now.addingTimeInterval(86400)) ?? now
        s.state = AppState(
            workspace: WorkspaceInfo(currency: "RUB", translate: true),
            channels: [
                Channel(id: "ch_whatsapp", type: "whatsapp", mode: "qr", name: "WhatsApp +905077748057", status: "connected", error: nil),
                Channel(id: "ch_threads", type: "threads", mode: nil, name: "@disifydev", status: "connected", error: nil),
                Channel(id: "ch_telegram", type: "telegram", mode: "mtproto", name: "@disifydev", status: "connected", error: nil),
            ],
            folders: folders, contacts: contacts, conversations: convs,
            deals: [Deal(id: "d1", contactId: "c5", productId: nil, amount: 5000, status: "paid", date: ago(5990), dueAt: nil)],
            reminders: [
                Reminder(id: "r1", contactId: "c1", at: isoString(tomorrow10), text: "Проверить оплату", done: false),
                Reminder(id: "r2", contactId: "c7", at: ago(120), text: "Напомнить про реквизиты", done: false),
            ],
            events: events,
            templates: [
                Template(id: "t1", title: "Привет", text: "Здравствуйте! Спасибо, что написали. Подскажите, что вас интересует?"),
                Template(id: "t2", title: "Реквизиты", text: "Отправляю реквизиты для оплаты. После оплаты пришлите, пожалуйста, скрин."),
            ])
        s.user = User(id: "u1", workspaceId: "ws1", email: "hi@disify.dev", name: "Владелец", role: "owner", locale: "ru", tz: "Europe/Moscow", features: Features(outreach: true))
        s.account = AccountInfo(name: "Владелец", email: "hi@disify.dev", role: "owner", plan: "business", status: "active", workspaceName: "Мой кабинет", paidUntil: nil, trialEndsAt: nil)
        s.outreach = OutreachList(targets: [
            OutreachTarget(id: "o1", name: "Vamos Bodrum", city: "Bodrum", niche: "Ресторан", phone: "+905321112233", site: nil, problem: "Нет сайта",
                           rating: 4.6, reviews: 212, waStatus: "yes", message: "Merhaba! Google'da firmanızı gördük…", status: "new", sentAt: nil, repliedAt: nil, contactId: nil, error: nil,
                           source: "tr-setup", country: "TR"),
            OutreachTarget(id: "o3", name: "Студия «Лофт»", city: "Казань", niche: "Дизайн интерьера", phone: "+79172223344", site: "loft-kzn.ru", problem: "Сайт не открывается на телефоне",
                           rating: 4.8, reviews: 64, waStatus: "unknown", message: "Здравствуйте! Увидели вашу студию на картах: сайт не открывается с телефона. Можем показать, как это исправить за неделю?",
                           status: "new", sentAt: nil, repliedAt: nil, contactId: nil, error: nil, source: "povod", country: "RU"),
            OutreachTarget(id: "o4", name: "Кофейня «Зерно»", city: "Самара", niche: "Кофейня", phone: "+79271112233", site: nil, problem: "Нет сайта",
                           rating: 4.7, reviews: 128, waStatus: "yes", message: "Здравствуйте!…", status: "replied", sentAt: ago(300), repliedAt: ago(240), contactId: nil, error: nil,
                           source: "povod", country: "RU"),
            OutreachTarget(id: "o2", name: "Cess Mimarlık", city: "İzmir", niche: "Архитектура", phone: "+905441112233", site: "cess.com.tr", problem: "Сайт не открывается",
                           rating: 4.9, reviews: 31, waStatus: "yes", message: "Merhaba…", status: "sent", sentAt: ago(60), repliedAt: nil, contactId: nil, error: nil,
                           source: "tr-setup", country: "TR"),
            OutreachTarget(id: "o5", name: "Ремонт Про", city: "Тула", niche: "Ремонт квартир", phone: "+74872334455", site: nil, problem: "Только соцсети",
                           rating: 4.2, reviews: 18, waStatus: "no", message: "Здравствуйте!…", status: "skip", sentAt: nil, repliedAt: nil, contactId: nil, error: nil,
                           source: "povod", country: "RU"),
            OutreachTarget(id: "o6", name: "Bodrum Emlak", city: "Bodrum", niche: "Недвижимость", phone: "+902523334455", site: nil, problem: "Нет сайта",
                           rating: 4.4, reviews: 47, waStatus: "no", message: "Merhaba…", status: "new", sentAt: nil, repliedAt: nil, contactId: nil, error: nil,
                           source: "tr-setup", country: "TR"),
        ], quota: OutreachQuota(ok: true, reason: nil, sentToday: 6, limit: 20), channel: "WhatsApp +905077748057",
           auto: OutreachAuto(on: true, stopped: nil, next: isoString(now.addingTimeInterval(900)), left: 2), error: nil,
           needWhatsApp: false,
           settings: OutreachSettings(dailyLimit: 20, gapMin: 5, startHour: 10, endHour: 19, days: [1, 2, 3, 4, 5], tz: "Europe/Moscow"))
        s.phase = ProcessInfo.processInfo.arguments.contains("-login") ? .login : .ready
        if ProcessInfo.processInfo.arguments.contains("-toast") {
            s.toast = Toast(text: "Метка «VIP» снята", ok: true, undo: {})
        }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-wall"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let w = Wall(rawValue: ProcessInfo.processInfo.arguments[i + 1]) { s.wall = w }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen"), i + 1 < ProcessInfo.processInfo.arguments.count {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "today": s.tab = .today
            case "summary": s.tab = .summary
            case "profile", "profile-delete": s.tab = .profile   // profile-delete: лист удаления открывает ProfileView
            case "chat": s.chatsPath = [.chat("v1")]
            case "chat-tr", "chat-tr-sheet": s.chatsPath = [.chat("v4")]
            case "chats-folder": s.chatFolder = "f_talking"
            case "chats-select":
                s.chatSelecting = true
                s.chatSelected = ["v1", "v4", "v6"]
            case "chats-folder-sheet":
                s.chatSelecting = true
                s.chatSelected = ["v1", "v4"]
                s.chatBatchFolderSheet = true
            case "chat-tg", "chat-reply", "chat-voice", "chat-preview", "viewer", "note", "note-rec", "note-lock", "chat-voice-rec",
                 "chat-down", "chat-menu", "chat-select", "chat-failed", "chat-forward":
                // у v0 в списке одно непрочитанное — для этих снимков чат прочитан, иначе откроется на разделителе «Непрочитанные»
                if let k = s.state.conversations.firstIndex(where: { $0.id == "v0" }) { s.state.conversations[k].unread = 0 }
                s.chatsPath = [.chat("v0")]
            case "chat-unread":
                // три последних входящих не прочитаны: чат откроется на разделителе «Непрочитанные сообщения»
                if let k = s.state.conversations.firstIndex(where: { $0.id == "v0" }) { s.state.conversations[k].unread = 3 }
                s.chatsPath = [.chat("v0")]
            case "client": s.chatsPath = [.client("c5")]
            case "chats-empty": s.chatFolder = "f_repeat"   // папка без чатов — пустой экран с подсказкой
            case "folders": s.tab = .profile; s.profilePath = [.folders]
            case "outreach": s.tab = .profile; s.profilePath = [.outreach]
            case "outreach-all", "outreach-settings", "outreach-clear":
                // 60 весь список (оба источника), 61 настройки, 62 подтверждение «Очистить очередь»
                s.outreachFixtureScreen = String(ProcessInfo.processInfo.arguments[i + 1].dropFirst("outreach-".count))
                s.tab = .profile; s.profilePath = [.outreach]
            case "outreach-wa":
                // 63 плашка «подключите WhatsApp»
                s.outreach?.needWhatsApp = true
                s.tab = .profile; s.profilePath = [.outreach]
            case "partners": s.tab = .profile; s.profilePath = [.partners]
            case "code": s.phase = .login
            default: break
            }
        }
    }

    /// Волна «с сервера»: 100 точек 0…31, похожа на речь (фразы и паузы).
    static func serverWave() -> [Double] {
        var out: [Double] = []
        for k in 0..<100 {
            let phrase: Double = abs(sin(Double(k) / 7.0))
            let jitter: Double = Double((k * 37) % 11) / 10.0
            let pause: Double = (k % 23 < 3) ? 0.15 : 1.0
            out.append((4.0 + 27.0 * phrase * (0.45 + 0.55 * jitter) * pause).rounded())
        }
        return out
    }

    /// Переписка с фото, голосовым, ответом и кружком — для снимков чата и просмотрщика.
    static func mediaChat(_ ago: (Double) -> String) -> [Message] {
        let photo = Attachment(kind: "image", name: "Фото", url: "fixture:photo-1", mediaId: nil, mime: "image/jpeg", round: nil)
        let photo2 = Attachment(kind: "image", name: "Фото", url: "fixture:photo-2", mediaId: nil, mime: "image/jpeg", round: nil)
        // волна и длительность пришли с сервера (как у Telegram): файл ради волны не качаем
        let voice = Attachment(kind: "audio", name: "Голосовое", url: "fixture:voice", mediaId: nil, mime: "audio/ogg", round: nil,
                               waveform: serverWave(), duration: 17)
        let note = Attachment(kind: "video", name: "Кружок", url: "fixture:note", mediaId: nil, mime: "video/mp4", round: true)
        var out: [Message] = []
        out.append(Message(id: "m0_0", dir: "in", text: "Здравствуйте! Сколько стоит курс?", at: ago(95), author: nil, attachments: nil, translation: nil))
        var a = Message(id: "m0_1", dir: "out", text: "Вот программа и расписание", at: ago(90), author: "Вы", attachments: [photo], translation: nil)
        a.externalId = "100:11"
        out.append(a)
        out.append(Message(id: "m0_2", dir: "in", text: "", at: ago(70), author: nil, attachments: [voice], translation: nil))
        out.append(Message(id: "m0_3", dir: "in", text: "А вот так у меня сейчас", at: ago(60), author: nil, attachments: [photo2], translation: nil))
        var r = Message(id: "m0_4", dir: "out", text: "Отлично, с таким уровнем подойдёт продвинутая группа", at: ago(55), author: "Вы", attachments: nil, translation: nil)
        r.replyTo = ReplyRef(id: "m0_3", text: "А вот так у меня сейчас", dir: "in")
        r.externalId = "100:14"
        out.append(r)
        var n = Message(id: "m0_5", dir: "out", text: "", at: ago(52), author: "Вы", attachments: [note], translation: nil)
        n.externalId = "100:15"
        out.append(n)
        // кружок клиента (слева), расшифровка уже пришла с сервера
        let note2 = Attachment(kind: "video", name: "Кружок", url: "fixture:note2", mediaId: nil, mime: "video/mp4", round: true)
        var n2 = Message(id: "m0_5b", dir: "in", text: "", at: ago(51), author: nil, attachments: [note2], translation: nil)
        n2.transcript = Transcript(text: "Вот так я сейчас играю — посмотрите, пожалуйста, руку.", lang: "ru")
        out.append(n2)
        out.append(Message(id: "m0_6", dir: "in", text: "Сколько стоит курс целиком?", at: ago(50), author: nil, attachments: nil, translation: nil))
        // голосовое, расшифровка которого уже пришла с сервера: по «→A» показывается без запроса
        let voice2 = Attachment(kind: "audio", name: "Голосовое", url: "fixture:voice2", mediaId: nil, mime: "audio/ogg", round: nil)
        var v2 = Message(id: "m0_7", dir: "in", text: "", at: ago(48), author: nil, attachments: [voice2], translation: nil)
        v2.transcript = Transcript(text: "И ещё вопрос: в группе сколько человек? Хочу, чтобы было не больше восьми.", lang: "ru")
        out.append(v2)
        return out
    }
}
#endif
