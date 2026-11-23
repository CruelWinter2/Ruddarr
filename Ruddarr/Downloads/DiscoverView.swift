import SwiftUI

// The center tab: Seerr's home page in poster rows, with search and requests.
struct DiscoverView: View {
    @State private var store = DownloadServers.shared
    @State private var client: SeerrClient?
    @State private var rows: [SeerrDiscoverRow: [SeerrResult]] = [:]
    @State private var recent: [SeerrRequest] = []
    @State private var query = ""
    @State private var results: [SeerrResult]?
    @State private var isSearching = false
    @State private var error: String?
    @State private var selected: SeerrResult?
    @State private var showSeerrSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if store.seerr == nil {
                    ContentUnavailableView {
                        Label("Seerr Not Set Up", systemImage: "sparkle.magnifyingglass")
                    } description: {
                        Text("Add your Seerr address and API key to discover and request movies and series.")
                    } actions: {
                        Button("Set Up Seerr") { showSeerrSettings = true }
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Discover")
            .safeNavigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: Text("Search movies and series"))
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { if query.isEmpty { results = nil } }
            .task(id: store.seerr?.url ?? "") { await load() }
            .refreshable { await load() }
            .toolbar { toolbar }
            .sheet(isPresented: $showSeerrSettings) {
                NavigationStack { ServiceEditView(service: .seerr) }
            }
            .sheet(item: $selected) { result in
                DiscoverDetailView(result: result, client: client) {
                    Task { await load() }
                }
                .presentationDetents([.large])
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Settings", systemImage: "gear") {
                dependencies.router.showSettings = true
            }
        }

        if store.seerr != nil {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    RequestsView()
                } label: {
                    Label("Requests", systemImage: "tray.full")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            if let results {
                searchResults(results)
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if let error {
                        ContentUnavailableView("Seerr Problem", systemImage: "exclamationmark.triangle", description: Text(error))
                    }

                    if !recent.isEmpty {
                        recentRequests
                    }

                    ForEach(SeerrDiscoverRow.allCases) { row in
                        if let items = rows[row], !items.isEmpty {
                            posterRow(row.label, items)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            } else if rows.isEmpty, error == nil, results == nil {
                ProgressView()
            } else if results?.isEmpty == true {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func searchResults(_ results: [SeerrResult]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
            ForEach(results) { result in
                Button { selected = result } label: {
                    PosterCard(title: result.title, poster: result.posterPath, status: result.status, width: nil)
                }
                .buttonStyle(.plain)
            }
        }
        .scenePadding(.horizontal)
        .padding(.vertical)
    }

    private var recentRequests: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                RequestsView()
            } label: {
                HStack(spacing: 4) {
                    Text("Recent Requests").font(.title3.bold())
                    Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .scenePadding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(recent) { request in
                        NavigationLink {
                            RequestsView()
                        } label: {
                            PosterCard(
                                title: request.title,
                                poster: request.posterPath,
                                status: request.status == .pending ? .pending : (request.mediaStatus ?? .pending),
                                width: 110
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scenePadding(.horizontal)
            }
        }
    }

    private func posterRow(_ label: String, _ items: [SeerrResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.title3.bold())
                .scenePadding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { result in
                        Button { selected = result } label: {
                            PosterCard(title: result.title, poster: result.posterPath, status: result.status, width: 110)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scenePadding(.horizontal)
            }
        }
    }

    private func makeClient() -> SeerrClient? {
        guard let server = store.seerr else { return nil }
        if client == nil { client = try? SeerrClient(server: server) }
        return client
    }

    private func load() async {
        client = nil
        guard let client = makeClient() else { return }

        await withTaskGroup(of: (SeerrDiscoverRow, [SeerrResult]?).self) { group in
            for row in SeerrDiscoverRow.allCases {
                group.addTask { (row, try? await client.discover(row)) }
            }
            for await (row, items) in group {
                if let items { rows[row] = items }
            }
        }

        do {
            recent = try await client.requests(.all, take: 12)
            error = nil
        } catch {
            self.error = rows.isEmpty ? error.localizedDescription : nil
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard let client = makeClient(), !text.isEmpty else { return }
        isSearching = true
        do {
            results = try await client.search(text)
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
        isSearching = false
    }
}

// A poster with its Seerr status in the corner, like Seerr's web page
struct PosterCard: View {
    let title: String
    let poster: String?
    let status: SeerrMediaStatus
    let width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(.poster, tmdbImage(poster), placeholder: title)
                .aspectRatio(2 / 3, contentMode: .fill)
                .frame(width: width)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topTrailing) { badge }
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08))
                }

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(status.label)
    }

    @ViewBuilder
    private var badge: some View {
        if let symbol = status.badgeSymbol {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(5)
                .background(status.badgeColor, in: Circle())
                .padding(6)
        }
    }
}

extension SeerrMediaStatus {
    var badgeSymbol: String? {
        switch self {
        case .available: "checkmark"
        case .partiallyAvailable: "minus"
        case .pending: "clock"
        case .processing: "arrow.down"
        case .unknown, .deleted: nil
        }
    }

    var badgeColor: Color {
        switch self {
        case .available, .partiallyAvailable: .green
        case .pending: .orange
        case .processing: .indigo
        case .unknown, .deleted: .gray
        }
    }
}
