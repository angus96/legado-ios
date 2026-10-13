import Foundation

enum ConcurrentSourceSearch {
    /// 超时会取消实际请求，子任务退出后才释放并发名额。
    static func withTimeout<Output>(seconds: TimeInterval, operation: @escaping () async throws -> Output) async throws -> Output {
        try await withThrowingTaskGroup(of: Output.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.001, min(300, seconds)) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
    /// Keep only a small number of source requests active, including during cancellation.
    static func run<Input, Output>(
        _ inputs: [Input],
        limit: Int = 5,
        operation: @escaping (Input) async -> Output,
        onResult: (Output) async -> Void
    ) async {
        guard !inputs.isEmpty, !Task.isCancelled else { return }
        await withTaskGroup(of: Output.self) { group in
            var nextIndex = 0
            for _ in 0..<min(max(1, limit), inputs.count) {
                let input = inputs[nextIndex]
                group.addTask { await operation(input) }
                nextIndex += 1
            }

            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                await onResult(result)
                if nextIndex < inputs.count, !Task.isCancelled {
                    let input = inputs[nextIndex]
                    group.addTask { await operation(input) }
                    nextIndex += 1
                }
            }
        }
    }
}
