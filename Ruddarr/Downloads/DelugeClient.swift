import Foundation

// Talks to the Deluge web UI's JSON-RPC endpoint (Deluge 2.x).
actor DelugeClient: DownloadClient {
    private let http: DownloadHTTP
    private let password: String
    private var nextId = 0
    private var connected = false
    private var cookie: String?

    private static let fields = [
        "name", "state", "progress", "download_payload_rate", "upload_payload_rate",
        "total_wanted", "eta", "ratio", "label", "message", "time_added",
    ]

    init(http: DownloadHTTP, password: String) {
        self.http = http
        self.password = password
    }

    func fetch() async throws -> DownloadSnapshot {
        let torrents = try await call("core.get_torrents_status", [[String: Any](), Self.fields]) as? [String: Any] ?? [:]
        let session = try await call(
            "core.get_session_status", [["payload_download_rate", "payload_upload_rate"]]
        ) as? [String: Any] ?? [:]
        let config = try await call("core.get_config_values", [["max_download_speed"]]) as? [String: Any] ?? [:]

        let items = torrents.compactMap { id, value -> DownloadItem? in
            guard let torrent = value as? [String: Any] else { return nil }
            return item(id: id, torrent)
        }

        let limit = jsonDouble(config["max_download_speed"])

        var snapshot = DownloadSnapshot()
        snapshot.items = items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        snapshot.stats.downloadRate = jsonInt64(session["payload_download_rate"])
        snapshot.stats.uploadRate = jsonInt64(session["payload_upload_rate"])
        snapshot.stats.downloadLimit = limit > 0 ? Int64(limit * 1_024) : nil
        return snapshot
    }

    func pause(_ items: [DownloadItem]) async throws {
        _ = try await call("core.pause_torrents", [items.map(\.id)])
    }

    func resume(_ items: [DownloadItem]) async throws {
        _ = try await call("core.resume_torrents", [items.map(\.id)])
    }

    func remove(_ items: [DownloadItem], deleteData: Bool) async throws {
        for item in items {
            _ = try await call("core.remove_torrent", [item.id, deleteData])
        }
    }

    func add(link: String) async throws {
        if link.lowercased().hasPrefix("magnet:") {
            _ = try await call("core.add_torrent_magnet", [link, [String: Any]()])
        } else {
            _ = try await call("core.add_torrent_url", [link, [String: Any]()])
        }
    }

    func pauseAll() async throws {
        _ = try await call("core.pause_session", [])
    }

    func resumeAll() async throws {
        _ = try await call("core.resume_session", [])
    }

    func setDownloadLimit(_ limit: Int64?) async throws {
        // Deluge stores the limit in KiB/s, -1 for unlimited
        let value: Double = limit.map { Double($0) / 1_024 } ?? -1
        _ = try await call("core.set_config", [["max_download_speed": value]])
    }

    private func item(id: String, _ torrent: [String: Any]) -> DownloadItem {
        let rawState = jsonString(torrent["state"]) ?? ""
        let progress = jsonDouble(torrent["progress"]) / 100
        let eta = Int(jsonDouble(torrent["eta"]))
        let message = jsonString(torrent["message"])

        var item = DownloadItem(id: id, name: jsonString(torrent["name"]) ?? id, state: state(rawState))
        item.progress = progress
        item.size = jsonInt64(torrent["total_wanted"])
        item.downloadRate = jsonInt64(torrent["download_payload_rate"])
        item.uploadRate = jsonInt64(torrent["upload_payload_rate"])
        item.eta = eta > 0 ? eta : nil
        item.ratio = jsonDouble(torrent["ratio"])
        item.category = jsonString(torrent["label"])
        item.message = message == "OK" ? nil : message
        item.date = Date(timeIntervalSince1970: jsonDouble(torrent["time_added"]))
        return item
    }

    private func state(_ raw: String) -> DownloadState {
        switch raw {
        case "Downloading": .downloading
        case "Seeding": .seeding
        case "Paused": .paused
        case "Queued": .queued
        case "Checking", "Allocating", "Moving": .checking
        case "Error": .failed
        default: .other(raw)
        }
    }

    private func call(_ method: String, _ params: [Any]) async throws -> Any? {
        if !connected { try await connect() }

        do {
            return try await rpc(method, params)
        } catch DelugeError.notAuthenticated {
            connected = false
            try await connect()
        }

        do {
            return try await rpc(method, params)
        } catch DelugeError.notAuthenticated {
            connected = false
            throw DownloadClientError.unauthorized
        }
    }

    private func connect() async throws {
        cookie = nil
        guard try await rpc("auth.login", [password]) as? Bool == true, cookie != nil else {
            throw DownloadClientError.unauthorized
        }

        if try await rpc("web.connected", []) as? Bool != true {
            // The web UI isn't attached to a daemon yet, so use the first one it knows about
            guard let hosts = try await rpc("web.get_hosts", []) as? [[Any]],
                  let hostId = hosts.first?.first as? String
            else {
                throw DownloadClientError.server(String(localized: "Deluge has no daemon to connect to."))
            }

            _ = try await rpc("web.connect", [hostId])
        }

        connected = true
    }

    private enum DelugeError: Error {
        case notAuthenticated
    }

    private func rpc(_ method: String, _ params: [Any]) async throws -> Any? {
        nextId += 1

        var request = http.request(http.url("json"), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "method": method, "params": params, "id": nextId,
        ])

        let (data, code, newCookie) = try await http.sendWithCookie(request)
        guard code == 200 else { throw DownloadClientError.status(code) }
        if let newCookie { cookie = newCookie }

        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DownloadClientError.unexpectedResponse
        }

        if let error = body["error"] as? [String: Any] {
            // Code 1 means the session cookie expired
            if jsonInt64(error["code"]) == 1 { throw DelugeError.notAuthenticated }
            throw DownloadClientError.server(jsonString(error["message"]) ?? method)
        }

        return body["result"]
    }
}
