//
//  HTTPClient.swift
//  Legado-iOS
//
//  网络请求客户端
//

import Foundation

class HTTPClient {
    static let shared = HTTPClient()
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: config)
    }
    
    /// GET 请求
    func get(
        url: String,
        headers: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let url = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let timeout = timeout {
            request.timeoutInterval = timeout
        }
        
        // 设置默认 headers
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        // 设置自定义 headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return (data: data, response: httpResponse)
    }

    func getHtml(urlString: String, headers: [String: String]? = nil) async throws -> (String, HTTPURLResponse) {
        let (data, response) = try await get(url: urlString, headers: headers)

        if let html = String(data: data, encoding: .utf8) {
            return (html, response)
        }

        if let html = String(data: data, encoding: .unicode) {
            return (html, response)
        }

        throw NetworkError.invalidResponse
    }
    
    /// POST 请求
    func post(
        url: String,
        body: Data? = nil,
        headers: [String: String]? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let url = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        
        // 设置默认 headers
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        
        // 设置自定义 headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return (data: data, response: httpResponse)
    }

    func post(
        url: String,
        body: [String: Any],
        headers: [String: String]? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        return try await post(url: url, body: jsonData, headers: headers)
    }
    
    /// 下载文件
    func download(url: String) async throws -> URL {
        guard let url = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        let (tempURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse
        }
        
        // 移动到永久目录
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = documents.appendingPathComponent(url.lastPathComponent)
        
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        
        return destination
    }
}

// MARK: - 错误类型
enum NetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case networkFailure(Error)

    static func message(for error: Error) -> String {
        if case NetworkError.networkFailure(let underlying) = error { return message(for: underlying) }
        var detail = error as NSError
        for _ in 0..<6 {
            if detail.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: detail.code) {
                case .appTransportSecurityRequiresSecureConnection:
                    return "系统阻止了此书源的 HTTP 连接（ATS）。"
                case .secureConnectionFailed:
                    return "安全连接失败（TLS）：网站的加密协议、证书或网络连接可能有问题，请重试或切换书源。"
                case .serverCertificateHasBadDate, .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                    return "网站的 HTTPS 证书未通过验证，请检查设备时间，或切换书源。"
                default: break
                }
            }
            guard let underlying = detail.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            detail = underlying
        }
        return error.localizedDescription
    }
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let statusCode):
            return "HTTP 错误：\(statusCode)"
        case .networkFailure(let error):
            return "网络错误：\(Self.message(for: error))"
        }
    }
}
