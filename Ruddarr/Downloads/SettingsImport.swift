import Foundation

// One JSON file that sets up Radarr/Sonarr instances and download clients in one go:
//
// {
//   "instances": [
//     { "type": "sonarr", "label": "Sonarr", "url": "http://10.0.0.5:8989",
//       "alternateURL": "https://sonarr.example.com", "apiKey": "...", "headers": [] }
//   ],
//   "downloadClients": [
//     { "kind": "deluge", "label": "Deluge", "url": "http://10.0.0.5:8112", "password": "..." },
//     { "kind": "sabnzbd", "label": "SABnzbd", "url": "http://10.0.0.5:8080", "apiKey": "..." },
//     { "kind": "qbittorrent", "label": "qBittorrent", "url": "...", "username": "...", "password": "...",
//       "allowsPrivate": true }
//   ],
//   "prowlarr": { "url": "http://10.0.0.5:9696", "apiKey": "..." },
//   "seerr": { "url": "http://10.0.0.5:5055", "apiKey": "..." }
// }
//
// Entries matching an existing instance or client (same type and URL) are updated in place.
struct SettingsImportFile: Decodable {
    var instances: [ImportedInstance]?
    var downloadClients: [ImportedClient]?
    var prowlarr: ImportedService?
    var seerr: ImportedService?

    struct Header: Decodable {
        var name: String
        var value: String
    }

    struct ImportedInstance: Decodable {
        var type: String
        var label: String?
        var url: String
        var alternateURL: String?
        var apiKey: String
        var headers: [Header]?
    }

    struct ImportedClient: Decodable {
        var kind: String
        var label: String?
        var url: String
        var username: String?
        var password: String?
        var apiKey: String?
        var headers: [Header]?
        var allowsPrivate: Bool?
    }

    struct ImportedService: Decodable {
        var url: String
        var apiKey: String
        var headers: [Header]?
    }
}

struct SettingsImportResult {
    var instances = 0
    var clients = 0
    var services: [String] = []

    var summary: String {
        var text = String(localized: "Imported \(instances) instances and \(clients) download clients")
        if !services.isEmpty { text += ", " + services.joined(separator: ", ") }
        return text
    }
}

enum SettingsImportError: LocalizedError {
    case unreadable(String)
    case unknownKind(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            String(localized: "The file isn't a settings file the app can read. \(detail)")
        case .unknownKind(let kind):
            String(localized: "The file lists an unknown download client type: \(kind)")
        }
    }
}

@MainActor
enum SettingsImporter {
    static func importFile(at url: URL) throws -> SettingsImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SettingsImportError.unreadable(error.localizedDescription)
        }
        return try importData(data)
    }

    static func importData(_ data: Data) throws -> SettingsImportResult {
        let file: SettingsImportFile
        do {
            file = try JSONDecoder().decode(SettingsImportFile.self, from: data)
        } catch {
            throw SettingsImportError.unreadable(error.localizedDescription)
        }

        let clients = try (file.downloadClients ?? []).map(downloadServer)
        var result = SettingsImportResult()

        let settings = AppSettings.shared
        for entry in file.instances ?? [] {
            let type: InstanceType = entry.type.caseInsensitiveCompare("sonarr") == .orderedSame ? .sonarr : .radarr
            var instance = settings.instances.first {
                $0.type == type && $0.url.caseInsensitiveCompare(entry.url) == .orderedSame
            } ?? Instance()

            instance.type = type
            instance.url = entry.url
            instance.alternateURL = entry.alternateURL ?? ""
            instance.apiKey = entry.apiKey
            instance.label = entry.label ?? type.rawValue
            instance.headers = (entry.headers ?? []).map { InstanceHeader(name: $0.name, value: $0.value) }

            settings.saveInstance(instance)
            result.instances += 1
        }

        let store = DownloadServers.shared
        for var client in clients {
            if let existing = store.servers.first(where: {
                $0.kind == client.kind && $0.url.caseInsensitiveCompare(client.url) == .orderedSame
            }) {
                client.id = existing.id
            }

            store.save(client)
            result.clients += 1
        }

        for (kind, entry) in [(ServiceKind.prowlarr, file.prowlarr), (.seerr, file.seerr)] {
            guard let entry else { continue }
            var server = ServiceServer()
            server.url = entry.url
            server.apiKey = entry.apiKey
            server.headers = (entry.headers ?? []).map { DownloadServerHeader(name: $0.name, value: $0.value) }
            kind.save(server, in: store)
            result.services.append(kind.label)
        }

        return result
    }

    private static func downloadServer(_ entry: SettingsImportFile.ImportedClient) throws -> DownloadServer {
        guard let kind = DownloadServerKind.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(entry.kind) == .orderedSame
        }) else {
            throw SettingsImportError.unknownKind(entry.kind)
        }

        var server = DownloadServer()
        server.kind = kind
        server.label = entry.label ?? kind.label
        server.url = entry.url
        server.username = entry.username ?? ""
        server.password = entry.password ?? ""
        server.apiKey = entry.apiKey ?? ""
        server.headers = (entry.headers ?? []).map { DownloadServerHeader(name: $0.name, value: $0.value) }
        server.allowsPrivate = entry.allowsPrivate ?? false
        return server
    }
}
