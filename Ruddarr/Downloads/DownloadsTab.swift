import SwiftUI

// The Downloads tab: the download client, or the Radarr/Sonarr queue (Activity, with History inside it).
// A switch at the top of either screen flips between them.
struct DownloadsTab: View {
    var body: some View {
        switch dependencies.router.downloadsSection {
        case .downloads:
            DownloadsView()
                .displayToasts()
        case .activity:
            ActivityView()
        }
    }
}

struct DownloadsSectionPicker: View {
    var body: some View {
        Picker("Show", selection: dependencies.$router.downloadsSection) {
            ForEach(DownloadsSection.allCases) { section in
                Text(section.label).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}
