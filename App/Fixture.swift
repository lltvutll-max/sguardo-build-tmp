#if DEBUG
import Foundation

/// Только для снимков симулятора в CI (`-fixture`): выдуманный кабинет без сети. В сборку для TestFlight не попадает.
/// Данные двуязычные: при английском языке приложения — английские клиенты и сообщения (снимки App Store en), иначе русские.
enum Fixture {
    /// Язык снимка: английский, если система или выбранная локализация приложения — en (`-AppleLanguages "(en)"`).
    static var isEnglish: Bool {
        let first: String = Locale.preferredLanguages.first ?? ""
        let loc: String = Bundle.main.preferredLocalizations.first ?? ""
        return first.hasPrefix("en") || loc == "en"
    }

    /// Клиент для фикстуры: имя, канал, папка, метки, сообщения (направление, текст, минут назад).
    struct Person {
        let name: String
        let handle: String
        let net: String
        let folder: String
        let tags: [String]
        let phone: String?
        let msgs: [(String, String, Double)]
        let unread: Int
    }

    static func folders(_ en: Bool) -> [Folder] {
        if en {
            return [
                Folder(id: "f_new", key: "new", name: "New", color: "#A9D8FF"),
                Folder(id: "f_talking", key: "talking", name: "In talks", color: "#DCC6FF"),
                Folder(id: "f_thinking", key: "thinking", name: "Thinking", color: "#FFD59E"),
                Folder(id: "f_later", key: "later", name: "Pay later", color: "#FFB8B0"),
                Folder(id: "f_paid", key: "paid", name: "Paid", color: "#A8EDCB"),
                Folder(id: "f_repeat", key: "repeat", name: "Repeat client", color: "#9EE6E0"),
                Folder(id: "f_rejected", key: "rejected", name: "Declined", color: "#B9B2B5"),
            ]
        }
        return [
            Folder(id: "f_new", key: "new", name: "Новые", color: "#A9D8FF"),
            Folder(id: "f_talking", key: "talking", name: "В диалоге", color: "#DCC6FF"),
            Folder(id: "f_thinking", key: "thinking", name: "Думает", color: "#FFD59E"),
            Folder(id: "f_later", key: "later", name: "Оплатит позже", color: "#FFB8B0"),
            Folder(id: "f_paid", key: "paid", name: "Оплатил", color: "#A8EDCB"),
            Folder(id: "f_repeat", key: "repeat", name: "Повторный клиент", color: "#9EE6E0"),
            Folder(id: "f_rejected", key: "rejected", name: "Отказ", color: "#B9B2B5"),
        ]
    }

    /// Турецкая переписка (чат v4): входящие с переводом, исходящие с тем, что написал владелец.
    static let trMessages: [(String, String, Double)] = [
        ("out", "Merhaba! Sitenizi inceledik, mobil sürüm yavaş açılıyor.", 4000),
        ("in", "Merhaba, evet biz de fark ettik. Ne kadar sürer?", 3990),
        ("out", "Yaklaşık bir hafta. Yarın size teklif gönderebilirim.", 3980),
        ("in", "Harika, teklifinizi bekliyorum!", 3970),
    ]

    static func peopleEN() -> [Person] {
        return [
            Person(name: "Emma Clarke", handle: "emmaclarke", net: "telegram", folder: "f_new", tags: ["VIP"], phone: nil,
                   msgs: [("in", "Hi! How much is the course?", 50)], unread: 1),
            Person(name: "+1 415 555 0132", handle: "+14155550132", net: "whatsapp", folder: "f_talking", tags: [], phone: "+14155550132",
                   msgs: [("in", "Hi, can I book a session for Thursday?", 300), ("out", "Hi! Yes, 3 PM is free", 290), ("in", "Great, I'll pay tomorrow", 280)], unread: 0),
            Person(name: "On Gayrimenkul", handle: "+905301112233", net: "whatsapp", folder: "f_talking", tags: ["Outreach TR"], phone: "+905301112233",
                   msgs: [("out", "Merhaba, On Gayrimenkul! 👋 Google'da firmanızı gördük", 1500)], unread: 0),
            Person(name: "Sophie Martin", handle: "sophie_m", net: "telegram", folder: "f_thinking", tags: ["Website"], phone: nil,
                   msgs: [("out", "Sent you the program and prices", 3000), ("in", "Thanks, I'll think about it until Friday", 2900)], unread: 0),
            Person(name: "Lena Ekicioğlu", handle: "+905551234567", net: "whatsapp", folder: "f_talking", tags: ["Outreach TR"], phone: "+905551234567",
                   msgs: trMessages, unread: 1),
            Person(name: "James Carter", handle: "jcarter", net: "telegram", folder: "f_paid", tags: ["VIP"], phone: "+12125550178",
                   msgs: [("in", "Paid, please check", 6000), ("out", "Thanks for the payment! All received.", 5990)], unread: 0),
            Person(name: "Emir Yapı", handle: "+905339998877", net: "whatsapp", folder: "f_talking", tags: [], phone: "+905339998877",
                   msgs: [("out", "Merhaba, Emir Yapı! 👋", 9000)], unread: 0),
            Person(name: "Olivia Brown", handle: "oliviab", net: "telegram", folder: "f_later", tags: [], phone: nil,
                   msgs: [("in", "Send me the invoice, I'll pay on Monday", 12000), ("out", "Sending the payment details", 11990)], unread: 0),
        ]
    }

    static func peopleRU() -> [Person] {
        return [
            Person(name: "Анна Белова", handle: "annabel", net: "telegram", folder: "f_new", tags: ["VIP"], phone: nil,
                   msgs: [("in", "Здравствуйте! Сколько стоит курс?", 50)], unread: 1),
            Person(name: "+7 988 473-73-30", handle: "+79884737330", net: "whatsapp", folder: "f_talking", tags: [], phone: "+79884737330",
                   msgs: [("in", "Добрый день, можно записаться на четверг?", 300), ("out", "Здравствуйте! Да, в 15:00 свободно", 290), ("in", "Отлично, оплачу завтра", 280)], unread: 0),
            Person(name: "On Gayrimenkul", handle: "+905301112233", net: "whatsapp", folder: "f_talking", tags: ["Рассылка TR"], phone: "+905301112233",
                   msgs: [("out", "Merhaba, On Gayrimenkul! 👋 Google'da firmanızı gördük", 1500)], unread: 0),
            Person(name: "Мария Орлова", handle: "m_orlova", net: "telegram", folder: "f_thinking", tags: ["Сайт"], phone: nil,
                   msgs: [("out", "Отправила программу и цены", 3000), ("in", "Спасибо, я подумаю до пятницы", 2900)], unread: 0),
            Person(name: "Lena Ekicioğlu", handle: "+905551234567", net: "whatsapp", folder: "f_talking", tags: ["Рассылка TR"], phone: "+905551234567",
                   msgs: trMessages, unread: 1),
            Person(name: "Павел Смирнов", handle: "psmirnov", net: "telegram", folder: "f_paid", tags: ["VIP"], phone: "+79161234567",
                   msgs: [("in", "Оплатил, проверьте", 6000), ("out", "Спасибо за оплату! Всё получили.", 5990)], unread: 0),
            Person(name: "Emir Yapı", handle: "+905339998877", net: "whatsapp", folder: "f_talking", tags: [], phone: "+905339998877",
                   msgs: [("out", "Merhaba, Emir Yapı! 👋", 9000)], unread: 0),
            Person(name: "Ольга Тихонова", handle: "olgat", net: "telegram", folder: "f_later", tags: [], phone: nil,
                   msgs: [("in", "Скиньте реквизиты, переведу в понедельник", 12000), ("out", "Отправляю реквизиты для оплаты", 11990)], unread: 0),
        ]
    }

    /// Перевод турецкой переписки: для входящих — на язык владельца, для исходящих — что он написал.
    static func trTranslation(_ j: Int, en: Bool) -> String {
        let enTexts: [String] = [
            "Hi! We looked at your website — the mobile version loads slowly.",
            "Hi, yes, we noticed that too. How long would it take?",
            "About a week. I can send you a quote tomorrow.",
            "Great, looking forward to your quote!",
        ]
        let ruTexts: [String] = [
            "Здравствуйте! Посмотрели ваш сайт — мобильная версия долго открывается.",
            "Здравствуйте, да, мы тоже заметили. Сколько времени займёт?",
            "Примерно неделю. Завтра могу прислать смету.",
            "Отлично, жду вашу смету!",
        ]
        let list: [String] = en ? enTexts : ruTexts
        return j < list.count ? list[j] : ""
    }

    static func targets(_ en: Bool, ago: (Double) -> String) -> [OutreachTarget] {
        let povodName: String = en ? "Loft Studio" : "Студия «Лофт»"
        let povodCity: String = en ? "Austin" : "Казань"
        let povodMsg: String = en
            ? "Hi! We found your studio on the map: your website doesn't open on mobile. Want us to show you how to fix it in a week?"
            : "Здравствуйте! Увидели вашу студию на картах: сайт не открывается с телефона. Можем показать, как это исправить за неделю?"
        let cafeName: String = en ? "Bean & Co" : "Кофейня «Зерно»"
        let cafeCity: String = en ? "Denver" : "Самара"
        let repairName: String = en ? "Fix Pro" : "Ремонт Про"
        let repairCity: String = en ? "Tampa" : "Тула"
        let country: String = en ? "US" : "RU"
        let hello: String = en ? "Hi!…" : "Здравствуйте!…"
        return [
            OutreachTarget(id: "o1", name: "Vamos Bodrum", city: "Bodrum", niche: en ? "Restaurant" : "Ресторан", phone: "+905321112233", site: nil,
                           problem: en ? "No website" : "Нет сайта",
                           rating: 4.6, reviews: 212, waStatus: "yes", message: "Merhaba! Google'da firmanızı gördük…", status: "new", sentAt: nil, repliedAt: nil, contactId: nil, error: nil,
                           source: "tr-setup", country: "TR"),
            OutreachTarget(id: "o3", name: povodName, city: povodCity, niche: en ? "Interior design" : "Дизайн интерьера", phone: en ? "+15125550147" : "+79172223344",
                           site: en ? "loftstudio.com" : "loft-kzn.ru", problem: en ? "Website doesn't work on mobile" : "Сайт не открывается на телефоне",
                           rating: 4.8, reviews: 64, waStatus: "unknown", message: povodMsg,
                           status: "new", sentAt: nil, repliedAt: nil, contactId: nil, error: nil, source: "povod", country: country),
            OutreachTarget(id: "o4", name: cafeName, city: cafeCity, niche: en ? "Coffee shop" : "Кофейня", phone: en ? "+13035550119" : "+79271112233", site: nil,
                           problem: en ? "No website" : "Нет сайта",
                           rating: 4.7, reviews: 128, waStatus: "yes", message: hello, status: "replied", sentAt: ago(300), repliedAt: ago(240), contactId: nil, error: nil,
                           source: "povod", country: country),
            OutreachTarget(id: "o2", name: "Cess Mimarlık", city: "İzmir", niche: en ? "Architecture" : "Архитектура", phone: "+905441112233", site: "cess.com.tr",
                           problem: en ? "Website is down" : "Сайт не открывается",
                           rating: 4.9, reviews: 31, waStatus: "yes", message: "Merhaba…", status: "sent", sentAt: ago(60), repliedAt: nil, contactId: nil, error: nil,
                           source: "tr-setup", country: "TR"),
            OutreachTarget(id: "o5", name: repairName, city: repairCity, niche: en ? "Home renovation" : "Ремонт квартир", phone: en ? "+18135550163" : "+74872334455", site: nil,
                           problem: en ? "Social media only" : "Только соцсети",
                           rating: 4.2, reviews: 18, waStatus: "no", message: hello, status: "skip", sentAt: nil, repliedAt: nil, contactId: nil, error: nil,
                           source: "povod", country: country),
            OutreachTarget(id: "o6", name: "Bodrum Emlak", city: "Bodrum", niche: en ? "Real estate" : "Недвижимость", phone: "+902523334455", site: nil,
                           problem: en ? "No website" : "Нет сайта",
                           rating: 4.4, reviews: 47, waStatus: "no", message: "Merhaba…", status: "new", sentAt: nil, repliedAt: nil, contactId: nil, error: nil,
                           source: "tr-setup", country: "TR"),
        ]
    }

    @MainActor
    static func apply(_ s: Store) {
        let now = Date()
        let en: Bool = isEnglish
        func ago(_ min: Double) -> String { isoString(now.addingTimeInterval(-min * 60)) }
        let folderList: [Folder] = folders(en)
        let people: [Person] = en ? peopleEN() : peopleRU()
        let homeLang: String = en ? "en" : "ru"
        var contacts: [Contact] = [], convs: [Conversation] = [], events: [AppEvent] = []
        for (i, p) in people.enumerated() {
            let cid = "c\(i)", vid = "v\(i)"
            let firstMin = (p.msgs.first?.2 ?? 100) + 60 * 24 * Double(i)
            let note: String = i == 3 ? (en ? "Wants group lessons" : "Хочет групповые занятия") : ""
            let email: String? = i == 5 ? (en ? "james@example.com" : "pavel@example.com") : nil
            contacts.append(Contact(id: cid, name: p.name, handle: p.handle, hue: Double((i * 47) % 360), source: p.net, networks: [p.net],
                                    folderId: p.folder, assignee: "", note: note, phone: p.phone, email: email,
                                    tags: p.tags, lang: (i == 0 || i == 4) ? "tr" : homeLang, avatar: nil, firstContactAt: ago(firstMin)))
            var msgs: [Message] = p.msgs.enumerated().map { j, m in
                Message(id: "m\(i)_\(j)", dir: m.0, text: m.1, at: ago(m.2), author: nil, attachments: nil, translation: nil)
            }
            if i == 0 { msgs = mediaChat(ago, en: en) }
            if i == 4 { msgs = trChat(ago, en: en) }
            convs.append(Conversation(id: vid, contactId: cid, network: p.net, messages: msgs, older: 0, unread: p.unread, channelId: "ch_\(p.net)"))
            events.append(AppEvent(id: "e\(i)", type: "lead_created", contactId: cid, at: ago(firstMin), meta: nil))
            for (j, m) in p.msgs.enumerated() {
                events.append(AppEvent(id: "e\(i)_\(j)", type: m.0 == "in" ? "message_in" : "message_out", contactId: cid, at: ago(m.2), meta: nil))
            }
        }
        let tomorrow10 = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now.addingTimeInterval(86400)) ?? now
        let reminders: [Reminder] = [
            Reminder(id: "r1", contactId: "c1", at: isoString(tomorrow10), text: en ? "Check the payment" : "Проверить оплату", done: false),
            Reminder(id: "r2", contactId: "c7", at: ago(120), text: en ? "Remind about the invoice" : "Напомнить про реквизиты", done: false),
        ]
        let templates: [Template] = en
            ? [Template(id: "t1", title: "Hello", text: "Hi! Thanks for reaching out. What are you interested in?"),
               Template(id: "t2", title: "Payment details", text: "Sending the payment details. Once paid, please send a screenshot.")]
            : [Template(id: "t1", title: "Привет", text: "Здравствуйте! Спасибо, что написали. Подскажите, что вас интересует?"),
               Template(id: "t2", title: "Реквизиты", text: "Отправляю реквизиты для оплаты. После оплаты пришлите, пожалуйста, скрин.")]
        s.state = AppState(
            workspace: WorkspaceInfo(currency: en ? "USD" : "RUB", translate: true),
            channels: [
                Channel(id: "ch_whatsapp", type: "whatsapp", mode: "qr", name: "WhatsApp +905077748057", status: "connected", error: nil),
                Channel(id: "ch_threads", type: "threads", mode: nil, name: "@disifydev", status: "connected", error: nil),
                Channel(id: "ch_telegram", type: "telegram", mode: "mtproto", name: "@disifydev", status: "connected", error: nil),
            ],
            folders: folderList, contacts: contacts, conversations: convs,
            deals: [Deal(id: "d1", contactId: "c5", productId: nil, amount: en ? 500 : 5000, status: "paid", date: ago(5990), dueAt: nil)],
            reminders: reminders,
            events: events,
            templates: templates)
        let ownerName: String = en ? "Owner" : "Владелец"
        s.user = User(id: "u1", workspaceId: "ws1", email: "hi@disify.dev", name: ownerName, role: "owner", locale: homeLang, tz: "Europe/Moscow", features: Features(outreach: true))
        s.account = AccountInfo(name: ownerName, email: "hi@disify.dev", role: "owner", plan: "business", status: "active",
                                workspaceName: en ? "My workspace" : "Мой кабинет", paidUntil: nil, trialEndsAt: nil)
        s.outreach = OutreachList(targets: targets(en, ago: ago), quota: OutreachQuota(ok: true, reason: nil, sentToday: 6, limit: 20), channel: "WhatsApp +905077748057",
           auto: OutreachAuto(on: true, stopped: nil, next: isoString(now.addingTimeInterval(900)), left: 2), error: nil,
           needWhatsApp: false,
           settings: OutreachSettings(dailyLimit: 20, gapMin: 5, startHour: 10, endHour: 19, days: [1, 2, 3, 4, 5], tz: "Europe/Moscow"))
        s.phase = ProcessInfo.processInfo.arguments.contains("-login") ? .login : .ready
        if ProcessInfo.processInfo.arguments.contains("-toast") {
            s.toast = Toast(text: en ? "Label “VIP” removed" : "Метка «VIP» снята", ok: true, undo: {})
        }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-wall"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let w = Wall(rawValue: ProcessInfo.processInfo.arguments[i + 1]) { s.wall = w }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-screen"), i + 1 < ProcessInfo.processInfo.arguments.count {
            switch ProcessInfo.processInfo.arguments[i + 1] {
            case "today": s.tab = .today
            case "summary": s.tab = .summary
            case "profile", "profile-delete": s.tab = .profile   // profile-delete: лист удаления открывает ProfileView
            case "chat": s.chatsPath = [.chat("v1")]
            case "chat-tr", "chat-tr-sheet", "chat-tr-clean": s.chatsPath = [.chat("v4")]   // chat-tr-clean: перевод без листа и клавиатуры (витрина)
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


    /// Турецкая переписка с переводом (чат v4, снимки 24/25): под входящими — перевод, под исходящими — что написал владелец.
    static func trChat(_ ago: (Double) -> String, en: Bool) -> [Message] {
        let target: String = en ? "en" : "ru"
        var out: [Message] = []
        for (j, m) in trMessages.enumerated() {
            let isOut: Bool = m.0 == "out"
            let tr = Translation(lang: isOut ? "tr" : target, text: trTranslation(j, en: en), from: isOut ? target : "tr")
            out.append(Message(id: "m4_\(j)", dir: m.0, text: m.1, at: ago(m.2), author: isOut ? (en ? "You" : "Вы") : nil, attachments: nil, translation: tr))
        }
        return out
    }

    /// Расшифровка голосового «по запросу» в режиме фикстуры (Store.transcribe).
    static var transcribeText: String {
        return isEnglish
            ? "Hi! Can we move the lesson to Thursday at 7 PM? And please send me the payment link."
            : "Добрый день! Хотела уточнить: можно ли перенести занятие на четверг, на семь вечера? И пришлите, пожалуйста, ссылку на оплату."
    }

    /// Переписка с фото, голосовым, ответом и кружком — для снимков чата и просмотрщика.
    static func mediaChat(_ ago: (Double) -> String, en: Bool) -> [Message] {
        let photoName: String = en ? "Photo" : "Фото"
        let voiceName: String = en ? "Voice message" : "Голосовое"
        let noteName: String = en ? "Video message" : "Кружок"
        let you: String = en ? "You" : "Вы"
        let tLang: String = en ? "en" : "ru"
        let photo = Attachment(kind: "image", name: photoName, url: "fixture:photo-1", mediaId: nil, mime: "image/jpeg", round: nil)
        let photo2 = Attachment(kind: "image", name: photoName, url: "fixture:photo-2", mediaId: nil, mime: "image/jpeg", round: nil)
        // волна и длительность пришли с сервера (как у Telegram): файл ради волны не качаем
        let voice = Attachment(kind: "audio", name: voiceName, url: "fixture:voice", mediaId: nil, mime: "audio/ogg", round: nil,
                               waveform: serverWave(), duration: 17)
        let note = Attachment(kind: "video", name: noteName, url: "fixture:note", mediaId: nil, mime: "video/mp4", round: true)
        let t0: String = en ? "Hi! How much is the course?" : "Здравствуйте! Сколько стоит курс?"
        let t1: String = en ? "Here's the program and schedule" : "Вот программа и расписание"
        let t3: String = en ? "This is my level right now" : "А вот так у меня сейчас"
        let t4: String = en ? "Great, the advanced group is a good fit for your level" : "Отлично, с таким уровнем подойдёт продвинутая группа"
        let t6: String = en ? "How much is the full course?" : "Сколько стоит курс целиком?"
        let n2Text: String = en ? "This is how I play now — could you check my hand position, please?" : "Вот так я сейчас играю — посмотрите, пожалуйста, руку."
        let v2Text: String = en ? "One more question: how many people are in a group? I'd like no more than eight." : "И ещё вопрос: в группе сколько человек? Хочу, чтобы было не больше восьми."
        var out: [Message] = []
        out.append(Message(id: "m0_0", dir: "in", text: t0, at: ago(95), author: nil, attachments: nil, translation: nil))
        var a = Message(id: "m0_1", dir: "out", text: t1, at: ago(90), author: you, attachments: [photo], translation: nil)
        a.externalId = "100:11"
        out.append(a)
        out.append(Message(id: "m0_2", dir: "in", text: "", at: ago(70), author: nil, attachments: [voice], translation: nil))
        out.append(Message(id: "m0_3", dir: "in", text: t3, at: ago(60), author: nil, attachments: [photo2], translation: nil))
        var r = Message(id: "m0_4", dir: "out", text: t4, at: ago(55), author: you, attachments: nil, translation: nil)
        r.replyTo = ReplyRef(id: "m0_3", text: t3, dir: "in")
        r.externalId = "100:14"
        out.append(r)
        var n = Message(id: "m0_5", dir: "out", text: "", at: ago(52), author: you, attachments: [note], translation: nil)
        n.externalId = "100:15"
        out.append(n)
        // кружок клиента (слева), расшифровка уже пришла с сервера
        let note2 = Attachment(kind: "video", name: noteName, url: "fixture:note2", mediaId: nil, mime: "video/mp4", round: true)
        var n2 = Message(id: "m0_5b", dir: "in", text: "", at: ago(51), author: nil, attachments: [note2], translation: nil)
        n2.transcript = Transcript(text: n2Text, lang: tLang)
        out.append(n2)
        out.append(Message(id: "m0_6", dir: "in", text: t6, at: ago(50), author: nil, attachments: nil, translation: nil))
        // голосовое, расшифровка которого уже пришла с сервера: по «→A» показывается без запроса
        let voice2 = Attachment(kind: "audio", name: voiceName, url: "fixture:voice2", mediaId: nil, mime: "audio/ogg", round: nil)
        var v2 = Message(id: "m0_7", dir: "in", text: "", at: ago(48), author: nil, attachments: [voice2], translation: nil)
        v2.transcript = Transcript(text: v2Text, lang: tLang)
        out.append(v2)
        return out
    }
}
#endif
