import SwiftUI

struct EpisodeRow: View {
    var episode: Episode
    var status: QueueItemStatus?

    @Environment(AppSettings.self) private var settings
    @Environment(SonarrInstance.self) private var instance
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Text("\(episode.episodeNumber.formatted()).", comment: "Prefix for episode title (episode number)")
                        .foregroundStyle(.secondary)

                    Text(episode.titleLabel)
                        .lineLimit(1)
                        .italic(episode.title == nil)

                    if let finale = episode.finaleType {
                        Text(finale.label)
                            .font(.caption)
                            .foregroundStyle(settings.theme.tint)
                    }
                }

                HStack(spacing: 6) {
                    if let file = episodeFile {
                        Text(file.quality.quality.normalizedName)
                            .foregroundStyle(.secondary)
                    } else if let status {
                        Text(status.label)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(episode.stateLabel)
                            .foregroundStyle(episodeIsMissing ? .red : .secondary)
                    }

                    Bullet()

                    if episode.airingToday {
                        Text(episode.airDateTimeLabel)
                            .foregroundStyle(settings.theme.tint)
                    } else {
                        Text(episode.airDateLabel)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }.padding(.trailing)

            Spacer()

            if let status {
                QueueStatusIcon(status: status, color: colorScheme == .dark ? .lightGray : .darkGray)
            }

            monitorButton
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Episode \(episode.episodeNumber.formatted()), \(episode.titleLabel)"))
        .accessibilityValue(accessibilitySummary)
        .accessibilityAction(named: episodeMonitored ? Text("Unmonitor") : Text("Monitor")) {
            guard series.monitored else { return }
            Task { await toggleMonitor() }
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let finale = episode.finaleType { parts.append(finale.label) }
        if let file = episodeFile {
            parts.append(String(localized: "Downloaded, \(file.quality.quality.normalizedName)"))
        } else if let status {
            parts.append(status.label)
        } else {
            parts.append(episodeIsMissing ? String(localized: "Missing") : episode.stateLabel)
        }
        parts.append(episode.airingToday ? episode.airDateTimeLabel : episode.airDateLabel)
        parts.append(episodeMonitored ? String(localized: "Monitored") : String(localized: "Not monitored"))
        return parts.joined(separator: ", ")
    }

    private var episodeMonitored: Bool {
        instance.episodes.items.first(where: { $0.id == episode.id })?.monitored ?? episode.monitored
    }

    var series: Series {
        instance.series.byId(episode.seriesId) ?? Series.void
    }

    var season: Season? {
        series.seasonById(episode.seasonNumber)
    }

    var episodeFile: MediaFile? {
        episode.episodeFile
    }

    var episodeIsMissing: Bool {
        episode.isMissing && episode.monitored && series.monitored && season?.monitored == true
    }

    var monitorButton: some View {
        Button {
            Task { await toggleMonitor() }
        } label: {
            RowMonitorButton(
                monitored: episodeMonitored,
                loading: instance.episodes.isMonitoring == episode.id
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(instance.episodes.isMonitoring == 0)
        .disabled(!series.monitored)
    }

    func toggleMonitor() async {
        guard let index = instance.episodes.items.firstIndex(where: { $0.id == episode.id }) else {
            return
        }

        let original = instance.episodes.items[index].monitored
        instance.episodes.items[index].monitored = !original

        guard await instance.episodes.monitor([episode.id], !original) else {
            instance.episodes.items.revert(\.monitored, to: original, id: episode.id)

            return
        }

        dependencies.toast.show(!original ? .monitored : .unmonitored)
    }
}

#Preview {
    let series: [Series] = PreviewData.load(name: "series")
    let item = series.first(where: { $0.id == 67 }) ?? series[0] // 15

    dependencies.router.selectedTab = .series

    dependencies.router.seriesPath.append(
        SeriesPath.series(item.id)
    )

    dependencies.router.seriesPath.append(
        SeriesPath.season(item.id, 2)
    )

    return ContentView()
        .withSonarrInstance(series: series)
        .withAppState()
}
