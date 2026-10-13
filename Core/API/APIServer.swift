import Foundation
import CoreData

struct APIResponse: Codable {
    var isSuccess: Bool
    var errorMsg: String
    var data: CodableValue?
    
    static func success(_ data: CodableValue? = nil) -> APIResponse {
        APIResponse(isSuccess: true, errorMsg: "", data: data)
    }
    
    static func error(_ message: String) -> APIResponse {
        APIResponse(isSuccess: false, errorMsg: message, data: nil)
    }
}

indirect enum CodableValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([CodableValue])
    case dictionary([String: CodableValue])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CodableValue].self) {
            self = .dictionary(value)
        } else {
            self = .null
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

@MainActor
class APIServer {
    static let shared = APIServer()
    
    private var router: HTTPRouter?
    private var handler: HTTPRequestHandler?
    private(set) var isRunning = false
    private(set) var port: UInt16 = 8080
    
    private init() {}
    
    func start(port: UInt16 = 8080) throws {
        guard !isRunning else { return }
        
        self.port = port
        let router = HTTPRouter()
        
        router.register(method: "GET", path: "/getBookSources") { [weak self] request in
            self?.handleSync(path: "/getBookSources", request: request) ?? .text(statusCode: 500, text: "Server error")
        }
        
        handler = HTTPRequestHandler(router: router)
        self.router = router
        isRunning = true
    }
    
    func stop() {
        handler = nil
        router = nil
        isRunning = false
    }
    
    private func handleSync(path: String, request: HTTPRequest) -> HTTPResponse {
        let queryParameters: [String: String] = Dictionary(request.queryItems.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        }, uniquingKeysWith: { _, last in last })
        
        let apiRequest = APIRequest(
            method: request.method,
            path: request.path,
            queryParameters: queryParameters,
            headers: request.headers,
            body: nil
        )
        
        let apiResponse: APIResponse
        switch path {
        case "/getBookSources":
            apiResponse = CoreDataStack.shared.viewContext.performAndWait { BookSourceAPI.getSources() }
        default:
            apiResponse = .error("未知接口: \(path)")
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let jsonData = try? encoder.encode(apiResponse) else {
            return HTTPResponse(statusCode: 500, body: Data("{\"isSuccess\":false}".utf8))
        }
        return HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: jsonData)
    }
}

// API 模块专用的请求/响应类型
struct APIRequest {
    let method: String
    let path: String
    let queryParameters: [String: String]
    let headers: [String: String]
    let body: String?
}

struct APIResponseData {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}
