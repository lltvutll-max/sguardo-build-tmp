import Foundation

/// Последняя копия кабинета на диске: при запуске экран показывается сразу из неё, свежие данные приходят в фоне.
/// Стирается при выходе и удалении аккаунта (Store.resetAll). В режиме снимков CI (-fixture) не используется.
struct CachedSnapshot: Codable {
    var version: Int
    var user: User?
    var state: AppState
    var history: [String: [Message]]
    var savedAt: Date
}

enum DiskCache {
    /// меняем, когда меняется формат моделей — старый файл просто не прочитается
    static let version: Int = 1
    /// история одного чата в кэше — не больше стольких последних сообщений
    static let historyLimit: Int = 1000

    private static let queue = DispatchQueue(label: "dev.disify.sguardo.disk-cache", qos: .utility)

    private static var folder: URL {
        let base: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("sguardo-cache", isDirectory: true)
    }

    static var snapshotURL: URL { folder.appendingPathComponent("state.json") }
    static var outreachURL: URL { folder.appendingPathComponent("outreach.json") }

    static func loadSnapshot() -> CachedSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        guard let snap = try? JSONDecoder().decode(CachedSnapshot.self, from: data), snap.version == version else { return nil }
        return snap
    }

    static func loadOutreach() -> OutreachList? {
        guard let data = try? Data(contentsOf: outreachURL) else { return nil }
        return try? JSONDecoder().decode(OutreachList.self, from: data)
    }

    /// Запись в фоне (последовательная очередь): кодирование не тормозит интерфейс.
    static func save<T: Encodable>(_ value: T, to url: URL) {
        let dir: URL = folder
        queue.async {
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Стереть всё. Ждёт уже поставленные записи, чтобы они не вернули файл после удаления.
    static func clear() {
        let dir: URL = folder
        queue.sync {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
