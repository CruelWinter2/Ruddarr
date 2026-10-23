import SwiftUI

struct CalendarMovie: View {
    var date: Date
    var movie: Movie
    var status: QueueItemStatus?
    var open: (CalendarSelection) -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center) {
                    Text(movie.title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(shouldFade ? .secondary : .primary)

                    Spacer()

                    statusIcon
                        .font(.subheadline)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }

                if let type = movie.releaseType(for: date) {
                    Text(type)
                        .font(.caption)
                        .foregroundStyle(settings.theme.tint)
                }
            }
        }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .opacity(shouldFade ? 0.5 : 1)
            .background(.card.opacity(shouldFade ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture {
                open(.movie(movie))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(movie.title)
            .accessibilityValue(
                [movie.releaseType(for: date), statusText].compactMap { $0 }.joined(separator: ", ")
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(.movie(movie)) }
    }

    var statusText: String? {
        if let status { return status.label }
        if movie.isDownloaded { return String(localized: "Downloaded") }
        if !movie.monitored { return String(localized: "Not monitored") }
        if movie.isWaiting { return String(localized: "Not released yet") }
        return String(localized: "Missing")
    }

    var shouldFade: Bool {
        !movie.monitored && !movie.isDownloaded
    }

    @ViewBuilder
    var statusIcon: some View {
        if let status {
            QueueStatusIcon(status: status)
        } else if movie.isDownloaded {
            Image(systemName: "checkmark").symbolVariant(.circle.fill)
        } else if !movie.monitored {
            Image(systemName: "bookmark").symbolVariant(.slash)
        } else if movie.isWaiting {
            Image(systemName: "clock")
        } else if movie.monitored {
            Image(systemName: "xmark").symbolVariant(.circle)
        }
    }
}

struct CalendarEpisode: View {
    var episode: Episode
    var status: QueueItemStatus?
    var open: (CalendarSelection) -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(episode.series?.title ?? "Unknown")
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(shouldFade ? .secondary : .primary)

                Spacer()

                if let airDate = episode.airDateUtc {
                    Text(airDate.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 6) {
                Text(episode.episodeLabel)

                if let title = episode.title {
                    Bullet()
                    Text(title).lineLimit(1)
                }

                Spacer()

                statusIcon
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .foregroundStyle(.secondary)
            .font(.subheadline)

            tag
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .opacity(shouldFade ? 0.5 : 1)
        .background(.card.opacity(shouldFade ? 0.6 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            open(.episode(episode))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(episode.series?.title ?? String(localized: "Unknown"))
        .accessibilityValue(episodeSummary)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(.episode(episode)) }
    }

    var episodeSummary: String {
        var parts = [episode.episodeLabel]
        if let title = episode.title { parts.append(title) }
        if let airDate = episode.airDateUtc { parts.append(airDate.formatted(date: .omitted, time: .shortened)) }
        if episode.isGroupedInCalendar, let hidden = episode.calendarGroupCount {
            parts.append(String(localized: "+\(hidden - 1) more..."))
        } else if episode.isSpecial {
            parts.append(episode.specialLabel)
        } else if let finale = episode.finaleType {
            parts.append(finale.label)
        } else if episode.isPremiere {
            parts.append(episode.premiereLabel)
        }
        if let status {
            parts.append(status.label)
        } else if episode.isDownloaded {
            parts.append(String(localized: "Downloaded"))
        } else if !episode.monitored || episode.series?.monitored == false {
            parts.append(String(localized: "Not monitored"))
        } else if !episode.hasAired {
            parts.append(String(localized: "Not aired yet"))
        } else {
            parts.append(String(localized: "Missing"))
        }
        return parts.joined(separator: ", ")
    }

    var shouldFade: Bool {
        !episode.isDownloaded
            && (!episode.monitored || episode.series?.monitored == false)
    }

    @ViewBuilder
    var tag: some View {
        if episode.isGroupedInCalendar, let hidden = episode.calendarGroupCount {
            Text(String(localized: "+\(hidden - 1) more..."))
                .font(.caption)
                .foregroundStyle(settings.theme.tint)
        } else if episode.isSpecial {
            Text(episode.specialLabel)
                .font(.caption)
                .foregroundStyle(settings.theme.tint)
        } else if let finale = episode.finaleType {
            Text(finale.label)
                .font(.caption)
                .foregroundStyle(settings.theme.tint)
        } else if episode.isPremiere {
            Text(episode.premiereLabel)
                .font(.caption)
                .foregroundStyle(settings.theme.tint)
        }
    }

    @ViewBuilder
    var statusIcon: some View {
        if let status {
            QueueStatusIcon(status: status)
        } else if episode.isDownloaded {
            Image(systemName: "checkmark").symbolVariant(.circle.fill)
        } else if !episode.monitored || episode.series?.monitored == false {
            Image(systemName: "bookmark").symbolVariant(.slash)
        } else if !episode.hasAired {
            Image(systemName: "clock")
        } else if episode.monitored {
            Image(systemName: "xmark").symbolVariant(.circle)
        }
    }
}

enum CalendarMediaType: CaseIterable {
    case all
    case movies
    case series

    var label: some View {
        switch self {
        case .all: Label(String(localized: "Everything", comment: "Movies and series filter option"), systemImage: "rectangle.stack")
        case .movies: Label(String(localized: "Movies"), systemImage: "film")
        case .series: Label(String(localized: "Series"), systemImage: "tv")
        }
    }
}

#Preview {
    dependencies.router.selectedTab = .calendar

    return ContentView()
        .withAppState()
}
