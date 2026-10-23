import Foundation

enum SeerrRequestStatus: Int, Sendable {
    case pending = 1
    case approved = 2
    case declined = 3
    case failed = 4
    case completed = 5

    var label: String {
        switch self {
        case .pending: String(localized: "Waiting for approval", comment: "Seerr request status")
        case .approved: String(localized: "Approved", comment: "Seerr request status")
        case .declined: String(localized: "Declined", comment: "Seerr request status")
        case .failed: String(localized: "Failed", comment: "Seerr request status")
        case .completed: String(localized: "Completed", comment: "Seerr request status")
        }
    }
}

enum SeerrMediaStatus: Int, Sendable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5
    case deleted = 6

    var label: String {
        switch self {
        case .unknown: String(localized: "Not requested", comment: "Seerr media status")
        case .pending: String(localized: "Requested", comment: "Seerr media status")
        case .processing: String(localized: "Downloading", comment: "Seerr media status")
        case .partiallyAvailable: String(localized: "Partly available", comment: "Seerr media status")
        case .available: String(localized: "Available", comment: "Seerr media status")
        case .deleted: String(localized: "Deleted", comment: "Seerr media status")
        }
    }
}

enum SeerrFilter: String, CaseIterable, Identifiable, Sendable {
    var id: Self { self }

    case all
    case pending
    case processing
    case available

    var label: String {
        switch self {
        case .all: String(localized: "All Requests")
        case .pending: String(localized: "Waiting for Approval")
        // Seerr counts partly available requests as still processing
        case .processing: String(localized: "Downloading or Partly Available")
        case .available: String(localized: "Available")
        }
    }
}

struct SeerrRequest: Identifiable, Sendable, Equatable {
    let id: Int
    var status: SeerrRequestStatus?
    var mediaStatus: SeerrMediaStatus?
    var isMovie: Bool
    var tmdbId: Int
    var title: String
    var requestedBy: String
    var created: Date?
    var seasons: Int

    var summary: String {
        var parts = [isMovie ? String(localized: "Movie") : String(localized: "Series")]
        if !isMovie, seasons > 0 { parts.append(String(localized: "\(seasons) seasons")) }
        if let status { parts.append(status.label) }
        if let mediaStatus, mediaStatus != .unknown, status != .pending { parts.append(mediaStatus.label) }
        parts.append(String(localized: "by \(requestedBy)"))
        if let created { parts.append(created.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: ", ")
    }
}

struct SeerrResult: Identifiable, Sendable, Equatable {
    var id: String { "\(isMovie ? "movie" : "tv")-\(tmdbId)" }
    let tmdbId: Int
    var isMovie: Bool
    var title: String
    var year: String?
    var overview: String?
    var status: SeerrMediaStatus

    var summary: String {
        var parts = [isMovie ? String(localized: "Movie") : String(localized: "Series")]
        if let year { parts.append(year) }
        parts.append(status.label)
        return parts.joined(separator: ", ")
    }

    var canRequest: Bool { status == .unknown || status == .deleted || status == .partiallyAvailable }
}

actor SeerrClient {
    private let http: DownloadHTTP
    private var titles: [String: String] = [:]

    init(server: ServiceServer) throws {
        guard let base = server.baseURL else { throw DownloadClientError.invalidURL }
        var headers = server.extraHeaders
        headers["X-Api-Key"] = server.apiKey
        http = DownloadHTTP(base: base, headers: headers)
    }

    func requests(_ filter: SeerrFilter) async throws -> [SeerrRequest] {
        let body = try await get("request", query: [
            URLQueryItem(name: "take", value: "100"),
            URLQueryItem(name: "filter", value: filter.rawValue),
            URLQueryItem(name: "sort", value: "added"),
        ]) as? [String: Any] ?? [:]

        var list: [SeerrRequest] = []
        for raw in body["results"] as? [[String: Any]] ?? [] {
            let media = raw["media"] as? [String: Any] ?? [:]
            let isMovie = jsonString(raw["type"]) == "movie"
            let tmdbId = Int(jsonDouble(media["tmdbId"]))
            let user = raw["requestedBy"] as? [String: Any] ?? [:]

            list.append(SeerrRequest(
                id: Int(jsonDouble(raw["id"])),
                status: SeerrRequestStatus(rawValue: Int(jsonDouble(raw["status"]))),
                mediaStatus: SeerrMediaStatus(rawValue: Int(jsonDouble(media["status"]))),
                isMovie: isMovie,
                tmdbId: tmdbId,
                title: try await title(tmdbId, isMovie: isMovie),
                requestedBy: jsonString(user["displayName"]) ?? "",
                created: jsonString(raw["createdAt"]).flatMap(seerrDate),
                seasons: (raw["seasons"] as? [Any])?.count ?? 0
            ))
        }
        return list
    }

    func search(_ query: String) async throws -> [SeerrResult] {
        let body = try await get("search", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: "1"),
        ]) as? [String: Any] ?? [:]

        return (body["results"] as? [[String: Any]] ?? []).compactMap { raw in
            let type = jsonString(raw["mediaType"])
            guard type == "movie" || type == "tv" else { return nil }

            let media = raw["mediaInfo"] as? [String: Any] ?? [:]
            let date = jsonString(raw["releaseDate"]) ?? jsonString(raw["firstAirDate"])

            return SeerrResult(
                tmdbId: Int(jsonDouble(raw["id"])),
                isMovie: type == "movie",
                title: jsonString(raw["title"]) ?? jsonString(raw["name"]) ?? "",
                year: date.map { String($0.prefix(4)) },
                overview: jsonString(raw["overview"]),
                status: SeerrMediaStatus(rawValue: Int(jsonDouble(media["status"]))) ?? .unknown
            )
        }
    }

    func request(_ result: SeerrResult) async throws {
        var body: [String: Any] = ["mediaType": result.isMovie ? "movie" : "tv", "mediaId": result.tmdbId]

        if !result.isMovie {
            // Ask for every regular season; season 0 holds specials
            let details = try await get("tv/\(result.tmdbId)") as? [String: Any] ?? [:]
            let seasons = (details["seasons"] as? [[String: Any]] ?? [])
                .map { Int(jsonDouble($0["seasonNumber"])) }
                .filter { $0 > 0 }
            body["seasons"] = seasons
        }

        try await send("request", method: "POST", body: body)
    }

    func approve(_ request: SeerrRequest) async throws {
        try await send("request/\(request.id)/approve", method: "POST", body: nil)
    }

    func decline(_ request: SeerrRequest) async throws {
        try await send("request/\(request.id)/decline", method: "POST", body: nil)
    }

    func delete(_ request: SeerrRequest) async throws {
        try await send("request/\(request.id)", method: "DELETE", body: nil)
    }

    func check() async throws {
        _ = try await get("request", query: [URLQueryItem(name: "take", value: "1")])
    }

    private func title(_ tmdbId: Int, isMovie: Bool) async throws -> String {
        let key = "\(isMovie ? "movie" : "tv")/\(tmdbId)"
        if let cached = titles[key] { return cached }

        let details = (try? await get(key)) as? [String: Any] ?? [:]
        let title = jsonString(details["title"]) ?? jsonString(details["name"]) ?? "TMDB \(tmdbId)"
        titles[key] = title
        return title
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        var items = query
        // Seerr rejects reserved characters it expects to be percent-encoded
        for index in items.indices {
            items[index].value = items[index].value?.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        }

        var components = URLComponents(url: http.url("api/v1/" + path), resolvingAgainstBaseURL: false)
        components?.percentEncodedQueryItems = items.isEmpty ? nil : items
        guard let url = components?.url else { throw DownloadClientError.invalidURL }

        let (data, code) = try await http.send(http.request(url))
        try check(code, data)
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            throw DownloadClientError.unexpectedResponse
        }
        return value
    }

    private func send(_ path: String, method: String, body: [String: Any]?) async throws {
        var request = http.request(http.url("api/v1/" + path), method: method)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, code) = try await http.send(request)
        try check(code, data)
    }

    private func check(_ code: Int, _ data: Data) throws {
        if code == 401 || code == 403 { throw DownloadClientError.unauthorized }
        guard (200..<300).contains(code) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let message = jsonString(body?["message"]) { throw DownloadClientError.server(message) }
            throw DownloadClientError.status(code)
        }
    }
}

// Seerr timestamps carry milliseconds, e.g. 2026-10-18T21:49:33.000Z
private func seerrDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
