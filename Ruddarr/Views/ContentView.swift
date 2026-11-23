import SwiftUI

#if os(iOS)
struct ContentView: View {
    @State private var tabCustomization = TabViewCustomization()

    @Environment(AppSettings.self) private var settings
    @Environment(\.deviceType) private var deviceType

    var body: some View {
        TabView(selection: selectedTab) {
            Tab(calendar.label, systemImage: calendar.icon, value: calendar) {
                CalendarView()
            }

            Tab(movies.label, image: movies.icon, value: movies) {
                MoviesView()
            }

            Tab(discover.label, systemImage: discover.icon, value: discover) {
                DiscoverView()
            }

            Tab(series.label, image: series.icon, value: series) {
                SeriesView()
            }

            Tab(TabItem.downloads.label, systemImage: TabItem.downloads.icon, value: TabItem.downloads) {
                DownloadsTab()
            }
            .badge(Queue.shared.itemsWithIssues)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        .tabBarMinimizeBehavior(.never)
        .onAppear {
            UITabBarItem.appearance().badgeColor = UIColor(settings.theme.tint)
        }
        .task {
            await updateTelemetryAndWebhooks()
        }
        .onBecomeActive(perform: updateTelemetryAndWebhooks)
        .sheet(isPresented: dependencies.$router.showSettings) {
            SettingsView()
        }
        .onAppear { routeHiddenTab(dependencies.router.selectedTab) }
        .onChange(of: dependencies.router.selectedTab) { _, tab in routeHiddenTab(tab) }
        .displayToasts()
        .whatsNewSheet()
        .reportBugSheet()
        // .testFlightNotice()
    }

    var movies: TabItem { .movies }
    var series: TabItem { .series }
    var calendar: TabItem { .calendar }
    var discover: TabItem { .discover }

    var selectedTab: Binding<TabItem> {
        Binding<TabItem>(
            get: {
                dependencies.router.selectedTab
            },
            set: {
                let from = dependencies.router.selectedTab
                dependencies.router.selectedTab = $0
                handleTabChange(from, $0)
            }
        )
    }

    func updateTelemetryAndWebhooks() async {
        Telemetry.maybePing(with: settings)
        Notifications.maybeUpdateWebhooks(settings)
    }

    // Activity, History and Settings are no longer tabs: open them where they live now
    func routeHiddenTab(_ tab: TabItem) {
        switch tab {
        case .activity, .history:
            dependencies.router.downloadsSection = .activity
            dependencies.router.selectedTab = .downloads
        case .settings:
            dependencies.router.selectedTab = .discover
            dependencies.router.showSettings = true
        default:
            break
        }
    }

    func handleTabChange(_ from: TabItem, _ to: TabItem) {
        guard from == to else { return }

        switch to {
        case .calendar: NotificationCenter.default.post(name: .scrollToToday)
        default: break
        }
    }
}
#endif

#Preview {
    ContentView()
        .withAppState()
}
