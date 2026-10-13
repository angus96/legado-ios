import Foundation

actor SearchProbe {
    var active = 0
    var maximum = 0
    var completed = 0
    func begin() { active += 1; maximum = max(maximum, active) }
    func end() { active -= 1; completed += 1 }
}

@main
struct SearchPerformanceChecks {
    static func main() async throws {
        var accumulator = SearchResultAccumulator()
        let started = ProcessInfo.processInfo.systemUptime
        var firstID: UUID?
        for source in 0..<3538 {
            let id = UUID()
            let incoming = (0..<20).map { index in
                BookSearchResult(name: "测试书籍\(index)", author: "作者", coverUrl: nil, intro: nil,
                                 kind: source == 0 ? nil : "小说", lastChapter: nil,
                                 sourceName: "书源\(source)", sourceId: id, bookUrl: "https://example.invalid/\(index)")
            }
            accumulator.append(incoming)
            if source == 0 { firstID = accumulator.results.first?.id }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        precondition(accumulator.results.count == 20)
        precondition(accumulator.results.first?.id == firstID)
        precondition(accumulator.results.first?.sourceCount == 3538)
        precondition(accumulator.results.first?.kind == "小说")
        print("3538 个书源、70760 条返回结果合并：\(String(format: "%.3f", elapsed)) 秒；行 ID 稳定，去重和书源计数正确。")

        for limit in [5, 12] {
            let probe = SearchProbe()
            let start = ProcessInfo.processInfo.systemUptime
            var firstResult: TimeInterval?
            await ConcurrentSourceSearch.run(Array(0..<120), limit: limit) { index in
                await probe.begin()
                try? await Task.sleep(nanoseconds: index < 5 ? 150_000_000 : 5_000_000)
                await probe.end()
                return index
            } onResult: { index in
                if index >= 5 && firstResult == nil { firstResult = ProcessInfo.processInfo.systemUptime - start }
            }
            let maximum = await probe.maximum
            let completed = await probe.completed
            precondition(maximum <= limit && completed == 120)
            print("前 5 个书源较慢时，并发 \(limit)：首个有效结果 \(String(format: "%.3f", firstResult!)) 秒，实际最大并发 \(maximum)。")
        }
        let deadlineStart = ProcessInfo.processInfo.systemUptime
        do {
            let _: Int = try await ConcurrentSourceSearch.withTimeout(seconds: 0.02) {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return 1
            }
            preconditionFailure("未超时")
        } catch let error as URLError { precondition(error.code == .timedOut) }
        precondition(ProcessInfo.processInfo.systemUptime - deadlineStart < 1)
        let probe = SearchProbe()
        let task = Task {
            await ConcurrentSourceSearch.run(Array(0..<3538), limit: 12) { _ in
                await probe.begin()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await probe.end()
            } onResult: { _ in }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        await task.value
        let active = await probe.active
        let completed = await probe.completed
        precondition(active == 0 && completed <= 12)
        print("超时和取消通过：停止后无残留请求，未继续启动剩余书源。")
    }
}
