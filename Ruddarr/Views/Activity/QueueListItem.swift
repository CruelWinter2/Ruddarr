import SwiftUI
import Combine

struct QueueListItem: View {
    var item: QueueItem

    @State private var time = Date()
    private let timer = Timer.publish(every: 1, tolerance: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.titleLabel)
                .font(.headline.monospacedDigit())
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                Text(item.statusLabel)

                if item.trackedDownloadState == .downloading {
                    Bullet()
                    Text(item.progressLabel)
                        .monospacedDigit()

                    if let remaining = item.remainingLabel {
                        Bullet()
                        Text(remaining)
                            .monospacedDigit()
                            .id(time)
                    }
                }

                if item.hasIssue {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityTile(item.titleLabel, accessibilitySummary)
        .onReceive(timer) { _ in
            if item.trackedDownloadState == .downloading {
                withAnimation {
                    time = Date()
                }
            }
        }
    }
}

extension QueueListItem {
    private var accessibilitySummary: String {
        var parts = [item.statusLabel]
        if item.trackedDownloadState == .downloading {
            parts.append(item.progressLabel)
            if let remaining = item.remainingLabel { parts.append(remaining) }
        }
        if item.hasIssue { parts.append(String(localized: "Needs attention")) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    dependencies.router.selectedTab = .activity

    return ContentView()
        .withAppState()
}
