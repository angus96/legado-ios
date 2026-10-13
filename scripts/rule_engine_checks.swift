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
    checkConcurrentParsing()
    await checkSourceConcurrency()
    if CommandLine.arguments.count > 2 { try checkCorpus(CommandLine.arguments[2]) }
}
