import Foundation

enum ConcurrentSourceSearch {
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
