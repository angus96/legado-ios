import XCTest

final class LegadoUITests: XCTestCase {
    @MainActor
    func testSearchAndChangeSourcePagesRemainRunning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["测试书籍"].firstMatch.waitForExistence(timeout: 15))
        app.staticTexts["测试书籍"].firstMatch.tap()
        let canvas = app.descendants(matching: .any)["reader.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let change = app.buttons["reader.changeSource"]
        XCTAssertTrue(change.waitForExistence(timeout: 10))
        change.tap()
        let result = app.buttons["changeSource.result.测试新书源"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        let loaded = XCTAttachment(screenshot: app.screenshot())
        loaded.name = "换源结果加载完成"
        loaded.lifetime = .keepAlways
        add(loaded)
        result.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: result)
        wait(for: [dismissed], timeout: 15)
        let updatedSource = app.buttons["reader.changeSource"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "测试新书源"), object: updatedSource)
        wait(for: [updated], timeout: 15)
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts["换源失败"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
        app.launch()
        let search = app.buttons["bookshelf.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        let keyword = app.textFields["search.keyword"]
        XCTAssertTrue(keyword.waitForExistence(timeout: 5))
        keyword.tap()
        keyword.typeText("fixture\n")
        XCTAssertTrue(app.staticTexts["测试书籍"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.state, .runningForeground)
        let searched = XCTAttachment(screenshot: app.screenshot())
        searched.name = "搜索结果加载完成"
        searched.lifetime = .keepAlways
        add(searched)
    }
}
