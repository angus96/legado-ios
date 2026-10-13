import Foundation
import JavaScriptCore
import SwiftSoup

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
    print("PASS: \(message)")
}

let engine = RuleEngine()
let html = "<article class='book'><h2 class='title'>测试书籍</h2><a href='/book/1'>阅读</a></article>"
let baseURL = "https://example.com/search"
let testCase = CommandLine.arguments.dropFirst().first ?? "all"

func checkHTMLInline() throws {
    let document = try SwiftSoup.parse(html)
    let element = try document.select("article").first()!
    let result = engine.getString(
        ruleStr: "{{typeof result === 'string' ? '.title' : '.missing'}}@text",
        elementContext: ElementContext(element: element), baseUrl: baseURL
    )
    check(result == "测试书籍", "HTML element in inline JavaScript")
    check(engine.getString(ruleStr: "{{'.title'}}@text", elementContext: ElementContext(element: document)) == "测试书籍",
          "HTML document in inline JavaScript")
}

final class ParsingContext: RuleExecutionContext {
    func getVariable(_ key: String) -> String { "变量" }
    func setVariable(_ key: String, value: String) {}
    func evalJS(_ jsCode: String, result: Any?) -> String? { "替换" }
    func resolveRule(_ rule: SourceRule) -> String? { "替换" }
}

func checkUnicode() {
    let context = ParsingContext()
    for prefix in ["中文", "📚", "e\u{301}", "👨‍👩‍👧‍👦"] {
        let rule = SourceRule(ruleStr: prefix + "{{'text'}}后缀")
        rule.makeUpRule(result: "", context: context)
        check(rule.rule == prefix + "替换后缀", "Unicode template preserves \(prefix)")
        let capture = SourceRule(ruleStr: prefix + "$1后缀")
        capture.makeUpRule(result: ["", "匹配"], context: context)
        check(capture.rule == prefix + "匹配后缀", "Unicode capture preserves \(prefix)")
        let parts = SourceRuleParser().parse(prefix + "<js>1</js>后缀")
        check(parts.count == 3 && parts.first?.rule == prefix && parts.last?.rule == "后缀", "Unicode rule splitting preserves \(prefix)")
    }
}

func checkJavaScriptInputs() throws {
    let parser = JavaScriptParser()
    func evaluate(_ input: Any?, _ script: String, previous: RuleResult = .none) throws -> RuleResult {
        let context = ExecutionContext()
        context.document = input
        context.lastResult = previous
        return try parser.execute(script, context: context)
    }

    check(try evaluate("hello", "result.toUpperCase()").string == "HELLO", "JavaScript reads response text")
    let document = try SwiftSoup.parse(html)
    check(try evaluate(document, "result.indexOf('测试书籍') >= 0").string == "true", "JavaScript reads document HTML")
    let json: [String: Any] = ["title": "测试", "count": 3, "enabled": true, "empty": NSNull(), "books": [["name": "书籍"]]]
    check(try evaluate(json, "result.title + ':' + result.count + ':' + result.enabled + ':' + result.books[0].name + ':' + result.empty").string == "测试:3:true:书籍:null",
          "JSON fields keep strings, numbers, booleans, arrays and null")
    check(try evaluate(["one", "two"], "result[1]").string == "two", "JavaScript reads JSON arrays")
    check(try evaluate(document, "result.join(',')", previous: .list(["one", "two"])).string == "one,two",
          "JavaScript reads a previous list result")
    check(try evaluate(document, "result", previous: .string("previous")).string == "previous",
          "JavaScript reads a previous string result")
    check(try evaluate(nil, "result === null").string == "true", "missing input becomes null")
    final class UnsupportedSwiftObject {}
    let nested: [String: Any] = ["node": document, "unsupported": UnsupportedSwiftObject()]
    check(try evaluate(nested, "typeof result.node === 'string' && result.unsupported === null").string == "true",
          "nested Swift objects cannot reach the Objective-C wrapper")

    let context = ExecutionContext()
    context.document = "still working"
    do {
        _ = try parser.execute("throw new Error('bad source')", context: context)
        fatalError("JavaScript exception was ignored")
    } catch RuleError.executionFailed {
        print("PASS: invalid JavaScript reports a rule error")
    }
    check(try parser.execute("result", context: context).string == "still working", "a failed script does not poison the next rule")
    check(try parser.execute("undefined", context: context).string == nil, "undefined is an empty rule result")
    check(try parser.execute("null", context: context).string == nil, "null is an empty rule result")
}

func checkExtraction() throws {
    let elements = try engine.getElements(ruleStr: "article.book", body: html, baseUrl: baseURL)
    check(elements.count == 1, "search result list parses HTML")
    let element = elements[0]
    check(engine.getString(ruleStr: ".title@text", elementContext: element) == "测试书籍", "search extracts a book title")
    check(engine.getString(ruleStr: "{{'a'}}@href", elementContext: element) == "https://example.com/book/1", "inline JavaScript builds a URL selector")
    check(engine.getString(ruleStr: "//h2/text()", elementContext: element) == "测试书籍", "XPath still parses HTML")
    let context = ExecutionContext()
    context.document = element.element
    check(try engine.executeSingle(rule: "@js: result.indexOf('测试书籍') >= 0", context: context).string == "true", "full rule engine executes JavaScript on an HTML result")

    let json = "{\"books\":[{\"name\":\"JSON书籍\",\"url\":\"/book/2\"}]}"
    let jsonElements = try engine.getElements(ruleStr: "$.books", body: json, baseUrl: baseURL)
    check(jsonElements.count == 1, "search result list parses JSON")
    check(engine.getString(ruleStr: "$.name", elementContext: jsonElements[0]) == "JSON书籍", "JSONPath still parses titles")
    check(engine.getString(ruleStr: "{{'$.name'}}", elementContext: jsonElements[0]) == "JSON书籍", "JSON inline JavaScript still works")
}

func checkAndroidHTMLRules() throws {
    let body = """
    <ul class="librarylist"><li><div class="info"><span><a href="/book/1">凡人修仙传</a></span><span><a>忘语</a></span></div></li>
    <li><div class="info"><span><a href="/book/2">斗破苍穹</a></span><span><a>天蚕土豆</a></span></div></li></ul>
    <div id="chaptercontent" class="article-content font16"><p>第一段正文</p><p>第二段正文</p></div><a href="/toc">点击阅读</a>
    <a data-user="reader@example.com" href="/quoted">属性值含分隔符</a>
    """
    let elements = try engine.getElements(ruleStr: "class.librarylist@tag.li", body: body, baseUrl: baseURL)
    check(elements.count == 2, "Android class/tag list rules preserve book result elements")
    check(engine.getString(ruleStr: ".info@tag.span.0@tag.a@text", elementContext: elements[0]) == "凡人修仙传", "Android chained selector extracts a book name")
    check(engine.getString(ruleStr: ".info@tag.span.-1@tag.a@text", elementContext: elements[0]) == "忘语", "Android negative selector index extracts the author")
    check(engine.getString(ruleStr: ".info@tag.span.0@tag.a@href", elementContext: elements[1]) == "https://example.com/book/2", "Android chained selector resolves book links")
    check(engine.getString(ruleStr: ".info@tag.span.99@text", elementContext: elements[0]).isEmpty, "out-of-range Android selector indexes return empty")
    check(try engine.getElements(ruleStr: "tag.missing||class.librarylist@children", body: body, baseUrl: baseURL).count == 2, "Android fallback list rules use the first nonempty selection")
    let root = ElementContext(element: try SwiftSoup.parse(body), baseUrl: baseURL)
    check(engine.getString(ruleStr: "class.article-content font16@tag.p.-1@text", elementContext: root) == "第二段正文", "multiple Android class names and negative indexes select chapter content")
    check(engine.getString(ruleStr: "text.点击阅读@href", elementContext: root) == "https://example.com/toc", "Android text selector resolves the directory link")
    check(engine.getString(ruleStr: "[data-user='reader@example.com']@href", elementContext: root) == "https://example.com/quoted", "CSS quoted attributes keep embedded at signs")
    check(try engine.getElements(ruleStr: "class.librarylist@tag.li.0,1", body: body, baseUrl: baseURL).count == 2, "Android selector accepts multiple indexes")
    let excluded = try engine.getElements(ruleStr: "class.librarylist@tag.li!0", body: body, baseUrl: baseURL)
    check(excluded.count == 1 && engine.getString(ruleStr: ".info@tag.span.0@text", elementContext: excluded[0]) == "斗破苍穹", "Android list exclusion skips the header or first result")
    check(try engine.getElements(ruleStr: "class.librarylist@tag.li!0,-1", body: body, baseUrl: baseURL).isEmpty, "Android list exclusion accepts multiple and negative indexes")
}

func checkInnerRules() {
    let root: [String: Any] = ["index": 0, "items": [["name": "嵌套规则书籍"]]]
    check(JSONPathParser.evaluate(path: "$.items[{$.index}].name", root: root).first as? String == "嵌套规则书籍",
          "JSONPath executes a nested rule and keeps the suffix")
    check(JSONPathParser.evaluate(path: "$.items[{$.missing}].name", root: root).isEmpty,
          "missing nested JSONPath values fail without a process crash")
    for text in ["{$.missing}", "{$.missing}尾部", "📚{$.missing}尾部", "{$.missing", "{$.missing}\\", "{[}]"] {
        _ = RuleAnalyzer(data: text, code: true).innerRule(inner: "{$.") { _ in "" }
    }
    check(RuleAnalyzer(data: "📚{{1}}尾部{{2}}结束", code: true)
        .innerRule(inner: "{{", startStep: 2, endStep: 2) { "替换" + $0 } == "📚替换1尾部替换2结束",
          "multiple nested rules preserve Unicode and trailing text")
    check(RuleAnalyzer(data: "<one>missing</one>tail<one>found</one>")
        .innerRule(startStr: "<one>", endStr: "</one>") { $0 == "found" ? "ok" : nil }
        == "<one>missing</one>tailok", "an unresolved delimited rule preserves the surrounding text")
    let analyzer = RuleAnalyzer(data: "a[b='&&']&&c&&d")
    check(analyzer.splitRule("&&") == ["a[b='&&']", "c", "d"], "rule splitting ignores separators inside balanced groups")
    analyzer.reSetPos()
    check(analyzer.splitRule("&&") == ["a[b='&&']", "c", "d"], "resetting a rule analyzer clears previous results")
    let chain = Array(repeating: "a[b='&&']", count: 10_000).joined(separator: "&&")
    check(RuleAnalyzer(data: chain).splitRule("&&").count == 10_000,
          "long balanced rule chains do not recurse on the stack")
    let parsed = try! JSONSerialization.jsonObject(with: Data("{\"zero\":0,\"one\":1,\"enabled\":true}".utf8))
    let values = ExecutionContext()
    values.jsonValue = parsed
    check(try! JSONPathParser().execute("$.zero", context: values).string == "0", "JSONSerialization numeric zero remains a number")
    check(try! JSONPathParser().execute("$.one", context: values).string == "1", "JSONSerialization numeric one remains a number")
    check(try! JSONPathParser().execute("$.enabled", context: values).string == "true", "JSONSerialization booleans retain their type")
}

func checkConcurrentParsing() {
    let lock = NSLock()
    var failureCount = 0
    DispatchQueue.concurrentPerform(iterations: 4000) { index in
        autoreleasepool {
            do {
                let elements = try engine.getElements(ruleStr: "article", body: html, baseUrl: baseURL)
                let result = engine.getString(ruleStr: "{{typeof result === 'string' ? '.title' : '.missing'}}@text",
                                              elementContext: elements[0])
                guard result == "测试书籍" else { throw RuleError.executionFailed("Wrong title") }
                let context = ExecutionContext()
                context.jsonValue = ["index": index]
                let json = try JavaScriptParser().execute("result.index", context: context)
                guard json.string == String(index) else { throw RuleError.executionFailed("Result crossed contexts") }
            } catch {
                lock.lock()
                failureCount += 1
                lock.unlock()
            }
        }
    }
    check(failureCount == 0, "4000 concurrent HTML and JSON searches keep results isolated")
}

actor SearchActivity {
    var active = 0
    var peak = 0
    var started = 0
    var results: [Int] = []
    func enter() {
        active += 1
        started += 1
        peak = max(peak, active)
    }
    func leave() { active -= 1 }
    func record(_ value: Int) { results.append(value) }
}

func checkSourceConcurrency() async {
    let activity = SearchActivity()
    await ConcurrentSourceSearch.run(Array(0..<100), limit: 5) { item in
        await activity.enter()
        try? await Task.sleep(nanoseconds: 1_000_000)
        await activity.leave()
        return item
    } onResult: { item in await activity.record(item) }
    check(await activity.peak <= 5, "source searches keep at most five requests active")
    check(await activity.results.sorted() == Array(0..<100), "bounded source search completes every source once")

    let cancelled = SearchActivity()
    var startedSignal: AsyncStream<Void>.Continuation!
    let started = AsyncStream<Void> { startedSignal = $0 }
    let signal = startedSignal!
    let task = Task {
        await ConcurrentSourceSearch.run(Array(0..<100), limit: 5) { item in
            await cancelled.enter()
            signal.yield(())
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            await cancelled.leave()
            return item
        } onResult: { item in await cancelled.record(item) }
    }
    var iterator = started.makeAsyncIterator()
    for _ in 0..<5 { _ = await iterator.next() }
    task.cancel()
    await task.value
    signal.finish()
    check(await cancelled.started == 5, "cancelled searches do not launch remaining sources")
    check(await cancelled.results.isEmpty, "cancelled searches do not publish stale results")
}

func checkCorpus(_ path: String) throws {
    let rules = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    let context = ParsingContext()
    let parser = SourceRuleParser()
    for text in rules {
        let rule = SourceRule(ruleStr: text)
        rule.makeUpRule(result: ["", "capture"], context: context)
        _ = parser.parse(text)
        _ = RuleSplitter.split(text)
        _ = JSONPathParser.evaluate(path: text, root: ["index": 0, "items": [["name": "fixture"]]])
    }
    print("PASS: \(rules.count) imported source rules parse without executing JavaScript")
}

switch testCase {
case "html-inline": try checkHTMLInline()
case "unicode": checkUnicode()
case "corpus": try checkCorpus(CommandLine.arguments[2])
default:
    try checkHTMLInline()
    checkUnicode()
    try checkJavaScriptInputs()
    try checkExtraction()
    try checkAndroidHTMLRules()
    checkInnerRules()
    checkConcurrentParsing()
    await checkSourceConcurrency()
    if CommandLine.arguments.count > 2 { try checkCorpus(CommandLine.arguments[2]) }
}
