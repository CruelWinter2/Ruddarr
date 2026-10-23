import Foundation

struct SABnzbdClient: DownloadClient {
    let http: DownloadHTTP
    let apiKey: String

    func fetch() async throws -> DownloadSnapshot {
        let queue = try await api(["mode": "queue", "limit": "200"])["queue"] as? [String: Any] ?? [:]
        let history = try await api(["mode": "history", "limit": "30"])["history"] as? [String: Any] ?? [:]

        let slots = queue["slots"] as? [[String: Any]] ?? []
        let rate = Int64(jsonDouble(queue["kbpersec"]) * 1_024)

        var items = slots.map(queueItem)
        // SABnzbd downloads one job at a time, so the queue speed belongs to it
        if let index = items.firstIndex(where: { $0.state == .downloading }) {
            items[index].downloadRate = rate
        }

        var snapshot = DownloadSnapshot()
        snapshot.items = items
        snapshot.history = (history["slots"] as? [[String: Any]] ?? []).map(historyItem)
        snapshot.stats.downloadRate = rate
        snapshot.stats.isPaused = queue["paused"] as? Bool ?? false

        let percent = jsonDouble(queue["speedlimit"])
        let absolute = jsonInt64(queue["speedlimit_abs"])
        snapshot.stats.downloadLimit = percent > 0 && percent < 100 && absolute > 0 ? absolute : nil

        return snapshot
    }

    func pause(_ items: [DownloadItem]) async throws {
        _ = try await api(["mode": "queue", "name": "pause", "value": ids(items)])
    }

    func resume(_ items: [DownloadItem]) async throws {
        _ = try await api(["mode": "queue", "name": "resume", "value": ids(items)])
    }

    func remove(_ items: [DownloadItem], deleteData: Bool) async throws {
        let queued = items.filter { !$0.isHistory }
        let finished = items.filter(\.isHistory)
        let delete = deleteData ? "1" : "0"

        if !queued.isEmpty {
            _ = try await api(["mode": "queue", "name": "delete", "value": ids(queued), "del_files": delete])
        }

        if !finished.isEmpty {
            _ = try await api(["mode": "history", "name": "delete", "value": ids(finished), "del_files": delete])
        }
    }

    func add(link: String) async throws {
        _ = try await api(["mode": "addurl", "name": link])
    }

    func pauseAll() async throws {
        _ = try await api(["mode": "pause"])
    }

    func resumeAll() async throws {
        _ = try await api(["mode": "resume"])
    }

    func setDownloadLimit(_ limit: Int64?) async throws {
        // A plain number is a percentage of the line speed set in SABnzbd; a K suffix is absolute
        let value = limit.map { "\(max(1, $0 / 1_024))K" } ?? "100"
        _ = try await api(["mode": "config", "name": "speedlimit", "value": value])
    }

    private func ids(_ items: [DownloadItem]) -> String {
        items.map(\.id).joined(separator: ",")
    }

    private func queueItem(_ slot: [String: Any]) -> DownloadItem {
        let id = jsonString(slot["nzo_id"]) ?? UUID().uuidString
        let raw = jsonString(slot["status"]) ?? ""

        var item = DownloadItem(id: id, name: jsonString(slot["filename"]) ?? id, state: queueState(raw))
        item.progress = jsonDouble(slot["percentage"]) / 100
        item.size = Int64(jsonDouble(slot["mb"]) * 1_048_576)
        item.eta = seconds(jsonString(slot["timeleft"]))
        item.category = jsonString(slot["cat"]).flatMap { $0 == "*" ? nil : $0 }
        return item
    }

    private func historyItem(_ slot: [String: Any]) -> DownloadItem {
        let id = jsonString(slot["nzo_id"]) ?? UUID().uuidString
        let raw = jsonString(slot["status"]) ?? ""

        var item = DownloadItem(id: id, name: jsonString(slot["name"]) ?? id, state: historyState(raw))
        item.progress = 1
        item.size = jsonInt64(slot["bytes"])
        item.category = jsonString(slot["category"]).flatMap { $0 == "*" ? nil : $0 }
        item.message = jsonString(slot["fail_message"])
        item.isHistory = true

        let completed = jsonDouble(slot["completed"])
        item.date = completed > 0 ? Date(timeIntervalSince1970: completed) : nil
        return item
    }

    private func queueState(_ raw: String) -> DownloadState {
        switch raw {
        case "Downloading": .downloading
        case "Paused": .paused
        case "Queued", "Fetching", "Grabbing", "Propagating": .queued
        case "Checking": .checking
        default: .other(raw)
        }
    }

    private func historyState(_ raw: String) -> DownloadState {
        switch raw {
        case "Completed": .completed
        case "Failed": .failed
        default: .processing
        }
    }

    // SABnzbd sends time left as "h:mm:ss" or "d:hh:mm:ss"
    private func seconds(_ value: String?) -> Int? {
        guard let parts = value?.split(separator: ":").compactMap({ Int($0) }), !parts.isEmpty else {
            return nil
        }

        let total = parts.reduce(0) { $0 * 60 + $1 }
        let adjusted = parts.count == 4 ? parts[0] * 86_400 + parts[1] * 3_600 + parts[2] * 60 + parts[3] : total
        return adjusted > 0 ? adjusted : nil
    }

    private func api(_ query: [String: String]) async throws -> [String: Any] {
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "output", value: "json"))
        items.append(URLQueryItem(name: "apikey", value: apiKey))

        let (data, code) = try await http.send(http.request(http.url("api", query: items)))

        if code == 401 || code == 403 { throw DownloadClientError.unauthorized }
        guard code == 200 else { throw DownloadClientError.status(code) }

        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DownloadClientError.unexpectedResponse
        }

        if body["status"] as? Bool == false {
            let message = jsonString(body["error"]) ?? ""
            if message.localizedCaseInsensitiveContains("api key") { throw DownloadClientError.unauthorized }
            throw DownloadClientError.server(message)
        }

        return body
    }
}
