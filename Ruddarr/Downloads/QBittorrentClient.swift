import Foundation

// qBittorrent Web API v2. Version 5 renamed pause/resume to stop/start; both are handled.
actor QBittorrentClient: DownloadClient {
    private let http: DownloadHTTP
    private let username: String
    private let password: String
    private var loggedIn = false
    private var cookie: String?

    init(http: DownloadHTTP, username: String, password: String) {
        self.http = http
        self.username = username
        self.password = password
    }

    func fetch() async throws -> DownloadSnapshot {
        let torrents = try await json("torrents/info", query: [URLQueryItem(name: "sort", value: "added_on"), URLQueryItem(name: "reverse", value: "true")])
        let transfer = try await json("transfer/info") as? [String: Any] ?? [:]

        var snapshot = DownloadSnapshot()
        snapshot.items = (torrents as? [[String: Any]] ?? []).map { item($0) }
        snapshot.stats.downloadRate = jsonInt64(transfer["dl_info_speed"])
        snapshot.stats.uploadRate = jsonInt64(transfer["up_info_speed"])

        let limit = jsonInt64(transfer["dl_rate_limit"])
        snapshot.stats.downloadLimit = limit > 0 ? limit : nil
        return snapshot
    }

    func pause(_ items: [DownloadItem]) async throws {
        try await renamed("torrents/stop", "torrents/pause", ["hashes": hashes(items)])
    }

    func resume(_ items: [DownloadItem]) async throws {
        try await renamed("torrents/start", "torrents/resume", ["hashes": hashes(items)])
    }

    func remove(_ items: [DownloadItem], deleteData: Bool) async throws {
        try await post("torrents/delete", ["hashes": hashes(items), "deleteFiles": deleteData ? "true" : "false"])
    }

    func add(link: String) async throws {
        try await post("torrents/add", ["urls": link])
    }

    func pauseAll() async throws {
        try await renamed("torrents/stop", "torrents/pause", ["hashes": "all"])
    }

    func resumeAll() async throws {
        try await renamed("torrents/start", "torrents/resume", ["hashes": "all"])
    }

    func setDownloadLimit(_ limit: Int64?) async throws {
        try await post("transfer/setDownloadLimit", ["limit": String(limit ?? 0)])
    }

    private func hashes(_ items: [DownloadItem]) -> String {
        items.map(\.id).joined(separator: "|")
    }

    private func item(_ torrent: [String: Any]) -> DownloadItem {
        let hash = jsonString(torrent["hash"]) ?? UUID().uuidString
        let eta = Int(jsonDouble(torrent["eta"]))

        var item = DownloadItem(id: hash, name: jsonString(torrent["name"]) ?? hash, state: state(jsonString(torrent["state"]) ?? ""))
        item.progress = jsonDouble(torrent["progress"])
        item.size = jsonInt64(torrent["size"])
        item.downloadRate = jsonInt64(torrent["dlspeed"])
        item.uploadRate = jsonInt64(torrent["upspeed"])
        // 8640000 is qBittorrent's "infinite"
        item.eta = eta > 0 && eta < 8_640_000 ? eta : nil
        item.ratio = jsonDouble(torrent["ratio"])
        item.category = jsonString(torrent["category"])
        item.date = Date(timeIntervalSince1970: jsonDouble(torrent["added_on"]))
        return item
    }

    private func state(_ raw: String) -> DownloadState {
        switch raw {
        case "downloading", "forcedDL", "metaDL", "forcedMetaDL", "stalledDL": .downloading
        case "uploading", "forcedUP", "stalledUP": .seeding
        case "pausedDL", "pausedUP", "stoppedDL", "stoppedUP": .paused
        case "queuedDL", "queuedUP": .queued
        case "checkingDL", "checkingUP", "checkingResumeData", "allocating", "moving": .checking
        case "error", "missingFiles": .failed
        default: .other(raw)
        }
    }

    private func renamed(_ path: String, _ legacy: String, _ fields: [String: String]) async throws {
        do {
            try await post(path, fields)
        } catch DownloadClientError.status(404) {
            try await post(legacy, fields)
        }
    }

    private func json(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        let data = try await send(http.request(http.url("api/v2/" + path, query: query)))
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw DownloadClientError.unexpectedResponse
        }
        return value
    }

    private func post(_ path: String, _ fields: [String: String]) async throws {
        var request = http.request(http.url("api/v2/" + path), method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = http.form(fields)
        _ = try await send(request)
    }

    private func send(_ original: URLRequest) async throws -> Data {
        if !loggedIn { try await login() }

        var request = original
        // qBittorrent's CSRF check compares these with its own address
        request.setValue(http.base.absoluteString, forHTTPHeaderField: "Referer")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }

        var (data, code) = try await http.send(request)

        if code == 403 {
            loggedIn = false
            try await login()
            if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
            (data, code) = try await http.send(request)
        }

        if code == 403 { throw DownloadClientError.unauthorized }
        guard code == 200 else { throw DownloadClientError.status(code) }
        return data
    }

    private func login() async throws {
        var request = http.request(http.url("api/v2/auth/login"), method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(http.base.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = http.form(["username": username, "password": password])

        let (data, code, newCookie) = try await http.sendWithCookie(request)
        let body = String(decoding: data, as: UTF8.self)
        cookie = newCookie

        // Servers that skip auth for local clients answer 200 without "Ok."
        guard code == 200, !body.contains("Fails") else {
            throw code == 403 || body.contains("Fails") ? DownloadClientError.unauthorized : DownloadClientError.status(code)
        }

        loggedIn = true
    }
}
