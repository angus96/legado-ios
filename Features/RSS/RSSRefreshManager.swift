import Foundation
import CoreData
import BackgroundTasks
import UIKit

@MainActor
final class RSSRefreshManager: NSObject {
    static let shared = RSSRefreshManager()

    static let taskIdentifier = "com.chrn11.legado.rssrefresh"
    static let autoRefreshEnabledKey = "rss.autoRefreshEnabled"
    static let refreshIntervalKey = "rss.refreshInterval"

    struct RefreshIntervalOption: Identifiable, Hashable {
        let seconds: TimeInterval
        let title: String

        var id: Int { Int(seconds) }
    }

    static let refreshIntervalOptions: [RefreshIntervalOption] = [
        RefreshIntervalOption(seconds: 5 * 60, title: "5 分钟"),
        RefreshIntervalOption(seconds: 15 * 60, title: "15 分钟"),
        RefreshIntervalOption(seconds: 30 * 60, title: "30 分钟"),
        RefreshIntervalOption(seconds: 60 * 60, title: "1 小时"),
        RefreshIntervalOption(seconds: 2 * 60 * 60, title: "2 小时")
    ]

    private var timer: Timer?
    private var runningTask: Task<Void, Never>?
    private var isCheckingAll = false
    private var hasRegisteredBackgroundTask = false

    private override init() {
        super.init()
        setupLifecycleObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        runningTask?.cancel()
    }

    var autoRefreshEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoRefreshEnabledKey) as? Bool ?? false
    }

    var refreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.refreshIntervalKey)
        if stored <= 0 {
            return 30 * 60
        }
        return max(5 * 60, stored)
    }

    func configureOnLaunch() {
        guard autoRefreshEnabled else {
            stopForegroundTimer()
            return
        }

        startForegroundTimerIfNeeded()
        scheduleBackgroundRefresh()
        enqueueRefreshCheck(force: false)
    }

    func setAutoRefreshEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.autoRefreshEnabledKey)

        if enabled {
            startForegroundTimerIfNeeded()
            scheduleBackgroundRefresh()
            enqueueRefreshCheck(force: false)
        } else {
            stopForegroundTimer()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        }
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        let normalized = max(5 * 60, interval)
        UserDefaults.standard.set(normalized, forKey: Self.refreshIntervalKey)

        if autoRefreshEnabled {
            startForegroundTimerIfNeeded()
            scheduleBackgroundRefresh()
        }
    }

    func checkAndRefreshAll() async {
        await checkAndRefreshAll(force: true)
    }

    func refresh(source: RssSource) async {
        await refreshSource(with: source.objectID)
    }

    @objc private func appDidBecomeActive() {
        guard autoRefreshEnabled else { return }
        startForegroundTimerIfNeeded()
        enqueueRefreshCheck(force: false)
    }

    @objc private func appWillResignActive() {
        stopForegroundTimer()
        if autoRefreshEnabled {
            scheduleBackgroundRefresh()
        }
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    private func startForegroundTimerIfNeeded() {
        guard UIApplication.shared.applicationState == .active else { return }

        let tickInterval = min(refreshInterval, 5 * 60)
        if let timer, timer.timeInterval == tickInterval {
            return
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enqueueRefreshCheck(force: false) }
        }
        timer?.tolerance = min(60, tickInterval * 0.2)
    }

    private func stopForegroundTimer() {
        timer?.invalidate()
        timer = nil
    }

    func registerBackgroundTaskIfNeeded() {
        guard !hasRegisteredBackgroundTask else { return }

        hasRegisteredBackgroundTask = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in self.handleBackgroundRefreshTask(refreshTask) }
        }
        
        if hasRegisteredBackgroundTask {
            DebugLogger.shared.log("RSS 后台任务注册成功")
        } else {
            DebugLogger.shared.log("RSS 后台任务注册失败")
        }
    }

    private func scheduleBackgroundRefresh() {
        guard autoRefreshEnabled else { return }

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(refreshInterval, 15 * 60))

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            DebugLogger.shared.log("RSS 后台刷新调度失败: \(error.localizedDescription)")
        }
    }

    private func handleBackgroundRefreshTask(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let work = Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            await self.checkAndRefreshAll(force: true)
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }

    private func enqueueRefreshCheck(force: Bool) {
        guard runningTask == nil else { return }

        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.checkAndRefreshAll(force: force)
            self.runningTask = nil
        }
    }

    private func checkAndRefreshAll(force: Bool) async {
        guard !isCheckingAll else { return }
        guard autoRefreshEnabled || force else { return }

        isCheckingAll = true
        defer {
            isCheckingAll = false
            if autoRefreshEnabled {
                scheduleBackgroundRefresh()
            }
        }

        let sourceIDs = fetchEnabledSourceIDs()
        let now = Date()

        for sourceID in sourceIDs {
            if Task.isCancelled {
                break
            }

            if !force, let source = sourceForCheck(with: sourceID), !shouldRefresh(source, now: now) {
                continue
            }

            await refreshSource(with: sourceID)
        }
    }

    private func fetchEnabledSourceIDs() -> [NSManagedObjectID] {
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<RssSource> = RssSource.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "customOrder", ascending: true)]
        request.predicate = NSPredicate(format: "enabled == YES")

        do {
            return try context.fetch(request).map(\.objectID)
        } catch {
            DebugLogger.shared.log("读取 RSS 源失败: \(error.localizedDescription)")
            return []
        }
    }

    private func sourceForCheck(with objectID: NSManagedObjectID) -> RssSource? {
        let context = CoreDataStack.shared.viewContext
        return try? context.existingObject(with: objectID) as? RssSource
    }

    private func shouldRefresh(_ source: RssSource, now: Date) -> Bool {
        if source.lastRefreshTime <= 0 {
            return true
        }

        let elapsed = now.timeIntervalSince1970 - TimeInterval(source.lastRefreshTime) / 1000
        let normalInterval = refreshInterval
        let retryDelay = retryInterval(for: Int(source.refreshFailureCount), normalInterval: normalInterval)
        let threshold = source.refreshFailureCount > 0 ? retryDelay : normalInterval
        return elapsed >= threshold
    }

    private func retryInterval(for failureCount: Int, normalInterval: TimeInterval) -> TimeInterval {
        guard failureCount > 0 else { return normalInterval }

        let baseRetry: TimeInterval = 5 * 60
        let exponent = min(max(failureCount - 1, 0), 4)
        let retry = baseRetry * pow(2, Double(exponent))
        return min(normalInterval, retry)
    }

    private func refreshSource(with objectID: NSManagedObjectID) async {
        let context = CoreDataStack.shared.newBackgroundContext()

        guard let source = try? await context.perform({ try context.existingObject(with: objectID) as? RssSource }) else {
            return
        }

        let sourceURL = (try? ManagedObjectAccess.read(source) { $0.sourceUrl }) ?? ""
        let refreshTime = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            let (feedTitle, articles) = try await RSSParser.fetchAndParse(url: sourceURL, source: source)
            let normalizedArticles = Self.normalize(articles)

            try await context.perform {
                RSSRefreshManager.upsertArticles(normalizedArticles, source: source, context: context)
                source.lastRefreshTime = refreshTime
                source.lastUpdateTime = refreshTime
                source.refreshFailureCount = 0
                if source.sourceName.isEmpty || source.sourceName == source.sourceUrl {
                    source.sourceName = feedTitle
                }
                try context.save()
            }
        } catch is CancellationError {
            return
        } catch {
            do {
                try await context.perform {
                    source.lastRefreshTime = refreshTime
                    source.lastUpdateTime = refreshTime
                    source.refreshFailureCount = min(source.refreshFailureCount, Int32.max - 1) + 1
                    try context.save()
                }
            } catch {
                DebugLogger.shared.log("写入 RSS 刷新失败状态异常: \(error.localizedDescription)")
            }

            DebugLogger.shared.log("刷新 RSS 源失败: \(sourceURL), error: \(error.localizedDescription)")
        }
    }

    private struct PersistArticle {
        let order: Int32
        let title: String
        let link: String
        let description: String?
        let pubDate: String?
    }

    nonisolated private static func normalize(_ articles: [RSSArticle]) -> [PersistArticle] {
        let formatter = ISO8601DateFormatter()
        return articles.enumerated().map { index, item in
            PersistArticle(
                order: Int32(index),
                title: item.title,
                link: item.link,
                description: item.description,
                pubDate: item.pubDate.map { formatter.string(from: $0) }
            )
        }
    }

    nonisolated private static func upsertArticles(_ articles: [PersistArticle], source: RssSource, context: NSManagedObjectContext) {
        guard !articles.isEmpty else { return }

        let validLinks = articles.map(\.link).filter { !$0.isEmpty }
        var existingByLink: [String: RssArticle] = [:]

        if !validLinks.isEmpty {
            let request: NSFetchRequest<RssArticle> = RssArticle.fetchRequest()
            request.predicate = NSPredicate(format: "origin == %@ AND link IN %@", source.sourceUrl, validLinks)
            if let existingArticles = try? context.fetch(request) {
                existingByLink = Dictionary(existingArticles.map { ($0.link, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }

        for article in articles where !article.link.isEmpty {
            let target = existingByLink[article.link] ?? RssArticle.create(in: context)
            target.origin = source.sourceUrl
            target.sort = source.sourceName
            target.order = article.order
            target.title = article.title
            target.link = article.link
            target.pubDate = article.pubDate
            target.articleDescription = article.description
            existingByLink[article.link] = target
        }
    }
}
