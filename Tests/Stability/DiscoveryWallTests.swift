import XCTest
import CoreData
@testable import Legado

private actor DiscoveryResponseGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
final class DiscoveryWallTests: XCTestCase {
    private func container() throws -> NSPersistentContainer {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Legado", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let container = NSPersistentContainer(name: UUID().uuidString, managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        return container
    }

    private func source(in context: NSManagedObjectContext, name: String = "发现书源") -> BookSource {
        let source = BookSource.create(in: context)
        source.bookSourceName = name
        source.bookSourceUrl = "https://example.invalid/" + source.sourceId.uuidString
        source.exploreUrl = "热门::/hot&&完本::/finished"
        return source
    }

    func testDiscoveryRemembersSourceAndCategoryWithoutLoadingOtherScripts() async throws {
        let database = try container()
        let plain = source(in: database.viewContext, name: "常用书源")
        let scripted = source(in: database.viewContext, name: "动态书源")
        scripted.exploreUrl = "@js: '动态分类::/dynamic'"
        try database.viewContext.save()
        let suite = "discovery-wall-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        let model = DiscoveryViewModel(context: database.newBackgroundContext(), defaults: defaults) { _ in
            calls += 1
            return [ExploreKind(title: "动态分类", url: "/dynamic")]
        }
        await model.loadExploreGroups()
        model.restoreSelection()
        XCTAssertEqual(model.selectedSourceID, plain.sourceId)
        XCTAssertEqual(model.selectedExplore?.url, "/hot")
        XCTAssertEqual(calls, 0, "首次进入只显示选中的静态分类，不执行其他书源的脚本")
        let group = try XCTUnwrap(model.selectedGroup)
        let kind = try XCTUnwrap(group.exploreKinds.first { $0.url == "/finished" })
        model.openExplore(group: group, kind: kind)

        let reopened = DiscoveryViewModel(context: database.newBackgroundContext(), defaults: defaults) { _ in
            XCTFail("恢复已选分类不能加载其他书源的脚本")
            return []
        }
        await reopened.loadExploreGroups()
        reopened.restoreSelection()
        XCTAssertEqual(reopened.selectedSourceID, plain.sourceId)
        XCTAssertEqual(reopened.selectedExplore?.url, "/finished")
        XCTAssertEqual(calls, 0)
    }

    func testSwitchingCategoryIgnoresThePreviousResponse() async throws {
        let database = try container()
        let source = source(in: database.viewContext)
        try database.viewContext.save()
        let sourceID = source.sourceId
        let gate = DiscoveryResponseGate()
        let started = expectation(description: "旧分类已开始请求")
        let model = DiscoveryBookWallViewModel(context: database.newBackgroundContext()) { _, url, _ in
            if url == "/slow" { started.fulfill(); await gate.wait() }
            return [SearchBookResult(name: url == "/slow" ? "旧分类的书" : "新分类的书", bookUrl: "https://example.invalid" + url)]
        }
        let slow = ExploreSelection(sourceId: sourceID, sourceName: "发现书源", kindTitle: "旧分类", url: "/slow")
        let fast = ExploreSelection(sourceId: sourceID, sourceName: "发现书源", kindTitle: "新分类", url: "/fast")
        let oldTask = Task { await model.show(slow) }
        await fulfillment(of: [started], timeout: 3)
        await model.show(fast)
        XCTAssertEqual(model.results.map(\.name), ["新分类的书"])
        await gate.release()
        await oldTask.value
        XCTAssertEqual(model.selection?.cacheKey, fast.cacheKey)
        XCTAssertEqual(model.results.map(\.name), ["新分类的书"], "较晚返回的旧分类不能覆盖当前书墙")
        XCTAssertFalse(model.isLoading)
    }

    func testPosterPagesAreDeduplicatedAndRestoredWhenReturningToACategory() async throws {
        let database = try container()
        let source = source(in: database.viewContext)
        try database.viewContext.save()
        let sourceID = source.sourceId
        var requests: [String] = []
        let model = DiscoveryBookWallViewModel(context: database.newBackgroundContext()) { _, url, page in
            requests.append("\(url):\(page)")
            if url == "/second" { return [SearchBookResult(name: "分类乙", bookUrl: "/b")] }
            if page == 1 { return [SearchBookResult(name: "第一页", bookUrl: "/1")] }
            if page == 2 {
                return [SearchBookResult(name: "重复条目", bookUrl: "/1"), SearchBookResult(name: "第二页", bookUrl: "/2")]
            }
            return []
        }
        let first = ExploreSelection(sourceId: sourceID, sourceName: "发现书源", kindTitle: "分类甲", url: "/first")
        let second = ExploreSelection(sourceId: sourceID, sourceName: "发现书源", kindTitle: "分类乙", url: "/second")
        await model.show(first)
        await model.loadMore()
        XCTAssertEqual(model.results.map(\.name), ["第一页", "第二页"])
        let ids = model.results.map(\.id)
        await model.show(second)
        await model.show(first)
        XCTAssertEqual(model.results.map(\.id), ids, "返回分类直接复用已加载的封面和列表行")
        XCTAssertEqual(model.currentPage, 2)
        XCTAssertEqual(requests, ["/first:1", "/first:2", "/second:1"])
        await model.loadMore()
        XCTAssertFalse(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(requests.last, "/first:3")
        XCTAssertEqual(requests.count, 4)
    }
}
