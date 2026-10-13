import Foundation
import AVFoundation

enum HttpTTSPlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case failed(String)

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .loading, .playing, .paused:
            return true
        default:
            return false
        }
    }
}

struct HttpTTSPlaybackProgress: Sendable {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Double = 0
}

enum HttpTTSPlaybackError: LocalizedError {
    case invalidConfig(String)
    case invalidURL(String)
    case requestFailed(Int)
    case playerFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfig(let message):
            return "配置无效：\(message)"
        case .invalidURL(let url):
            return "URL 无效：\(url)"
        case .requestFailed(let statusCode):
            return "请求失败，HTTP \(statusCode)"
        case .playerFailed:
            return "音频播放失败"
        }
    }
}

private final class HttpTTSAudioDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var onFinish: ((Bool) -> Void)?
    var onDecodeError: ((Error?) -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?(flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onDecodeError?(error)
    }
}

private struct TTSRequestSnapshot {
    let name: String
    let url: String
    let header: String?
    let contentType: String?
    let concurrentRate: String?
    let loginUrl: String?
    static func capture(_ config: HttpTTS) throws -> TTSRequestSnapshot {
        try ManagedObjectAccess.read(config) {
            TTSRequestSnapshot(name: $0.name, url: $0.url, header: $0.header, contentType: $0.contentType,
                               concurrentRate: $0.concurrentRate, loginUrl: $0.loginUrl)
        }
    }
}

actor HttpTTSPlaybackManager {
    typealias StateChangeHandler = @MainActor (HttpTTSPlaybackState) -> Void
    typealias ProgressChangeHandler = @MainActor (HttpTTSPlaybackProgress) -> Void

    private let session: URLSession
    private let cacheDirectory: URL
    private let audioDelegate = HttpTTSAudioDelegate()

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    private var playbackRequestID = UUID()
    private var state: HttpTTSPlaybackState = .idle
    private var currentHeaders: [String: String] = [:]
    private var currentCacheKey: String = ""
    private var maxRetryCount: Int = 2
    private var delegatesConfigured = false

    private var stateHandler: StateChangeHandler?
    private var progressHandler: ProgressChangeHandler?

    nonisolated init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        let baseCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = baseCache.appendingPathComponent("HttpTTSCache", isDirectory: true)
    }

    private func configureDelegatesIfNeeded() {
        guard !delegatesConfigured else { return }
        delegatesConfigured = true
        
        audioDelegate.onFinish = { [weak self] success in
            Task { [weak self] in
                await self?.handlePlaybackFinished(success: success)
            }
        }

        audioDelegate.onDecodeError = { [weak self] error in
            Task { [weak self] in
                await self?.handlePlaybackError(error)
            }
        }
    }
    
    func setCallbacks(
        onStateChange: StateChangeHandler?,
        onProgressChange: ProgressChangeHandler?
    ) {
        self.stateHandler = onStateChange
        self.progressHandler = onProgressChange
        notifyStateChanged()
        notifyProgressChanged()
    }

    func setRetryCount(_ retryCount: Int) {
        maxRetryCount = max(0, retryCount)
    }

    func currentState() -> HttpTTSPlaybackState {
        state
    }

    func currentProgress() -> HttpTTSPlaybackProgress {
        buildProgressSnapshot()
    }

    func speak(text: String, config: HttpTTS) async {
        configureDelegatesIfNeeded()
        
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            updateState(.failed("朗读文本为空"))
            return
        }

        stopInternal(newState: .stopped)
        let requestID = playbackRequestID

        do {
            let config = try TTSRequestSnapshot.capture(config)
            updateState(.loading)
            currentHeaders = parseHeaders(from: config.header)
            if let contentType = config.contentType?.trimmingCharacters(in: .whitespacesAndNewlines), !contentType.isEmpty {
                currentHeaders["Content-Type"] = contentType
            }

            let url = try generateUrl(text: normalizedText, config: config)
            currentCacheKey = buildCacheKey(text: normalizedText, config: config)

            var lastError: Error?
            for attempt in 0...maxRetryCount {
                do {
                    let localPath = try await downloadAudio(url: url)
                    guard playbackRequestID == requestID, !Task.isCancelled else { return }
                    try play(localPath: localPath)
                    return
                } catch {
                    guard playbackRequestID == requestID, !Task.isCancelled else { return }
                    lastError = error
                    DebugLogger.shared.log("HttpTTS 下载或播放失败，attempt=\(attempt + 1): \(error.localizedDescription)")
                    if attempt < maxRetryCount {
                        continue
                    }
                }
            }

            let message = (lastError as? LocalizedError)?.errorDescription
                ?? lastError?.localizedDescription
                ?? "在线朗读失败"
            updateState(.failed(message))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            updateState(.failed(message))
        }
    }

    func generateUrl(text: String, config: HttpTTS) throws -> URL {
        try generateUrl(text: text, config: TTSRequestSnapshot.capture(config))
    }

    private func generateUrl(text: String, config: TTSRequestSnapshot) throws -> URL {
        let template = config.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            throw HttpTTSPlaybackError.invalidConfig("URL 为空")
        }

        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let replacements: [String: String] = [
            "{{text}}": encodedText,
            "{{speakText}}": encodedText,
            "{{content}}": encodedText,
            "{text}": encodedText,
            "{speakText}": encodedText,
            "{content}": encodedText
        ]

        var rendered = template
        for (placeholder, value) in replacements {
            rendered = rendered.replacingOccurrences(of: placeholder, with: value)
        }

        if rendered == template,
           var components = URLComponents(string: template),
           !template.contains("{{") {
            var queryItems = components.queryItems ?? []
            let hasTextParam = queryItems.contains { $0.name.lowercased() == "text" }
            if !hasTextParam {
                queryItems.append(URLQueryItem(name: "text", value: text))
            }
            components.queryItems = queryItems
            if let url = components.url {
                return url
            }
        }

        guard let url = URL(string: rendered) else {
            throw HttpTTSPlaybackError.invalidURL(rendered)
        }
        return url
    }

    func downloadAudio(url: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let cacheKey = currentCacheKey.isEmpty ? url.absoluteString.md5() : currentCacheKey
        let localPath = cacheDirectory.appendingPathComponent("\(cacheKey).audio")

        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        currentHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (tempURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HttpTTSPlaybackError.invalidConfig("响应无效")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HttpTTSPlaybackError.requestFailed(httpResponse.statusCode)
        }

        try? FileManager.default.removeItem(at: localPath)
        try FileManager.default.moveItem(at: tempURL, to: localPath)
        return localPath
    }

    func play(localPath: URL) throws {
        stopProgressLoop()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetooth, .allowAirPlay])
        try audioSession.setActive(true)

        let player = try AVAudioPlayer(contentsOf: localPath)
        player.delegate = audioDelegate
        player.prepareToPlay()

        guard player.play() else {
            throw HttpTTSPlaybackError.playerFailed
        }

        self.player = player
        updateState(.playing)
        startProgressLoop()
    }

    func pause() {
        guard state.isPlaying else { return }
        player?.pause()
        updateState(.paused)
        notifyProgressChanged()
    }

    func resume() {
        guard state.isPaused else { return }
        guard player?.play() == true else {
            updateState(.failed("恢复播放失败"))
            return
        }
        updateState(.playing)
        startProgressLoop()
    }

    func stop() {
        stopInternal(newState: .stopped)
    }

    private func stopInternal(newState: HttpTTSPlaybackState) {
        playbackRequestID = UUID()
        stopProgressLoop()
        player?.stop()
        player = nil
        updateState(newState)
        notifyProgressChanged()
    }

    private func handlePlaybackFinished(success: Bool) {
        stopProgressLoop()
        if success {
            updateState(.idle)
        } else {
            updateState(.failed("播放未完成"))
        }
        notifyProgressChanged()
    }

    private func handlePlaybackError(_ error: Error?) {
        stopProgressLoop()
        let message = error?.localizedDescription ?? "音频解码失败"
        updateState(.failed(message))
        notifyProgressChanged()
    }

    private func startProgressLoop() {
        stopProgressLoop()
        progressTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await self.notifyProgressChanged()
                let active = await self.state.isActive
                if !active {
                    break
                }
            }
        }
    }

    private func stopProgressLoop() {
        progressTask?.cancel()
        progressTask = nil
    }

    private func updateState(_ newState: HttpTTSPlaybackState) {
        state = newState
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        let handler = stateHandler
        let currentState = state
        Task { @MainActor in
            handler?(currentState)
        }
    }

    private func notifyProgressChanged() {
        let handler = progressHandler
        let progress = buildProgressSnapshot()
        Task { @MainActor in
            handler?(progress)
        }
    }

    private func buildProgressSnapshot() -> HttpTTSPlaybackProgress {
        guard let player else {
            return HttpTTSPlaybackProgress()
        }

        let duration = max(0, player.duration)
        let currentTime = max(0, player.currentTime)
        let progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0

        return HttpTTSPlaybackProgress(
            currentTime: currentTime,
            duration: duration,
            progress: progress
        )
    }

    private func parseHeaders(from header: String?) -> [String: String] {
        guard let header,
              !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = header.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }

        if let dictionary = json as? [String: String] {
            return dictionary
        }

        if let dictionary = json as? [String: Any] {
            var headers: [String: String] = [:]
            for (key, value) in dictionary {
                headers[key] = "\(value)"
            }
            return headers
        }

        return [:]
    }

    private func buildCacheKey(text: String, config: TTSRequestSnapshot) -> String {
        let parts = [
            config.name,
            text,
            config.url,
            config.header ?? "",
            config.contentType ?? "",
            config.concurrentRate ?? "",
            config.loginUrl ?? ""
        ]

        return parts.joined(separator: "|").md5()
    }
}
