import Foundation
import CoreData

@MainActor
final class RSSViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var autoRefreshEnabled: Bool
    @Published var refreshInterval: TimeInterval
    @Published var isRefreshing = false
    @Published var lastRefreshMessage: String?

    let refreshIntervalOptions = RSSRefreshManager.refreshIntervalOptions

    private let refreshManager: RSSRefreshManager

    init(refreshManager: RSSRefreshManager? = nil) {
        self.refreshManager = refreshManager ?? .shared
        self.autoRefreshEnabled = refreshManager.autoRefreshEnabled
        self.refreshInterval = refreshManager.refreshInterval
    }

    func onAppear() {
        syncSettings()
        refreshManager.configureOnLaunch()
    }

    func syncSettings() {
        autoRefreshEnabled = refreshManager.autoRefreshEnabled
        refreshInterval = refreshManager.refreshInterval
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        refreshManager.setAutoRefreshEnabled(enabled)
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        refreshManager.setRefreshInterval(interval)
    }

    func refreshAllNow() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        await refreshManager.checkAndRefreshAll()
        lastRefreshMessage = "刷新检查完成：\(Date().formatted(.dateTime.hour().minute().second()))"
    }

    func refresh(source: RssSource) async {
        await refreshManager.refresh(source: source)
    }

    func statusText(for source: RssSource) -> String {
        let failureCount = Int(source.refreshFailureCount)

        if source.lastRefreshTime <= 0 {
            if failureCount > 0 {
                return "尚未成功刷新，失败 \(failureCount) 次"
            }
            return "尚未刷新"
        }

        let refreshDate = Date(timeIntervalSince1970: TimeInterval(source.lastRefreshTime) / 1000)
        let relative = refreshDate.formatted(.relative(presentation: .named))

        if failureCount > 0 {
            return "上次 \(relative)，失败 \(failureCount) 次"
        }
        return "上次 \(relative)"
    }
}
