import SwiftUI

enum ServiceKind: String, CaseIterable, Identifiable {
    var id: Self { self }

    case prowlarr
    case seerr

    var label: String {
        switch self {
        case .prowlarr: "Prowlarr"
        case .seerr: "Seerr"
        }
    }

    var placeholder: String {
        switch self {
        case .prowlarr: "http://10.0.0.5:9696"
        case .seerr: "http://10.0.0.5:5055"
        }
    }

    var keyHelp: String {
        switch self {
        case .prowlarr: String(localized: "The API key is in Prowlarr under Settings, General.")
        case .seerr: String(localized: "The API key is in Seerr under Settings, General.")
        }
    }

    @MainActor
    func server(in store: DownloadServers) -> ServiceServer? {
        switch self {
        case .prowlarr: store.prowlarr
        case .seerr: store.seerr
        }
    }

    @MainActor
    func save(_ server: ServiceServer?, in store: DownloadServers) {
        switch self {
        case .prowlarr: store.prowlarr = server
        case .seerr: store.seerr = server
        }
    }

    // Answers with the problem, or nil when the service responds
    func test(_ server: ServiceServer) async -> String? {
        do {
            switch self {
            case .prowlarr: _ = try await ProwlarrClient(server: server).indexers()
            case .seerr: try await SeerrClient(server: server).check()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

struct ServiceEditView: View {
    let service: ServiceKind

    @State private var server = ServiceServer()
    @State private var isTesting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var store: DownloadServers { .shared }

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $server.url, prompt: Text(verbatim: service.placeholder))
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                TextField("API Key", text: $server.apiKey)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text(service.keyHelp)
                }
            }

            Section("Custom Headers") {
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
            }

            if service.server(in: store) != nil {
                Section {
                    Button("Remove \(service.label)", role: .destructive) {
                        service.save(nil, in: store)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(service.label)
        .safeNavigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let saved = service.server(in: store) { server = saved }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isTesting {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(server.url.isEmpty || server.apiKey.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isTesting = true
        error = await service.test(server)
        isTesting = false

        if error == nil {
            service.save(server, in: store)
            dismiss()
        }
    }
}
