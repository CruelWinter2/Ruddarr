import SwiftUI

// Tapping a poster: the backdrop, details and a Request button
struct DiscoverDetailView: View {
    let result: SeerrResult
    let client: SeerrClient?
    var onRequested: () -> Void

    @State private var status: SeerrMediaStatus
    @State private var isRequesting = false
    @Environment(\.dismiss) private var dismiss

    init(result: SeerrResult, client: SeerrClient?, onRequested: @escaping () -> Void) {
        self.result = result
        self.client = client
        self.onRequested = onRequested
        _status = State(initialValue: result.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    VStack(alignment: .leading, spacing: 16) {
                        requestButton

                        if let overview = result.overview {
                            Text(overview)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .scenePadding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            // A fixed-size frame with the image as an overlay, so a wide backdrop can't widen the page
            Color.clear
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .overlay {
                    AsyncImage(url: tmdbImage(result.backdropPath, size: "w780").flatMap(URL.init(string:))) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.secondary.opacity(0.2))
                    }
                }
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                }

            HStack(alignment: .bottom, spacing: 14) {
                CachedAsyncImage(.poster, tmdbImage(result.posterPath), placeholder: result.title)
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(3)

                    Text(facts)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))

                    Text(status.label)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(status.badgeColor, in: Capsule())
                }
                .padding(.bottom, 4)
            }
            .scenePadding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(height: 300, alignment: .bottom)
    }

    private var facts: String {
        var parts = [result.isMovie ? String(localized: "Movie") : String(localized: "Series")]
        if let year = result.year { parts.append(year) }
        if let rating = result.rating { parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1)))) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var requestButton: some View {
        if status == .unknown || status == .deleted || status == .partiallyAvailable {
            Button {
                Task { await request() }
            } label: {
                HStack {
                    if isRequesting { ProgressView().tint(.white) }
                    Text(result.isMovie ? "Request Movie" : "Request All Seasons")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting || client == nil)
        }
    }

    private func request() async {
        guard let client else { return }
        isRequesting = true
        do {
            try await client.request(result)
            status = .pending
            dependencies.toast.notice(text: String(localized: "Requested \(result.title)"), icon: "checkmark.circle.fill")
            onRequested()
        } catch {
            dependencies.toast.error(text: error.localizedDescription, icon: "exclamationmark.triangle.fill")
        }
        isRequesting = false
    }
}
