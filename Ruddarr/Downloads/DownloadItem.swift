import Foundation

enum DownloadState: Equatable, Sendable {
    case downloading
    case seeding
    case paused
    case queued
    case checking
    case processing
    case completed
    case failed
    case other(String)

    var label: String {
        switch self {
        case .downloading: String(localized: "Downloading", comment: "Download state")
        case .seeding: String(localized: "Seeding", comment: "Download state")
        case .paused: String(localized: "Paused", comment: "Download state")
        case .queued: String(localized: "Queued", comment: "Download state")
        case .checking: String(localized: "Checking", comment: "Download state")
        case .processing: String(localized: "Processing", comment: "Download state")
        case .completed: String(localized: "Completed", comment: "Download state")
        case .failed: String(localized: "Failed", comment: "Download state")
        case .other(let raw): raw
        }
    }

    var icon: String {
        switch self {
        case .downloading: "arrow.down.circle.fill"
        case .seeding: "arrow.up.circle.fill"
        case .paused: "pause.circle.fill"
        case .queued: "clock.fill"
        case .checking, .processing: "gearshape.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .other: "questionmark.circle.fill"
        }
    }

    var isPaused: Bool { self == .paused }
}

struct DownloadItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var state: DownloadState
    var progress: Double = 0
    var size: Int64 = 0
    var downloadRate: Int64 = 0
    var uploadRate: Int64 = 0
    var eta: Int?
    var ratio: Double?
    var category: String?
    var message: String?
    var date: Date?
    var isHistory = false

    var percent: Int { Int((progress * 100).rounded(.down)) }

    // One line for VoiceOver and the row subtitle, in reading order.
    var summary: String {
        var parts: [String] = [state.label]

        if !isHistory, state != .seeding, state != .completed {
            parts.append(String(localized: "\(percent)% of \(formatBytes(size))", comment: "Download progress"))
        } else if size > 0 {
            parts.append(formatBytes(size))
        }

        if downloadRate > 0 {
            parts.append(String(localized: "down \(formatBytes(downloadRate))/s", comment: "Download speed"))
        }

        if uploadRate > 0 {
            parts.append(String(localized: "up \(formatBytes(uploadRate))/s", comment: "Upload speed"))
        }

        if let eta, eta > 0, state == .downloading {
            parts.append(formatDownloadEta(eta))
        }

        if let ratio, state == .seeding || state == .paused, size > 0, progress >= 1 {
            parts.append(String(localized: "ratio \(ratio.formatted(.number.precision(.fractionLength(2))))", comment: "Seed ratio"))
        }

        return parts.joined(separator: ", ")
    }
}

struct DownloadStats: Equatable, Sendable {
    var downloadRate: Int64 = 0
    var uploadRate: Int64 = 0
    // Bytes per second, nil when unlimited
    var downloadLimit: Int64?
    // SABnzbd only: the whole queue is paused
    var isPaused = false
}

struct DownloadSnapshot: Sendable {
    var items: [DownloadItem] = []
    var history: [DownloadItem] = []
    var stats = DownloadStats()
}

func formatDownloadEta(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : (seconds >= 3_600 ? [.hour, .minute] : [.minute, .second])
    let value = formatter.string(from: TimeInterval(seconds)) ?? ""
    return String(localized: "\(value) left", comment: "Time remaining for a download")
}
