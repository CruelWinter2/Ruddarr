import Foundation

enum IndexerPrivacy: String, Sendable {
    case `public`
    case semiPrivate
    case `private`

    var label: String {
        switch self {
        case .public: String(localized: "Public", comment: "Indexer privacy")
        case .semiPrivate: String(localized: "Semi-private", comment: "Indexer privacy")
        case .private: String(localized: "Private", comment: "Indexer privacy")
        }
    }
}

struct ProwlarrIndexer: Identifiable, Sendable, Equatable {
    let id: Int
    var name: String
    var enabled: Bool
    var protocolName: String
    var privacy: IndexerPrivacy
    var disabledUntil: Date?
    var failure: String?
}

struct ProwlarrResult: Identifiable, Sendable, Equatable {
    var id: String { "\(indexerId)-\(guid)" }
    let guid: String
    let indexerId: Int
    var indexer: String
    var title: String
    var size: Int64
    var published: Date?
    var seeders: Int?
    var leechers: Int?
    var grabs: Int?
    var isTorrent: Bool
    var privacy: IndexerPrivacy
    var category: String?
    // Magnet if the indexer gives one, otherwise Prowlarr's download link
    var link: String?

    var summary: String {
        var parts = [indexer, privacy.label, formatBytes(size)]
        if isTorrent {
            parts.append(String(localized: "\(seeders ?? 0) seeders, \(leechers ?? 0) leechers"))
        }
        if let published {
            parts.append(published.formatted(.relative(presentation: .named)))
        }
        if let category { parts.append(category) }
        return parts.joined(separator: ", ")
    }
}

enum ProwlarrCategory: Int, CaseIterable, Identifiable, Sendable {
    var id: Self { self }

    case all = 0
    case movies = 2_000
    case tv = 5_000
    case audio = 3_000
    case books = 7_000

    var label: String {
        switch self {
        case .all: String(localized: "All Categories")
        case .movies: String(localized: "Movies")
        case .tv: String(localized: "TV")
        case .audio: String(localized: "Music")
        case .books: String(localized: "Books")
        }
    }
}

struct ProwlarrClient: Sendable {
    let http: DownloadHTTP

    init(server: ServiceServer) throws {
        guard let base = server.baseURL else { throw DownloadClientError.invalidURL }
        var headers = server.extraHeaders
        headers["X-Api-Key"] = server.apiKey
        http = DownloadHTTP(base: base, headers: headers)
    }

    func indexers() async throws -> [ProwlarrIndexer] {
        let list = try await get("indexer") as? [[String: Any]] ?? []
        let statuses = try await get("indexerstatus") as? [[String: Any]] ?? []

        var disabled: [Int: (Date?, String?)] = [:]
        for status in statuses {
            let id = Int(jsonDouble(status["indexerId"]))
            let until = jsonString(status["disabledTill"]).flatMap { try? Date($0, strategy: .iso8601) }
            let failure = jsonString(status["mostRecentFailure"])
            disabled[id] = (until, failure)
        }

        return list.map { raw in
            let id = Int(jsonDouble(raw["id"]))
            return ProwlarrIndexer(
                id: id,
                name: (jsonString(raw["name"]) ?? "").trimmingCharacters(in: .whitespaces),
                enabled: raw["enable"] as? Bool ?? false,
                protocolName: jsonString(raw["protocol"]) ?? "",
                privacy: IndexerPrivacy(rawValue: jsonString(raw["privacy"]) ?? "") ?? .private,
                disabledUntil: disabled[id]?.0.flatMap { $0 > .now ? $0 : nil },
                failure: disabled[id]?.1
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func health() async throws -> [String] {
        let items = try await get("health") as? [[String: Any]] ?? []
        return items.compactMap { jsonString($0["message"]) }
    }

    func search(_ query: String, category: ProwlarrCategory, indexers: [ProwlarrIndexer]) async throws -> [ProwlarrResult] {
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "type", value: "search"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        if category != .all {
            items.append(URLQueryItem(name: "categories", value: String(category.rawValue)))
        }

        let privacy = Dictionary(uniqueKeysWithValues: indexers.map { ($0.id, $0.privacy) })
        let raw = try await get("search", query: items, timeout: 90) as? [[String: Any]] ?? []

        return raw.map { result in
            let guid = jsonString(result["guid"]) ?? UUID().uuidString
            let indexerId = Int(jsonDouble(result["indexerId"]))
            let isTorrent = jsonString(result["protocol"]) == "torrent"
            let magnet = guid.lowercased().hasPrefix("magnet:") ? guid : nil
            let categories = result["categories"] as? [[String: Any]] ?? []

            return ProwlarrResult(
                guid: guid,
                indexerId: indexerId,
                indexer: jsonString(result["indexer"]) ?? "",
                title: jsonString(result["title"]) ?? guid,
                size: jsonInt64(result["size"]),
                published: jsonString(result["publishDate"]).flatMap { try? Date($0, strategy: .iso8601) },
                seeders: result["seeders"].map { Int(jsonDouble($0)) },
                leechers: result["leechers"].map { Int(jsonDouble($0)) },
                grabs: result["grabs"].map { Int(jsonDouble($0)) },
                isTorrent: isTorrent,
                privacy: privacy[indexerId] ?? .private,
                category: categories.compactMap { jsonString($0["name"]) }.first,
                link: magnet ?? jsonString(result["downloadUrl"]) ?? jsonString(result["magnetUrl"])
            )
        }
    }

    // Sends the release to the download client configured inside Prowlarr
    func grab(_ result: ProwlarrResult) async throws {
        try await send("search", method: "POST", body: ["guid": result.guid, "indexerId": result.indexerId])
    }

    func setEnabled(_ indexer: ProwlarrIndexer, _ enabled: Bool) async throws {
        guard var raw = try await get("indexer/\(indexer.id)") as? [String: Any] else {
            throw DownloadClientError.unexpectedResponse
        }
        raw["enable"] = enabled
        try await send("indexer/\(indexer.id)", method: "PUT", body: raw)
    }

    // Returns nil when the indexer works, otherwise Prowlarr's reason
    func test(_ indexer: ProwlarrIndexer) async throws -> String? {
        guard let raw = try await get("indexer/\(indexer.id)") as? [String: Any] else {
            throw DownloadClientError.unexpectedResponse
        }

        do {
            try await send("indexer/test", method: "POST", body: raw)
            return nil
        } catch DownloadClientError.server(let message) {
            return message
        }
    }

    private func get(_ path: String, query: [URLQueryItem] = [], timeout: Double = 20) async throws -> Any {
        var request = http.request(http.url("api/v1/" + path, query: query))
        request.timeoutInterval = timeout
        let (data, code) = try await http.send(request)
        try check(code, data)
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw DownloadClientError.unexpectedResponse
        }
        return value
    }

    private func send(_ path: String, method: String, body: [String: Any]) async throws {
        var request = http.request(http.url("api/v1/" + path), method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60
        let (data, code) = try await http.send(request)
        try check(code, data)
    }

    private func check(_ code: Int, _ data: Data) throws {
        if code == 401 { throw DownloadClientError.unauthorized }
        guard (200..<300).contains(code) else {
            // Prowlarr explains validation failures as a list of {errorMessage}
            let body = try? JSONSerialization.jsonObject(with: data)
            let messages = (body as? [[String: Any]])?.compactMap { jsonString($0["errorMessage"]) }
                ?? [jsonString((body as? [String: Any])?["message"])].compactMap { $0 }
            if let message = messages.first { throw DownloadClientError.server(message) }
            throw DownloadClientError.status(code)
        }
    }
}
