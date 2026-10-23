import SwiftUI
import UniformTypeIdentifiers

struct DownloadsView: View {
    @State private var model = DownloadsModel.shared
    @State private var showServers = false
    @State private var showAdd = false
    @State private var showImporter = false
    @State private var showImportChoice = false
    @State private var removing: DownloadItem?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if model.store.servers.isEmpty {
                    noServers
                } else {
                    list
                }
            }
            .navigationTitle(model.server?.displayName ?? String(localized: "Downloads"))
            .safeNavigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task(id: pollKey) { await poll() }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showServers) {
                DownloadServersView()
            }
            .sheet(isPresented: $showAdd) {
                DownloadAddView(model: model)
            }
            .confirmationDialog(
                removing?.name ?? "",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { item in
                Button("Remove and Delete Files", role: .destructive) {
                    Task { await model.remove([item], deleteData: true) }
                }
                Button("Remove, Keep Files") {
                    Task { await model.remove([item], deleteData: false) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .confirmationDialog("Import Settings", isPresented: $showImportChoice, titleVisibility: .visible) {
            Button("From a File") { openImporter() }
            #if os(iOS)
                Button("From the Clipboard") { importClipboard() }
            #endif
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose where the Ruddarr settings file is. You can also share the file to Ruddarr from the Files app.")
        }
        #if os(macOS)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importSettings(result)
            }
        #endif
    }

    // Lets the menu finish closing before the file picker opens
    private func openImporter() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            #if os(iOS)
                DocumentPicker.shared.pick([.json]) { url in
                    importSettings(.success(url))
                }
            #else
                showImporter = true
            #endif
        }
    }

    // Restarts polling when the server changes or the app comes back to the foreground
    private var pollKey: String {
        "\(model.server?.id.uuidString ?? "none")-\(scenePhase == .active)"
    }

    private func poll() async {
        guard scenePhase == .active, model.server != nil else { return }

        while !Task.isCancelled {
            await model.refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private var list: some View {
        List {
            if model.server != nil {
                Section {
                    speedSummary
                }
            }

            Section {
                ForEach(model.items) { item in
                    row(item)
                }
            } header: {
                if !model.items.isEmpty {
                    Text(model.server?.kind == .sabnzbd ? "Queue" : "Torrents")
                }
            }

            if !model.history.isEmpty {
                Section("History") {
                    ForEach(model.history) { item in
                        row(item)
                    }
                }
            }
        }
        .overlay {
            if let error = model.error, model.items.isEmpty {
                ContentUnavailableView {
                    Label("Can't Reach \(model.server?.displayName ?? "")", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                    Button("Edit Download Clients") { showServers = true }
                }
            } else if model.hasLoaded, model.items.isEmpty, model.history.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: "arrow.down.circle", description: Text("Nothing is downloading right now."))
            } else if !model.hasLoaded {
                ProgressView()
            }
        }
    }

    private var speedSummary: some View {
        let stats = model.stats
        var parts = [
            String(localized: "Down \(formatBytes(stats.downloadRate))/s"),
        ]
        if model.server?.kind != .sabnzbd {
            parts.append(String(localized: "Up \(formatBytes(stats.uploadRate))/s"))
        }
        if let limit = stats.downloadLimit {
            parts.append(String(localized: "limit \(formatBytes(limit))/s"))
        }
        if stats.isPaused {
            parts.insert(String(localized: "Queue paused"), at: 0)
        }
        if let error = model.error, !model.items.isEmpty {
            parts.append(String(localized: "last update failed: \(error)"))
        }

        return Text(parts.joined(separator: ", "))
            .font(.footnote)
            .foregroundStyle(stats.isPaused ? .orange : .secondary)
    }

    private func row(_ item: DownloadItem) -> some View {
        DownloadRow(item: item)
            .swipeActions(edge: .trailing) {
                Button("Remove", systemImage: "trash", role: .destructive) { removing = item }
            }
            .swipeActions(edge: .leading) {
                if !item.isHistory { toggleButton(item) }
            }
            .contextMenu {
                if !item.isHistory { toggleButton(item) }
                Button("Remove", systemImage: "trash", role: .destructive) { removing = item }
            }
            .accessibilityActions {
                if !item.isHistory { toggleButton(item) }
                Button("Remove") { removing = item }
            }
    }

    @ViewBuilder
    private func toggleButton(_ item: DownloadItem) -> some View {
        if item.state.isPaused {
            Button("Resume", systemImage: "play.fill") { Task { await model.resume([item]) } }
                .tint(.green)
        } else {
            Button("Pause", systemImage: "pause.fill") { Task { await model.pause([item]) } }
                .tint(.orange)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Download", systemImage: "plus") { showAdd = true }
                .disabled(model.server == nil)
        }

        ToolbarItem(placement: .primaryAction) {
            NavigationLink {
                IndexersView()
            } label: {
                Label("Search Indexers", systemImage: "magnifyingglass")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            NavigationLink {
                RequestsView()
            } label: {
                Label("Requests", systemImage: "person.crop.circle.badge.plus")
            }
        }

        ToolbarItem(placement: .navigation) {
            Menu {
                if model.store.servers.count > 1 {
                    Section("Download Client") {
                        ForEach(model.store.servers) { server in
                            Button {
                                model.select(server)
                            } label: {
                                if server.id == model.server?.id {
                                    Label(server.displayName, systemImage: "checkmark")
                                } else {
                                    Text(server.displayName)
                                }
                            }
                        }
                    }
                }

                if model.server != nil {
                    Section {
                        Button("Pause All", systemImage: "pause.circle") { Task { await model.pauseAll() } }
                        Button("Resume All", systemImage: "play.circle") { Task { await model.resumeAll() } }
                        speedLimitMenu
                    }
                }

                Section {
                    Button("Edit Download Clients", systemImage: "server.rack") { showServers = true }
                    Button("Import Settings", systemImage: "square.and.arrow.down") { showImportChoice = true }
                }
            } label: {
                Label("Download Clients", systemImage: "ellipsis.circle")
            }
        }
    }

    private var speedLimitMenu: some View {
        Menu {
            Button("Unlimited") { Task { await model.setDownloadLimit(nil) } }
            ForEach([1, 5, 10, 25, 50], id: \.self) { mebibytes in
                Button("\(mebibytes) MB/s") {
                    Task { await model.setDownloadLimit(Int64(mebibytes) * 1_048_576) }
                }
            }
        } label: {
            Label("Download Speed Limit", systemImage: "speedometer")
        }
    }

    private var noServers: some View {
        ContentUnavailableView {
            Label("No Download Clients", systemImage: "arrow.down.circle")
        } description: {
            Text("Add Deluge, qBittorrent or SABnzbd to see and control your downloads here.")
        } actions: {
            Button("Add Download Client") { showServers = true }
            Button("Import Settings") { showImportChoice = true }
            NavigationLink("Search Indexers") { IndexersView() }
            NavigationLink("Requests") { RequestsView() }
        }
    }

    #if os(iOS)
        private func importClipboard() {
            guard let text = UIPasteboard.general.string, !text.isEmpty else {
                dependencies.toast.error(text: String(localized: "The clipboard is empty."), icon: "exclamationmark.triangle.fill")
                return
            }
            finishImport { try SettingsImporter.importData(Data(text.utf8)) }
        }
    #endif

    private func finishImport(_ load: () throws -> SettingsImportResult) {
        do {
            let imported = try load()
            dependencies.toast.notice(text: imported.summary, icon: "checkmark.circle.fill")
            Task { await model.refresh() }
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
    }

    private func importSettings(_ result: Result<URL, any Error>) {
        finishImport { try SettingsImporter.importFile(at: result.get()) }
    }
}
