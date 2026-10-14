import XCTest

final class LegadoUITests: XCTestCase {
    @MainActor
    func testIncomingTextIsAutomaticallySavedAndCanBeReadFromTheShelf() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_SHARED_TXT"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        let status = app.staticTexts["fileImport.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertEqual(status.label, "已加入书架")
        XCTAssertTrue(app.staticTexts["共 3 章 · 可离线阅读"].exists)
        capture(app, name: "分享TXT-自动加入书架")
        app.buttons["fileImport.read"].tap()
        let canvas = app.descendants(matching: .any)["reader.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "这是从其他应用分享的文本"), object: canvas)], timeout: 15)
        capture(app, name: "分享TXT-本地正文可阅读")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["reader.back"].tap()
        XCTAssertTrue(app.buttons["fileImport.bookshelf"].waitForExistence(timeout: 10))
        app.buttons["fileImport.bookshelf"].tap()
        XCTAssertTrue(app.staticTexts["分享的星河"].firstMatch.waitForExistence(timeout: 10))
        capture(app, name: "分享TXT-书架显示本地书籍")
        app.staticTexts["分享的星河"].firstMatch.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "这是从其他应用分享的文本"), object: canvas)], timeout: 15)
    }

    @MainActor
    func testAuthorSearchFiltersResultsAndRemembersTheSelectedMode() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_AUTHOR_SEARCH"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["bookshelf.search"].waitForExistence(timeout: 15))
        app.buttons["bookshelf.search"].tap()
        let mode = app.segmentedControls["search.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.buttons["按作者"].tap()
        let keyword = app.textFields["search.keyword"]
        keyword.tap(); keyword.typeText("辰东\n")
        XCTAssertTrue(app.staticTexts["遮天"].firstMatch.waitForExistence(timeout: 15))
        let completed = NSPredicate(format: "label CONTAINS %@", "搜索完成")
        wait(for: [XCTNSPredicateExpectation(predicate: completed, object: app.staticTexts["search.progress"])], timeout: 15)
        XCTAssertTrue(app.staticTexts["完美世界"].exists)
        XCTAssertFalse(app.staticTexts["辰东作品评论"].exists)
        XCTAssertFalse(app.staticTexts["辰东相关资料"].exists)
        XCTAssertEqual(app.staticTexts["search.sourceCount"].firstMatch.label, "3 个书源")
        capture(app, name: "按作者搜索-只显示作者匹配的书")

        mode.buttons["综合"].tap()
        XCTAssertTrue(app.staticTexts["辰东作品评论"].firstMatch.waitForExistence(timeout: 5))
        mode.buttons["按作者"].tap()
        let hidden = NSPredicate(format: "exists == false")
        wait(for: [XCTNSPredicateExpectation(predicate: hidden, object: app.staticTexts["辰东作品评论"])], timeout: 5)
        app.buttons["关闭"].firstMatch.tap()
        app.buttons["bookshelf.search"].tap()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.buttons["按作者"].isSelected)
        keyword.tap(); keyword.typeText("不存在的作者\n")
        XCTAssertTrue(app.staticTexts["没有找到作者匹配的书"].waitForExistence(timeout: 15))
        capture(app, name: "按作者搜索-没有匹配作品")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testSingleSourceIsVisibleAndDirectoryStartsWithItsIntroduction() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_DIRECTORY_REGRESSION"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["bookshelf.search"].waitForExistence(timeout: 15))
        app.buttons["bookshelf.search"].tap()
        let keyword = app.textFields["search.keyword"]
        XCTAssertTrue(keyword.waitForExistence(timeout: 5))
        keyword.tap(); keyword.typeText("目录\n")
        XCTAssertTrue(app.staticTexts["目录测试书"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["search.sourceCount"].firstMatch.label, "1 个书源")
        capture(app, name: "搜索结果-单书源")
        app.staticTexts["目录测试书"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["目录测试简介"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["bookDetail.chapters"].tap()
        XCTAssertTrue(app.buttons["toc.chapter.0"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["toc.chapter.0"].label.contains("引言"))
        XCTAssertTrue(app.buttons["toc.chapter.1"].label.contains("第1章"))
        XCTAssertTrue(app.buttons["toc.chapter.4"].label.contains("第4章"))
        XCTAssertFalse(app.buttons["toc.chapter.5"].exists)
        capture(app, name: "目录-保留引言并从第一章开始")
    }

    @MainActor
    func testSearchDetailOnlyAddsWhenRequestedAndKeepsItsChapters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_SEARCH_PREVIEW"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        let title = "长夜行舟：一个旅人与群星的故事"
        func openDetail() {
            app.buttons["bookshelf.search"].tap()
            let keyword = app.textFields["search.keyword"]
            XCTAssertTrue(keyword.waitForExistence(timeout: 5))
            keyword.tap(); keyword.typeText("preview\n")
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 15))
            app.staticTexts[title].firstMatch.tap()
            XCTAssertTrue(app.buttons["bookDetail.add"].waitForExistence(timeout: 10))
        }
        func closeDetailAndSearch() {
            app.navigationBars["书籍详情"].buttons["搜索"].tap()
            app.buttons["关闭"].firstMatch.tap()
            XCTAssertTrue(app.buttons["bookshelf.search"].waitForExistence(timeout: 5))
        }
        func openChapters() {
            let button = app.buttons["bookDetail.chapters"]
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: button)], timeout: 15)
            button.tap()
            let chapter = app.buttons["toc.chapter.2"]
            XCTAssertTrue(chapter.waitForExistence(timeout: 15))
            XCTAssertTrue(chapter.label.contains("第3章"))
        }
        XCTAssertTrue(app.buttons["bookshelf.search"].waitForExistence(timeout: 15))
        openDetail()
        XCTAssertTrue(app.buttons["bookDetail.add"].label.contains("加入书架"))
        openChapters()
        app.buttons["关闭"].firstMatch.tap()
        capture(app, name: "书籍详情-未加入-长书名与简介")
        closeDetailAndSearch()
        XCTAssertFalse(app.staticTexts[title].exists, "仅浏览详情和目录不能增加书架条目")

        openDetail()
        openChapters()
        app.buttons["关闭"].firstMatch.tap()
        app.buttons["bookDetail.add"].tap()
        let joined = NSPredicate(format: "label CONTAINS %@", "已在书架")
        wait(for: [XCTNSPredicateExpectation(predicate: joined, object: app.buttons["bookDetail.add"])], timeout: 5)
        XCTAssertFalse(app.buttons["bookDetail.add"].isEnabled)
        capture(app, name: "书籍详情-已加入书架")
        closeDetailAndSearch()
        XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10), "关闭搜索后书架应立即刷新")

        openDetail()
        XCTAssertTrue(app.buttons["bookDetail.add"].label.contains("已在书架"))
        openChapters()
        app.buttons["toc.chapter.2"].tap()
        let canvas = app.descendants(matching: .any)["reader.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "第3章正文"), object: canvas)], timeout: 15)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testDiscoveryKeyboardCanBeDismissedWithoutClearingTheFilter() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launch()
        XCTAssertTrue(app.staticTexts["测试书籍"].firstMatch.waitForExistence(timeout: 15))
        app.tabBars.buttons["发现"].tap()
        let search = app.textFields["discovery.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("test")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["discovery.dismissKeyboard"].tap()
        let hidden = NSPredicate(format: "exists == false")
        wait(for: [XCTNSPredicateExpectation(predicate: hidden, object: app.keyboards.firstMatch)], timeout: 5)
        XCTAssertEqual(search.value as? String, "test")
        search.tap()
        search.typeText("\n")
        wait(for: [XCTNSPredicateExpectation(predicate: hidden, object: app.keyboards.firstMatch)], timeout: 5)
        app.buttons["清空搜索"].tap()
        capture(app, name: "发现页收起键盘")
    }

    @MainActor
    func testChapterCacheDefaultsToAllAndDownloadsSelectedChapters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        let book = app.staticTexts["测试书籍"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.press(forDuration: 1)
        app.buttons["缓存章节"].firstMatch.tap()
        let selection = app.staticTexts["cache.selection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 15))
        XCTAssertEqual(selection.label, "已选 4 / 共 4 章")
        app.buttons["cache.chapter.1"].tap()
        app.buttons["cache.chapter.4"].tap()
        XCTAssertEqual(selection.label, "已选 2 / 共 4 章")
        capture(app, name: "选择章节缓存")
        app.buttons["cache.startStop"].tap()
        let status = app.staticTexts["cache.status"]
        let completed = NSPredicate(format: "label == %@", "缓存完成")
        wait(for: [XCTNSPredicateExpectation(predicate: completed, object: status)], timeout: 20)
        XCTAssertTrue(app.buttons["cache.chapter.2"].label.contains("已缓存"))
        XCTAssertFalse(app.buttons["cache.chapter.1"].label.contains("已缓存"))
        app.buttons["cache.selectAll"].tap()
        app.buttons["cache.startStop"].tap()
        wait(for: [XCTNSPredicateExpectation(predicate: completed, object: status)], timeout: 20)
        XCTAssertTrue(app.staticTexts["所选章节中，已有 4 章可离线阅读"].waitForExistence(timeout: 20))
        capture(app, name: "全本缓存完成")
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testDeletingBookFromTheShelfKeepsTheAppRunning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        let book = app.staticTexts["测试书籍"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 15))
        book.press(forDuration: 1)
        let remove = app.buttons["删除"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.staticTexts["书架空空如也"].waitForExistence(timeout: 10))
        XCTAssertFalse(book.exists)
        XCTAssertEqual(app.state, .runningForeground)
        capture(app, name: "删除书籍后的空书架")
    }

    @MainActor
    func testSearchAndChangeSourcePagesRemainRunning() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["LEGADO_UI_TESTS"] = "1"
        app.launchEnvironment["LEGADO_FIXTURE_URL"] = "http://127.0.0.1:8766"
        app.launchArguments = ["-com.apple.CoreData.ConcurrencyDebug", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["测试书籍"].firstMatch.waitForExistence(timeout: 15))
        capture(app, name: "书架")
        app.staticTexts["测试书籍"].firstMatch.tap()
        let canvas = app.descendants(matching: .any)["reader.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        let visibleText = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "第1章正文"), object: canvas)
        wait(for: [visibleText], timeout: 15)
        let readerImage = XCTAttachment(screenshot: app.screenshot())
        readerImage.name = "阅读页实际正文"
        readerImage.lifetime = .keepAlways
        add(readerImage)
        let firstPage = canvas.label
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let nextPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label CONTAINS %@", firstPage, "正文"), object: canvas)
        wait(for: [nextPage], timeout: 10)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let theme = app.buttons["reader.theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 10))
        capture(app, name: "阅读菜单")
        theme.tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let darkReader = XCTAttachment(screenshot: app.screenshot())
        darkReader.name = "阅读页暗色主题"
        darkReader.lifetime = .keepAlways
        add(darkReader)
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
        app.staticTexts["测试书籍"].firstMatch.tap()
        let readButton = app.buttons["bookDetail.read"].firstMatch
        XCTAssertTrue(readButton.waitForExistence(timeout: 10), "搜索结果应进入详情页")
        capture(app, name: "书籍详情")
        readButton.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let searchedReader = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "正文"), object: canvas)
        wait(for: [searchedReader], timeout: 15)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
