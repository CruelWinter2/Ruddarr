import SwiftUI

struct RequestsView: View {
    @State private var store = DownloadServers.shared
    @State private var filter: SeerrFilter = .pending
    @State private var requests: [SeerrRequest] = []
    @State private var query = ""
    @State private var results: [SeerrResult]?
    @State private var isLoading = false
    @State private var error: String?
    @State private var requesting: SeerrResult?
    @State private var showSettings = false
    @State private var cached: (server: ServiceServer, client: SeerrClient)?

    var body: some View {
        Group {
            if store.seerr == nil {
                ContentUnavailableView {
                    Label("Seerr Not Set Up", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add your Seerr address and API key to manage requests from here.")
                } actions: {
                    Button("Set Up Seerr") { showSettings = true }
                }
            } else {
                list
            }
        }
        .navigationTitle("Requests")
        .safeNavigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search movies and series"))
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { if query.isEmpty { results = nil } }
        .task(id: "\(filter.rawValue)-\(store.seerr?.url ?? "")") { await load() }
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(SeerrFilter.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Seerr Settings", systemImage: "gearshape") { showSettings = true }
                } label: {
                    Label("Filter Requests", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { ServiceEditView(service: .seerr) }
        }
        .confirmationDialog(
            requesting.map { String(localized: "Request \($0.title)?") } ?? "",
            isPresented: Binding(get: { requesting != nil }, set: { if !$0 { requesting = nil } }),
            titleVisibility: .visible,
            presenting: requesting
        ) { result in
            Button(result.isMovie ? "Request Movie" : "Request All Seasons") {
                Task { await request(result) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var list: some View {
        List {
            if let results {
                Section {
                    ForEach(results) { result in
                        Button {
                            if result.canRequest { requesting = result }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(result.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let overview = result.overview {
                                    Text(overview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(result.title)
                            .accessibilityValue(result.summary)
                            .accessibilityHint(result.canRequest ? Text("Asks to request it") : Text(""))
                        }
                    }
                } header: {
                    Text("Search Results")
                }
            } else {
                Section {
                    ForEach(requests) { request in
                        row(request)
                    }
                } header: {
                    Text(filter.label)
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let error {
                ContentUnavailableView("Seerr Problem", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if results?.isEmpty == true {
                ContentUnavailableView.search(text: query)
            } else if results == nil, requests.isEmpty {
                ContentUnavailableView("No Requests", systemImage: "tray", description: Text("Nothing matches \(filter.label)."))
            }
        }
    }

    private func row(_ request: SeerrRequest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.title)
                .font(.subheadline.weight(.medium))
            Text(request.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(request.title)
        .accessibilityValue(request.summary)
        .swipeActions(edge: .leading) {
            if request.status == .pending {
                Button("Approve") { Task { await act { try await $0.approve(request) } } }
                    .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { Task { await act { try await $0.delete(request) } } }
            if request.status == .pending {
                Button("Decline") { Task { await act { try await $0.decline(request) } } }
                    .tint(.orange)
            }
        }
        .accessibilityActions {
            if request.status == .pending {
                Button("Approve") { Task { await act { try await $0.approve(request) } } }
                Button("Decline") { Task { await act { try await $0.decline(request) } } }
            }
            Button("Delete") { Task { await act { try await $0.delete(request) } } }
        }
    }

    // Kept between loads so looked-up titles stay cached
    private var client: SeerrClient? {
        guard let server = store.seerr else { return nil }
        if let cached, cached.server == server { return cached.client }
        guard let client = try? SeerrClient(server: server) else { return nil }
        Task { @MainActor in cached = (server, client) }
        return client
    }

    private func load() async {
        guard let client else { return }
        isLoading = requests.isEmpty
        do {
            requests = try await client.requests(filter)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard let client, !text.isEmpty else { return }
        isLoading = true
        do {
            results = try await client.search(text)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func request(_ result: SeerrResult) async {
        guard let client else { return }
        do {
            try await client.request(result)
            dependencies.toast.notice(text: String(localized: "Requested \(result.title)"), icon: "checkmark.circle.fill")
            await search()
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }

    private func act(_ action: (SeerrClient) async throws -> Void) async {
        guard let client else { return }
        do {
            try await action(client)
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
        await load()
    }
}
