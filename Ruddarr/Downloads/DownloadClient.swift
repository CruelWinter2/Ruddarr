import Foundation

protocol DownloadClient: Sendable {
    func fetch() async throws -> DownloadSnapshot
    func pause(_ items: [DownloadItem]) async throws
    func resume(_ items: [DownloadItem]) async throws
    func remove(_ items: [DownloadItem], deleteData: Bool) async throws
    func add(link: String) async throws
    func pauseAll() async throws
    func resumeAll() async throws
    // Bytes per second, nil for unlimited
    func setDownloadLimit(_ limit: Int64?) async throws
}

func makeDownloadClient(for server: DownloadServer) throws -> any DownloadClient {
    guard let base = server.baseURL else {
        throw DownloadClientError.invalidURL
    }

    let http = DownloadHTTP(base: base, headers: server.extraHeaders)

    return switch server.kind {
    case .deluge: DelugeClient(http: http, password: server.password)
    case .qbittorrent: QBittorrentClient(http: http, username: server.username, password: server.password)
    case .sabnzbd: SABnzbdClient(http: http, apiKey: server.apiKey)
    }
}

enum DownloadClientError: LocalizedError {
    case invalidURL
    case unauthorized
    case status(Int)
    case server(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The server address isn't a valid URL.")
        case .unauthorized:
            String(localized: "The server rejected the password or API key.")
        case .status(let code):
            String(localized: "The server answered with an error (HTTP \(code)).")
        case .server(let message):
            String(localized: "The server reported a problem: \(message)")
        case .unexpectedResponse:
            String(localized: "The server sent a reply the app couldn't read.")
        }
    }
}

// Login cookies are kept by each client and sent by hand, so they never mix between servers.
struct DownloadHTTP: Sendable {
    let base: URL
    let headers: [String: String]
    let session: URLSession

    init(base: URL, headers: [String: String]) {
        self.base = base
        self.headers = headers

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var url = base.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        return url
    }

    func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, code, _) = try await sendWithCookie(request)
        return (data, code)
    }

    // Also returns any cookies the server set, joined into one Cookie header value
    func sendWithCookie(_ request: URLRequest) async throws -> (Data, Int, String?) {
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        var cookie: String?

        if let http, let url = http.url {
            let fields = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
            }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            if !cookies.isEmpty {
                cookie = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
        }

        return (data, http?.statusCode ?? 0, cookie)
    }

    func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        // URLComponents leaves "+" alone, which form decoding reads as a space
        let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return Data(encoded.utf8)
    }
}

// Loose readers for JSON that mixes numbers and numeric strings.
func jsonDouble(_ value: Any?) -> Double {
    switch value {
    case let number as NSNumber: number.doubleValue
    case let string as String: Double(string) ?? 0
    default: 0
    }
}

func jsonInt64(_ value: Any?) -> Int64 {
    Int64(jsonDouble(value))
}

func jsonString(_ value: Any?) -> String? {
    switch value {
    case let string as String: string.isEmpty ? nil : string
    case let number as NSNumber: number.stringValue
    default: nil
    }
}
