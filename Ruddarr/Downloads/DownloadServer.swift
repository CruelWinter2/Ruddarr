import Foundation
import Observation

enum DownloadServerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    var id: Self { self }

    case deluge
    case qbittorrent
    case sabnzbd

    var label: String {
        switch self {
        case .deluge: "Deluge"
        case .qbittorrent: "qBittorrent"
        case .sabnzbd: "SABnzbd"
        }
    }

    var placeholderURL: String {
        switch self {
        case .deluge: "http://10.0.0.5:8112"
        case .qbittorrent: "http://10.0.0.5:8080"
        case .sabnzbd: "http://10.0.0.5:8080"
        }
    }

    var hasHistory: Bool { self == .sabnzbd }
}

struct DownloadServerHeader: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var value = ""
}

struct DownloadServer: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id = UUID()
    var kind: DownloadServerKind = .deluge
    var label = ""
    var url = ""
    var username = ""
    // Deluge web password or qBittorrent password
    var password = ""
    // SABnzbd API key
    var apiKey = ""
    var headers: [DownloadServerHeader] = []
    // Results from private trackers may only be sent to clients with this turned on
    var allowsPrivate = false

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(DownloadServerKind.self, forKey: .kind)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? ""
        url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try values.decodeIfPresent(String.self, forKey: .password) ?? ""
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        headers = try values.decodeIfPresent([DownloadServerHeader].self, forKey: .headers) ?? []
        allowsPrivate = try values.decodeIfPresent(Bool.self, forKey: .allowsPrivate) ?? false
    }

    var displayName: String {
        label.trimmingCharacters(in: .whitespaces).isEmpty ? kind.label : label
    }

    var baseURL: URL? { downloadBaseURL(url) }

    var extraHeaders: [String: String] { downloadHeaderMap(headers) }

    var torrents: Bool { kind != .sabnzbd }
}

// Address and API key for Prowlarr or Seerr
struct ServiceServer: Codable, Equatable, Sendable {
    var url = ""
    var apiKey = ""
    var headers: [DownloadServerHeader] = []

    var baseURL: URL? { downloadBaseURL(url) }

    var extraHeaders: [String: String] { downloadHeaderMap(headers) }
}

func downloadBaseURL(_ url: String) -> URL? {
    var raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
    while raw.hasSuffix("/") { raw.removeLast() }
    guard !raw.isEmpty else { return nil }
    if !raw.contains("://") { raw = "http://" + raw }
    return URL(string: raw)
}

func downloadHeaderMap(_ headers: [DownloadServerHeader]) -> [String: String] {
    var map: [String: String] = [:]
    for header in headers where !header.name.isEmpty {
        map[header.name] = header.value
    }
    return map
}

// Servers are kept on this device only, separate from the synced Radarr/Sonarr instances.
@MainActor
@Observable
final class DownloadServers {
    static let shared = DownloadServers()

    private static let serversKey = "downloadServers"
    private static let selectedKey = "downloadServerSelected"
    private static let prowlarrKey = "prowlarrServer"
    private static let seerrKey = "seerrServer"

    var servers: [DownloadServer] {
        didSet { persist() }
    }

    var selectedId: DownloadServer.ID? {
        didSet { UserDefaults.live.set(selectedId?.uuidString, forKey: Self.selectedKey) }
    }

    var prowlarr: ServiceServer? {
        didSet { Self.persist(prowlarr, Self.prowlarrKey) }
    }

    var seerr: ServiceServer? {
        didSet { Self.persist(seerr, Self.seerrKey) }
    }

    init() {
        if let data = UserDefaults.live.data(forKey: Self.serversKey),
           let decoded = try? JSONDecoder().decode([DownloadServer].self, from: data) {
            servers = decoded
        } else {
            servers = []
        }

        selectedId = UserDefaults.live.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
        prowlarr = Self.loadService(Self.prowlarrKey)
        seerr = Self.loadService(Self.seerrKey)
    }

    private static func loadService(_ key: String) -> ServiceServer? {
        UserDefaults.live.data(forKey: key).flatMap { try? JSONDecoder().decode(ServiceServer.self, from: $0) }
    }

    private static func persist(_ server: ServiceServer?, _ key: String) {
        UserDefaults.live.set(server.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    var selected: DownloadServer? {
        servers.first { $0.id == selectedId } ?? servers.first
    }

    func save(_ server: DownloadServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }

        if selectedId == nil { selectedId = server.id }
    }

    func delete(_ server: DownloadServer) {
        servers.removeAll { $0.id == server.id }
        if selectedId == server.id { selectedId = servers.first?.id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.live.set(data, forKey: Self.serversKey)
        }
    }
}
