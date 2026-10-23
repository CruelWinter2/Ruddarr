import SwiftUI

struct DownloadRow: View {
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.state.icon)
                    .foregroundStyle(tint)
                    .imageScale(.small)

                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }

            if !item.isHistory, item.state != .seeding {
                ProgressView(value: min(max(item.progress, 0), 1))
                    .tint(tint)
            }

            Text(item.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let message = item.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
        // VoiceOver reads the whole row as one item: name, then status
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let message = item.message else { return item.summary }
        return item.summary + ". " + message
    }

    private var tint: Color {
        switch item.state {
        case .downloading: .blue
        case .seeding, .completed: .green
        case .failed: .red
        case .paused, .queued: .secondary
        default: .orange
        }
    }
}
