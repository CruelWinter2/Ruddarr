import SwiftUI

struct DownloadAddView: View {
    let model: DownloadsModel

    @State private var link = ""
    @State private var isSending = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $link, axis: .vertical)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                } footer: {
                    Text(footer)
                }

                #if os(iOS)
                    Section {
                        Button("Paste from Clipboard", systemImage: "doc.on.clipboard") {
                            link = UIPasteboard.general.string ?? link
                        }
                    }
                #endif
            }
            .navigationTitle("Add Download")
            .safeNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await send() } }
                            .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var placeholder: String {
        model.server?.kind == .sabnzbd ? String(localized: "NZB link") : String(localized: "Magnet or torrent link")
    }

    private var footer: String {
        model.server?.kind == .sabnzbd
            ? String(localized: "SABnzbd downloads the NZB file from this link.")
            : String(localized: "Paste a magnet link or a link to a .torrent file.")
    }

    private func send() async {
        isSending = true
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if await model.add(link: trimmed) {
            dependencies.toast.notice(text: String(localized: "Added"), icon: "checkmark.circle.fill")
            dismiss()
        }
        isSending = false
    }
}
