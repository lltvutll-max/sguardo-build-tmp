import Foundation

/// Настоящий бэкенд Sguardo: https://disify.dev/sguardo. Адреса API — со слэшем на конце (иначе 308).
/// Сессия — cookie `sid` (httpOnly, путь /sguardo) в общем HTTPCookieStorage: её же видят картинки и плееры.
enum API {
    static let origin = URL(string: "https://disify.dev")!
    static let basePath = "/sguardo"
    static let webCabinet = URL(string: "https://disify.dev/sguardo/")!
    static let supportURL = URL(string: "https://disify.dev/sguardo/support/")!
    static let privacyURL = URL(string: "https://disify.dev/sguardo/privacy/")!

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var p = path.hasPrefix("/") ? path : "/" + path
        if !p.hasSuffix("/") { p += "/" }
        var comps = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        comps.path = basePath + p
        if !query.isEmpty { comps.queryItems = query }
        return comps.url!
    }

    /// Ссылка на файл из данных кабинета ("/sguardo/api/files/m/…") → полный адрес.
    /// Абсолютные адреса принимаются только https; куки к ним прикладываются лишь для своего хоста (isOwn).
    static func media(_ raw: String) -> URL? {
        if raw.lowercased().hasPrefix("http") {
            guard let u = URL(string: raw), u.scheme?.lowercased() == "https" else { return nil }
            return u
        }
        var path = raw
        if !path.hasPrefix("/") { path = "/" + path }
        if !path.contains("?") && !path.hasSuffix("/") { path += "/" }
        return URL(string: origin.absoluteString + path)
    }

    /// Свой ли это сервер (только ему можно отдавать сессионную куку).
    static func isOwn(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == origin.host?.lowercased()
    }

    /// Опции AVURLAsset: кука сессии — только для своего хоста, чужим адресам — ничего.
    static func assetOptions(for url: URL) -> [String: Any] {
        isOwn(url) ? ["AVURLAssetHTTPCookiesKey": cookies] : [:]
    }

    /// Загрузка файла: свой хост — через сессию с куками, чужой — через эфемерную сессию без кук.
    static func download(_ url: URL) async throws -> Data {
        if isOwn(url) { return try await session.data(from: url).0 }
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        return try await URLSession(configuration: c).data(from: url).0
    }

    static var cookies: [HTTPCookie] { HTTPCookieStorage.shared.cookies(for: origin.appendingPathComponent("sguardo/")) ?? [] }

    static func clearCookies() {
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.domain.contains("disify.dev") {
            HTTPCookieStorage.shared.deleteCookie(c)
        }
    }

    @discardableResult
    static func send(_ method: String, _ path: String, json: [String: Any]? = nil, query: [URLQueryItem] = [],
                     headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ru", forHTTPHeaderField: "Accept-Language")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(status: 0, message: String(localized: "Нет ответа от сервера")) }
        if http.statusCode >= 400 { throw APIError(status: http.statusCode, message: errorText(data, status: http.statusCode)) }
        return (data, http)
    }

    static func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, _) = try await send("GET", path, query: query)
        return try decode(type, data)
    }

    static func post<T: Decodable>(_ type: T.Type, _ path: String, json: [String: Any]) async throws -> T {
        let (data, _) = try await send("POST", path, json: json)
        return try decode(type, data)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw APIError(status: 0, message: String(localized: "Сервер ответил непонятно, обнови приложение"))
        }
    }

    static func upload(data: Data, name: String, mime: String) async throws -> Attachment {
        let boundary = "sguardo-\(UUID().uuidString)"
        var req = URLRequest(url: url("/api/files/upload/"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\n\(name)\r\n")
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        add("\r\n--\(boundary)--\r\n")
        req.httpBody = body
        req.timeoutInterval = 120
        let (d, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 { throw APIError(status: status, message: errorText(d, status: status)) }
        return try decode(UploadResponse.self, d).attachment
    }

    static func errorText(_ data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let e = obj["error"] as? String, !e.isEmpty { return e }
        switch status {
        case 401: return String(localized: "Нужно войти заново")
        case 402: return String(localized: "Кабинет не оплачен — продли тариф в веб-версии")
        case 403: return String(localized: "Нет доступа")
        case 404: return String(localized: "Не найдено")
        case 429: return String(localized: "Слишком много попыток, подожди немного")
        default: return status >= 500 ? String(localized: "Сервер не ответил, попробуй ещё раз") : String(localized: "Ошибка \(status)")
        }
    }
}

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

func friendly(_ error: Error) -> String {
    if let e = error as? APIError { return e.message }
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return String(localized: "Нет интернета")
        case NSURLErrorTimedOut: return String(localized: "Сервер долго не отвечает")
        case NSURLErrorCancelled: return String(localized: "Отменено")
        default: return String(localized: "Сеть недоступна")
        }
    }
    return error.localizedDescription
}
