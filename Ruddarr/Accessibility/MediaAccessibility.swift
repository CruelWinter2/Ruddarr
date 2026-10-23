import SwiftUI

// What VoiceOver says for a movie or series tile, after its title.
extension Movie {
    var accessibilitySummary: String {
        var parts = [yearLabel]

        if exists {
            if isDownloaded {
                parts.append(String(localized: "Downloaded"))
            } else if isWaiting {
                parts.append(String(localized: "Not released yet"))
            } else if monitored {
                parts.append(String(localized: "Missing"))
            }
            parts.append(monitored ? String(localized: "Monitored") : String(localized: "Not monitored"))
        } else {
            parts.append(String(localized: "Not in library"))
        }

        return parts.joined(separator: ", ")
    }
}

extension Series {
    var accessibilitySummary: String {
        var parts = [yearLabel, status.label]

        if exists {
            if episodeCount > 0 {
                parts.append(String(localized: "\(episodeFileCount) of \(episodeCount) episodes"))
            }
            parts.append(monitored ? String(localized: "Monitored") : String(localized: "Not monitored"))
        } else {
            parts.append(String(localized: "Not in library"))
        }

        return parts.joined(separator: ", ")
    }
}

extension View {
    // Reads the whole tile as one item instead of its artwork and icons
    func accessibilityTile(_ title: String, _ summary: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(summary)
    }
}

// Spoken details for a release row, in the order a person would want them.
protocol SpokenRelease {
    var rejected: Bool { get }
    var qualityLabel: String { get }
    var sizeLabel: String { get }
    var ageLabel: String { get }
    var isUsenet: Bool { get }
    var seeders: Int? { get }
    var leechers: Int? { get }
    var languageLabel: String { get }
    var indexerLabel: String { get }
    var flagLabels: [String] { get }
    var formatLabels: [String] { get }
}

extension SpokenRelease {
    var accessibilitySummary: String {
        var parts: [String] = []
        if rejected { parts.append(String(localized: "Rejected")) }
        parts += [qualityLabel, sizeLabel, ageLabel]
        if isUsenet {
            parts.append(String(localized: "Usenet"))
        } else {
            parts.append(String(localized: "\(seeders ?? 0) seeders, \(leechers ?? 0) leechers"))
        }
        parts += [languageLabel, indexerLabel]
        parts += flagLabels
        if !formatLabels.isEmpty { parts.append(formatLabels.joined(separator: ", ")) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension MovieRelease: SpokenRelease {}
extension SeriesRelease: SpokenRelease {}
