import Foundation
import Observation

@MainActor
@Observable
final class DownloadsModel {
    static let shared = DownloadsModel()

    let store = DownloadServers.shared

    private(set) var items: [DownloadItem] = []
    private(set) var history: [DownloadItem] = []
    private(set) var stats = DownloadStats()
    private(set) var error: String?
    private(set) var hasLoaded = false

    @ObservationIgnored private var clients: [DownloadServer.ID: (DownloadServer, any DownloadClient)] = [:]

    var server: DownloadServer? { store.selected }

    func select(_ server: DownloadServer) {
        guard store.selectedId != server.id else { return }
        store.selectedId = server.id
        items = []
        history = []
        stats = DownloadStats()
        error = nil
        hasLoaded = false
    }

    func refresh() async {
        guard let server else { return }

        do {
            let snapshot = try await client(for: server).fetch()
            // Ignore a late answer from a server the user switched away from
            guard store.selected?.id == server.id else { return }
            items = snapshot.items
            history = snapshot.history
            stats = snapshot.stats
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard store.selected?.id == server.id else { return }
            self.error = error.localizedDescription
        }

        hasLoaded = true
    }

    func pause(_ items: [DownloadItem]) async {
        await perform { try await $0.pause(items) }
    }

    func resume(_ items: [DownloadItem]) async {
        await perform { try await $0.resume(items) }
    }

    func remove(_ items: [DownloadItem], deleteData: Bool) async {
        await perform { try await $0.remove(items, deleteData: deleteData) }
    }

    func pauseAll() async {
        await perform { try await $0.pauseAll() }
    }

    func resumeAll() async {
        await perform { try await $0.resumeAll() }
    }

    func setDownloadLimit(_ limit: Int64?) async {
        await perform { try await $0.setDownloadLimit(limit) }
    }

    func add(link: String) async -> Bool {
        await perform { try await $0.add(link: link) }
    }

    // Connects with unsaved settings so the edit form can check them before saving.
    static func test(_ server: DownloadServer) async -> String? {
        do {
            _ = try await makeDownloadClient(for: server).fetch()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    private func perform(_ action: (any DownloadClient) async throws -> Void) async -> Bool {
        guard let server else { return false }

        do {
            try await action(try client(for: server))
            await refresh()
            return true
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
            return false
        }
    }

    private func client(for server: DownloadServer) throws -> any DownloadClient {
        // Reuse the client (and its login) until the server's settings change
        if case let (saved, client)? = clients[server.id], saved == server {
            return client
        }

        let client = try makeDownloadClient(for: server)
        clients[server.id] = (server, client)
        return client
    }
}
