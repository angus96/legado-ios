//
//  ConcurrentRateLimiter.swift
//  Legado-iOS
//
//  并发频率限制器 - 参考原版 ConcurrentRateLimiter.kt
//  1:1 移植 Android io.legado.app.help.ConcurrentRateLimiter
//

import Foundation

/// 并发异常（对应 Android ConcurrentException）
struct ConcurrentError: LocalizedError {
    let message: String
    let waitTime: Int64 // 毫秒

    var errorDescription: String? { message }
}

/// 并发记录（对应 Android AnalyzeUrl.ConcurrentRecord）
struct ConcurrentRecord {
    /// 开始访问时间（毫秒时间戳）
    var time: Int64
    /// 限制次数
    var accessLimit: Int
    /// 间隔时间（毫秒）
    var interval: Int
    /// 正在访问的个数
    var frequency: Int
}

/// 并发频率限制器
/// 根据书源的 concurrentRate 设置控制请求频率
/// 格式: "次数/间隔毫秒" 如 "3/1000" 表示 1秒内最多3次
/// 或纯数字如 "500" 表示 1/500ms
class ConcurrentRateLimiter {

    /// 全局并发记录表（对应 Android concurrentRecordMap）
    private static let concurrentRecordMapLock = NSLock()
    private static var concurrentRecordMap: [String: ConcurrentRecord] = [:]

    /// 更新并发率（对应 Android updateConcurrentRate）
    static func updateConcurrentRate(key: String, concurrentRate: String) {
        concurrentRecordMapLock.lock()
        defer { concurrentRecordMapLock.unlock() }

        guard let settings = parseRate(concurrentRate) else { return }
        let existing = concurrentRecordMap[key]
        concurrentRecordMap[key] = ConcurrentRecord(
            time: existing?.time ?? Int64(Date().timeIntervalSince1970 * 1000),
            accessLimit: settings.limit, interval: settings.interval, frequency: existing?.frequency ?? 0
        )
    }

    private static func parseRate(_ rate: String) -> (limit: Int, interval: Int)? {
        let parts = rate.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        let limit = parts.count == 1 ? 1 : Int(parts[0])
        let interval = parts.count == 1 ? Int(parts[0]) : parts.count == 2 ? Int(parts[1]) : nil
        guard let limit, let interval, (1...10_000).contains(limit), (1...86_400_000).contains(interval) else { return nil }
        return (limit, interval)
    }

    private let concurrentRate: String?
    private let key: String?

    init(source: BookSourceDefinition?) {
        // 从 BookSource 获取 concurrentRate
        if let source = source, let snapshot = try? BookSourceSnapshot.capture(source) {
            self.concurrentRate = snapshot.concurrentRate
            self.key = snapshot.bookSourceUrl
        } else {
            self.concurrentRate = nil
            self.key = nil
        }
    }

    /// 便捷初始化
    init(concurrentRate: String?, key: String?) {
        self.concurrentRate = concurrentRate
        self.key = key
    }

    /// 开始访问，并发判断（对应 Android fetchStart）
    /// - Returns: ConcurrentRecord 如果允许访问，nil 如果不需要限制
    /// - Throws: ConcurrentError 如果需要等待
    private func fetchStart() throws -> ConcurrentRecord? {
        guard let concurrentRate = concurrentRate,
              !concurrentRate.isEmpty, concurrentRate != "0",
              let key = key, let settings = Self.parseRate(concurrentRate) else {
            return nil
        }

        Self.concurrentRecordMapLock.lock()

        var isNewRecord = false
        var fetchRecord: ConcurrentRecord

        if let existing = Self.concurrentRecordMap[key] {
            fetchRecord = existing
        } else {
            isNewRecord = true
            fetchRecord = ConcurrentRecord(
                time: Int64(Date().timeIntervalSince1970 * 1000),
                accessLimit: settings.limit, interval: settings.interval, frequency: 1
            )
            Self.concurrentRecordMap[key] = fetchRecord
        }

        if isNewRecord {
            Self.concurrentRecordMapLock.unlock()
            return fetchRecord
        }

        // 并发控制逻辑
        let nowTime = Int64(Date().timeIntervalSince1970 * 1000)
        let nextTime = fetchRecord.time + Int64(fetchRecord.interval)

        if nowTime >= nextTime {
            // 已过限制时间，重置
            fetchRecord.time = nowTime
            fetchRecord.frequency = 1
            Self.concurrentRecordMap[key] = fetchRecord
            Self.concurrentRecordMapLock.unlock()
            return fetchRecord
        }

        if fetchRecord.frequency < fetchRecord.accessLimit {
            fetchRecord.frequency += 1
            Self.concurrentRecordMap[key] = fetchRecord
            Self.concurrentRecordMapLock.unlock()
            return fetchRecord
        } else {
            let waitTime = nextTime - nowTime
            Self.concurrentRecordMapLock.unlock()
            throw ConcurrentError(
                message: "根据并发率还需等待\(waitTime)毫秒才可以访问",
                waitTime: waitTime
            )
        }
    }

    /// 获取并发记录，若处于并发限制状态下则会等待（对应 Android getConcurrentRecord）
    func getConcurrentRecord() async throws -> ConcurrentRecord? {
        while true {
            try Task.checkCancellation()
            do {
                return try fetchStart()
            } catch let error as ConcurrentError {
                try await Task.sleep(nanoseconds: UInt64(error.waitTime) * 1_000_000)
            } catch {
                throw error
            }
        }
    }

    /// 同步版本（对应 Android getConcurrentRecordBlocking）
    func getConcurrentRecordBlocking() -> ConcurrentRecord? {
        while true {
            do {
                return try fetchStart()
            } catch let error as ConcurrentError {
                Thread.sleep(forTimeInterval: Double(error.waitTime) / 1000.0)
            } catch {
                return nil
            }
        }
    }

    /// 带频率限制执行异步闭包（对应 Android withLimit）
    func withLimit<T>(block: () async throws -> T) async throws -> T {
        _ = try await getConcurrentRecord()
        return try await block()
    }

    /// 带频率限制执行同步闭包（对应 Android withLimitBlocking）
    func withLimitBlocking<T>(block: () throws -> T) rethrows -> T {
        _ = getConcurrentRecordBlocking()
        return try block()
    }
}
