import Foundation

// Модели — зеркало src/lib/types.ts бэкенда Sguardo. Поля, без которых экран живёт, — необязательные:
// бэкенд меняется, и приложение не должно падать на новом/пропавшем поле.

struct Folder: Codable, Identifiable, Hashable {
    let id: String
    let key: String?
    var name: String
    var color: String?
}

struct Attachment: Codable, Hashable {
    let kind: String
    let name: String?
    let url: String
    let mediaId: String?
    let mime: String?
    let round: Bool?
    /// голосовое: волна с сервера (до 100 точек 0…31, как в Telegram) — рисуем её, файл ради волны не качаем
    var waveform: [Double]? = nil
    /// голосовое: длительность в секундах с сервера
    var duration: Double? = nil
}

struct Translation: Codable, Hashable {
    let lang: String?
    let text: String
    let from: String?
}

struct ReplyRef: Codable, Hashable {
    let id: String
    let text: String
    let dir: String?
}

/// Расшифровка голосового/кружка (Groq Whisper на сервере).
struct Transcript: Codable, Hashable {
    let text: String
    let lang: String?
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let dir: String
    let text: String?
    let at: String
    let author: String?
    let attachments: [Attachment]?
    let translation: Translation?
    var replyTo: ReplyRef? = nil
    var externalId: String? = nil
    var authorId: String? = nil
    var transcript: Transcript? = nil

    var isOut: Bool { dir == "out" }
    var date: Date { parseISO(at) ?? .distantPast }
    var body: String { text ?? "" }

    var preview: String {
        if !body.isEmpty { return body }
        if attachments?.first?.round == true { return String(localized: "Кружок") }
        switch attachments?.first?.kind {
        case "audio": return String(localized: "Голосовое сообщение")
        case "image": return String(localized: "Фото")
        case "video": return String(localized: "Видео")
        case .some: return String(localized: "Вложение")
        default: return ""
        }
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let network: String
    var messages: [Message]
    let older: Int?
    var unread: Int
    let channelId: String?

    var last: Message? { messages.last }
}

struct Contact: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let handle: String?
    let hue: Double?
    let source: String?
    let networks: [String]?
    let folderId: String?
    let assignee: String?
    let note: String?
    let phone: String?
    let email: String?
    let tags: [String]?
    let lang: String?
    let avatar: String?
    let firstContactAt: String?

    var first: Date { parseISO(firstContactAt) ?? .distantPast }
    var displayHue: Double { hue ?? Double(stableHash(name)) }
}

struct Deal: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let productId: String?
    let amount: Double
    let status: String
    let date: String
    let dueAt: String?
    var day: Date { parseISO(date) ?? .distantPast }
}

struct Reminder: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String
    let at: String
    let text: String
    let done: Bool
    var date: Date { parseISO(at) ?? .distantPast }
}

struct AppEvent: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let contactId: String
    let at: String
    let meta: String?
    var date: Date { parseISO(at) ?? .distantPast }
}

struct Template: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let text: String
}

struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let mode: String?
    let name: String
    let status: String
    let error: String?
}

struct WorkspaceInfo: Codable, Hashable {
    let currency: String?
    let translate: Bool?
}

struct AppState: Codable {
    var workspace: WorkspaceInfo?
    var channels: [Channel]
    var folders: [Folder]
    var contacts: [Contact]
    var conversations: [Conversation]
    var deals: [Deal]
    var reminders: [Reminder]
    var events: [AppEvent]
    var templates: [Template]

    static let empty = AppState(workspace: nil, channels: [], folders: [], contacts: [], conversations: [], deals: [], reminders: [], events: [], templates: [])

    init(workspace: WorkspaceInfo?, channels: [Channel], folders: [Folder], contacts: [Contact], conversations: [Conversation],
         deals: [Deal], reminders: [Reminder], events: [AppEvent], templates: [Template]) {
        self.workspace = workspace; self.channels = channels; self.folders = folders; self.contacts = contacts
        self.conversations = conversations; self.deals = deals; self.reminders = reminders; self.events = events; self.templates = templates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try? c.decodeIfPresent(WorkspaceInfo.self, forKey: .workspace)
        channels = (try? c.decodeIfPresent([Channel].self, forKey: .channels)) ?? []
        folders = (try? c.decodeIfPresent([Folder].self, forKey: .folders)) ?? []
        contacts = (try? c.decodeIfPresent([Contact].self, forKey: .contacts)) ?? []
        conversations = (try? c.decodeIfPresent([Conversation].self, forKey: .conversations)) ?? []
        deals = (try? c.decodeIfPresent([Deal].self, forKey: .deals)) ?? []
        reminders = (try? c.decodeIfPresent([Reminder].self, forKey: .reminders)) ?? []
        events = (try? c.decodeIfPresent([AppEvent].self, forKey: .events)) ?? []
        templates = (try? c.decodeIfPresent([Template].self, forKey: .templates)) ?? []
    }
}

/// Сравнение состояний: одинаковый ответ сервера не перерисовывает экраны (без мигания при фоновом обновлении).
extension AppState: Equatable {}

struct Features: Codable, Hashable {
    let outreach: Bool?
}

struct User: Codable, Hashable {
    let id: String
    let workspaceId: String?
    let email: String
    let name: String
    let role: String
    let locale: String?
    let tz: String?
    let features: Features?
    var isOwner: Bool { role == "owner" }
}

struct StateResponse: Codable {
    let state: AppState
    let user: User?
}

struct ActionResponse: Codable {
    let state: AppState
}

struct MeResponse: Codable {
    let user: User
}

struct HistoryResponse: Codable {
    let messages: [Message]
}

struct AccountInfo: Codable {
    let name: String?
    let email: String?
    let role: String?
    let plan: String?
    let status: String?
    let workspaceName: String?
    let paidUntil: String?
    let trialEndsAt: String?
}

struct UploadResponse: Codable {
    let attachment: Attachment
}

// Рассылка: владелец оплаченного кабинета (или кабинета с флагом features.outreach). Помощникам 403, без оплаты 402.
struct OutreachTarget: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String?
    let niche: String?
    let phone: String?
    let site: String?
    let problem: String?
    let rating: Double?
    let reviews: Double?
    let waStatus: String?
    let message: String?
    let status: String
    let sentAt: String?
    let repliedAt: String?
    let contactId: String?
    let error: String?
    /// откуда фирма: "tr-setup" — «Рассылка TR», "povod" — «Рассылка Повод»
    var source: String? = nil
    var country: String? = nil

    var isPovod: Bool { source == "povod" }
    /// ещё не написали — можно править текст, пропускать и убирать из списка
    var unsent: Bool { status == "new" || status == "skip" }
}

/// Настройки рассылки кабинета (GET/POST /api/outreach/settings): лимит в сутки, пауза, окно автоотправки.
struct OutreachSettings: Codable, Hashable {
    var dailyLimit: Int
    var gapMin: Int
    var startHour: Int
    var endHour: Int
    /// 0 — воскресенье … 6 — суббота
    var days: [Int]
    var tz: String?

    /// как было до настроек: 15 в сутки, раз в 3 минуты, 10:00–19:00, пн–сб
    static let defaults = OutreachSettings(dailyLimit: 15, gapMin: 3, startHour: 10, endHour: 19, days: [1, 2, 3, 4, 5, 6], tz: nil)
    static let dailyRange: ClosedRange<Int> = 1...40
    static let gapRange: ClosedRange<Int> = 3...120
    /// с какого часа можно начинать (6…22) и до какого заканчивать (до 24); окно — не меньше 2 часов
    static let firstHour = 6
    static let lastHour = 24
    static let minWindow = 2
    /// автоотправка не чаще раза в 15 минут, даже если пауза меньше
    static let autoMinGap = 15
}

struct OutreachSettingsReply: Codable {
    let settings: OutreachSettings
}

struct OutreachQuota: Codable, Hashable {
    let ok: Bool?
    let reason: String?
    let sentToday: Int?
    let limit: Int?
}

struct OutreachAuto: Codable, Hashable {
    let on: Bool?
    let stopped: String?
    let next: String?
    let left: Int?
}

struct OutreachList: Codable {
    let targets: [OutreachTarget]
    let quota: OutreachQuota?
    let channel: String?
    let auto: OutreachAuto?
    let error: String?
    /// WhatsApp по QR не подключён: проверять номера и писать нечем
    var needWhatsApp: Bool? = nil
    var settings: OutreachSettings? = nil
    /// ответы на действия: результат проверки номера ("yes"/"no"), сколько убрано, «ушло не полностью»
    var wa: String? = nil
    var removed: Int? = nil
    var partial: String? = nil
}

// MARK: - даты

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

func parseISO(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

func isoString(_ d: Date) -> String { isoFrac.string(from: d) }

/// Ответ POST /api/account/delete/: {ok, scope: "workspace"|"user", povod, note}.
struct AccountDeleteResponse: Decodable {
    let ok: Bool
    let scope: String?
    let povod: Bool?
    let note: String?
}
