import SwiftUI

struct DownloadServersView: View {
    @State private var store = DownloadServers.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.servers) { server in
                    NavigationLink {
                        DownloadServerEditView(server: server)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(server.displayName)
                            Text(server.allowsPrivate ? "\(server.kind.label), \(server.url), private trackers allowed" : "\(server.kind.label), \(server.url)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { store.delete(store.servers[index]) }
                }

                NavigationLink {
                    DownloadServerEditView(server: DownloadServer(), isNew: true)
                } label: {
                    Text("Add Download Client")
                }

                Section {
                    ForEach(ServiceKind.allCases) { service in
                        NavigationLink {
                            ServiceEditView(service: service)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(service.label)
                                Text(service.server(in: store)?.url ?? String(localized: "Not set up"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } header: {
                    Text("Indexers and Requests")
                }
            }
            .navigationTitle("Download Clients")
            .safeNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DownloadServerEditView: View {
    @State var server: DownloadServer
    var isNew = false

    @State private var isTesting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $server.kind) {
                    ForEach(DownloadServerKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }

                TextField("Name", text: $server.label, prompt: Text(server.kind.label))

                TextField("Address", text: $server.url, prompt: Text(server.kind.placeholderURL))
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
            }

            Section {
                switch server.kind {
                case .deluge:
                    SecureField("Web UI Password", text: $server.password)
                case .qbittorrent:
                    TextField("Username", text: $server.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Password", text: $server.password)
                case .sabnzbd:
                    TextField("API Key", text: $server.apiKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                }
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }

            if server.torrents {
                Section {
                    Toggle("Allow Private Trackers", isOn: $server.allowsPrivate)
                } footer: {
                    Text("Releases from private trackers found in Indexers can only be sent to clients with this turned on.")
                }
            }

            Section {
                ForEach($server.headers) { $header in
                    VStack {
                        TextField("Header name", text: $header.name)
                        TextField("Header value", text: $header.value)
                    }
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                }
                .onDelete { server.headers.remove(atOffsets: $0) }

                Button("Add Header") { server.headers.append(DownloadServerHeader()) }
            } header: {
                Text("Custom Headers")
            } footer: {
                Text("Only needed when the client sits behind a proxy that asks for extra headers.")
            }

            if !isNew {
                Section {
                    Button("Delete Download Client", role: .destructive) {
                        DownloadServers.shared.delete(server)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Download Client" : server.displayName)
        .safeNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isTesting {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(server.url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // Saves only after the client answers, so a typo shows up here instead of on the Downloads tab
    private func save() async {
        isTesting = true
        error = nil

        if let failure = await DownloadsModel.test(server) {
            error = failure
            isTesting = false
            return
        }

        DownloadServers.shared.save(server)
        isTesting = false
        dismiss()
    }
}
