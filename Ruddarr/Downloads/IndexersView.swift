import SwiftUI

enum ProwlarrSort: String, CaseIterable, Identifiable {
    var id: Self { self }

    case seeders
    case newest
    case size

    var label: String {
        switch self {
        case .seeders: String(localized: "Most Seeders")
        case .newest: String(localized: "Newest")
        case .size: String(localized: "Largest")
        }
    }
}

extension ProwlarrResult {
    // Private and semi-private torrents must stay on clients marked for private trackers
    var needsPrivateClient: Bool { isTorrent && privacy != .public }
}

struct IndexersView: View {
    @State private var store = DownloadServers.shared
    @State private var query = ""
    @State private var category: ProwlarrCategory = .all
    @State private var sort: ProwlarrSort = .seeders
    @State private var results: [ProwlarrResult]?
    @State private var indexers: [ProwlarrIndexer] = []
    @State private var health: [String] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var selected: ProwlarrResult?
    @State private var showSettings = false

    var body: some View {
        Group {
            if store.prowlarr == nil {
                ContentUnavailableView {
                    Label("Prowlarr Not Set Up", systemImage: "magnifyingglass")
                } description: {
                    Text("Add your Prowlarr address and API key to search all your indexers from here.")
                } actions: {
                    Button("Set Up Prowlarr") { showSettings = true }
                }
            } else {
                list
            }
        }
        .navigationTitle("Indexers")
        .safeNavigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search all indexers"))
        .onSubmit(of: .search) { Task { await search() } }
        .onChange(of: query) { if query.isEmpty { results = nil } }
        .toolbar { toolbar }
        .task(id: store.prowlarr) { await loadIndexers() }
        .refreshable { await loadIndexers() }
        .sheet(isPresented: $showSettings) {
            NavigationStack { ServiceEditView(service: .prowlarr) }
        }
        .confirmationDialog(
            selected?.title ?? "",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible,
            presenting: selected
        ) { result in
            sendButtons(result)
            Button("Cancel", role: .cancel) {}
        } message: { result in
            if result.needsPrivateClient {
                Text("From a private tracker, so it can only go to download clients allowed for private trackers.")
            }
        }
    }

    private var list: some View {
        List {
            if let results {
                Section {
                    ForEach(sorted(results)) { result in
                        Button {
                            selected = result
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(result.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(result.title)
                            .accessibilityValue(result.summary)
                            .accessibilityHint(Text("Shows where to send this release"))
                        }
                    }
                } header: {
                    Text("\(results.count) results")
                }
            } else {
                if !health.isEmpty {
                    Section("Prowlarr Health") {
                        ForEach(health, id: \.self) { message in
                            Text(message).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                }

                Section("Indexers") {
                    ForEach(indexers) { indexer in
                        IndexerRow(indexer: indexer, client: client, reload: loadIndexers)
                    }
                }
            }
        }
        .overlay {
            if isSearching {
                ProgressView("Searching")
            } else if let error {
                ContentUnavailableView("Prowlarr Problem", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if results?.isEmpty == true {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    @ViewBuilder
    private func sendButtons(_ result: ProwlarrResult) -> some View {
        let targets = store.servers.filter {
            $0.torrents == result.isTorrent && (!result.needsPrivateClient || $0.allowsPrivate)
        }

        ForEach(targets) { server in
            Button("Send to \(server.displayName)") {
                Task { await send(result, to: server) }
            }
        }

        if !result.needsPrivateClient {
            Button("Send with Prowlarr") {
                Task { await grabWithProwlarr(result) }
            }
        }

        if targets.isEmpty, result.needsPrivateClient {
            Button("No Client Allowed for Private Trackers") {}
                .disabled(true)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Category", selection: $category) {
                    ForEach(ProwlarrCategory.allCases) { Text($0.label).tag($0) }
                }
                Picker("Sort", selection: $sort) {
                    ForEach(ProwlarrSort.allCases) { Text($0.label).tag($0) }
                }
                Button("Prowlarr Settings", systemImage: "gearshape") { showSettings = true }
            } label: {
                Label("Search Options", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private var client: ProwlarrClient? {
        store.prowlarr.flatMap { try? ProwlarrClient(server: $0) }
    }

    private func sorted(_ results: [ProwlarrResult]) -> [ProwlarrResult] {
        switch sort {
        case .seeders: results.sorted { ($0.seeders ?? -1, $0.size) > ($1.seeders ?? -1, $1.size) }
        case .newest: results.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        case .size: results.sorted { $0.size > $1.size }
        }
    }

    private func loadIndexers() async {
        guard let client else { return }
        do {
            indexers = try await client.indexers()
            health = (try? await client.health()) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard let client, !text.isEmpty else { return }

        isSearching = true
        error = nil
        do {
            if indexers.isEmpty { indexers = try await client.indexers() }
            results = try await client.search(text, category: category, indexers: indexers)
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    private func send(_ result: ProwlarrResult, to server: DownloadServer) async {
        guard let link = result.link else {
            dependencies.toast.error(text: String(localized: "This release has no download link."), icon: "exclamationmark.triangle.fill")
            return
        }

        do {
            try await makeDownloadClient(for: server).add(link: link)
            dependencies.toast.notice(text: String(localized: "Sent to \(server.displayName)"), icon: "checkmark.circle.fill")
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }

    private func grabWithProwlarr(_ result: ProwlarrResult) async {
        guard let client else { return }
        do {
            try await client.grab(result)
            dependencies.toast.notice(text: String(localized: "Sent with Prowlarr"), icon: "checkmark.circle.fill")
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }
}

struct IndexerRow: View {
    let indexer: ProwlarrIndexer
    let client: ProwlarrClient?
    let reload: () async -> Void

    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(indexer.name)
                    .foregroundStyle(indexer.enabled ? .primary : .secondary)
                if isTesting { ProgressView().controlSize(.small) }
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(indexer.disabledUntil == nil ? Color.secondary : Color.orange)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(indexer.name)
        .accessibilityValue(summary)
        .swipeActions(edge: .trailing) {
            Button("Test") { Task { await test() } }
                .tint(.blue)
        }
        .swipeActions(edge: .leading) {
            Button(indexer.enabled ? "Disable" : "Enable") { Task { await toggle() } }
                .tint(indexer.enabled ? .orange : .green)
        }
        .accessibilityActions {
            Button("Test") { Task { await test() } }
            Button(indexer.enabled ? "Disable" : "Enable") { Task { await toggle() } }
        }
    }

    private var summary: String {
        var parts = [indexer.protocolName == "usenet" ? "Usenet" : "Torrent", indexer.privacy.label]
        parts.append(indexer.enabled ? String(localized: "enabled") : String(localized: "disabled"))
        if let until = indexer.disabledUntil {
            parts.append(String(localized: "failing, retries \(until.formatted(.relative(presentation: .named)))"))
            if let failure = indexer.failure { parts.append(failure) }
        }
        return parts.joined(separator: ", ")
    }

    private func test() async {
        guard let client else { return }
        isTesting = true
        do {
            if let failure = try await client.test(indexer) {
                dependencies.toast.error(text: "\(indexer.name): \(failure)", icon: "exclamationmark.triangle.fill")
            } else {
                dependencies.toast.notice(text: String(localized: "\(indexer.name) works"), icon: "checkmark.circle.fill")
            }
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
        isTesting = false
        await reload()
    }

    private func toggle() async {
        guard let client else { return }
        do {
            try await client.setEnabled(indexer, !indexer.enabled)
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
        await reload()
    }
}
