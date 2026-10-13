import Foundation
import CoreData

struct BookSourceAPI {
    
    static func getSources() -> APIResponse {
        let context = CoreDataStack.shared.viewContext
        let fetchRequest: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "customOrder", ascending: true)]
        
        do {
            let sources = try context.fetch(fetchRequest)
            if sources.isEmpty {
                return .error("设备源列表为空")
            }
            let dataArray = sources.map { encodeBookSource($0) }
            return .success(.array(dataArray))
        } catch {
            return .error("获取书源失败: \(error.localizedDescription)")
        }
    }
    
    static func saveSource(_ body: String?) -> APIResponse {
        guard let body = body, !body.isEmpty else {
            return .error("数据不能为空")
        }
        
        guard let data = body.data(using: .utf8) else {
            return .error("数据格式错误")
        }
        
        do {
            let decoder = JSONDecoder()
            let json = try decoder.decode(APIBookSourceJSON.self, from: data)
            
            if json.bookSourceName.isEmpty || json.bookSourceUrl.isEmpty {
                return .error("源名称和URL不能为空")
            }
            
            let context = CoreDataStack.shared.viewContext
            let source = BookSource.create(in: context)
            applyJSONToBookSource(json, source)
            try context.save()
            
            return .success(.string(""))
        } catch {
            return .error("转换源失败: \(error.localizedDescription)")
        }
    }
    
    static func saveSources(_ body: String?) -> APIResponse {
        guard let body = body, !body.isEmpty else {
            return .error("数据为空")
        }
        
        guard let data = body.data(using: .utf8) else {
            return .error("数据格式错误")
        }
        
        do {
            let decoder = JSONDecoder()
            let jsonArray = try decoder.decode([APIBookSourceJSON].self, from: data)
            
            if jsonArray.isEmpty {
                return .error("转换源失败")
            }
            
            let context = CoreDataStack.shared.viewContext
            var okSources: [CodableValue] = []
            
            for json in jsonArray {
                if !json.bookSourceName.isEmpty && !json.bookSourceUrl.isEmpty {
                    let source = BookSource.create(in: context)
                    applyJSONToBookSource(json, source)
                    okSources.append(encodeBookSource(source))
                }
            }
            
            try context.save()
            return .success(.array(okSources))
        } catch {
            return .error("转换源失败: \(error.localizedDescription)")
        }
    }
    
    static func getSource(_ query: [String: String]) -> APIResponse {
        guard let url = query["url"], !url.isEmpty else {
            return .error("参数url不能为空，请指定源地址")
        }
        
        let context = CoreDataStack.shared.viewContext
        let fetchRequest: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "bookSourceUrl == %@", url)
        fetchRequest.fetchLimit = 1
        
        do {
            guard let source = try context.fetch(fetchRequest).first else {
                return .error("未找到源，请检查书源地址")
            }
            return .success(encodeBookSource(source))
        } catch {
            return .error("查询失败: \(error.localizedDescription)")
        }
    }
    
    static func deleteSources(_ body: String?) -> APIResponse {
        guard let body = body, !body.isEmpty else {
            return .error("数据为空")
        }
        
        guard let data = body.data(using: .utf8) else {
            return .error("数据格式错误")
        }
        
        do {
            let decoder = JSONDecoder()
            let jsonArray = try decoder.decode([APIBookSourceJSON].self, from: data)
            
            let context = CoreDataStack.shared.viewContext
            for json in jsonArray {
                let fetchRequest: NSFetchRequest<BookSource> = BookSource.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "bookSourceUrl == %@", json.bookSourceUrl)
                if let source = try context.fetch(fetchRequest).first {
                    context.delete(source)
                }
            }
            
            try context.save()
            return .success(.string("已执行"))
        } catch {
            return .error("删除失败: \(error.localizedDescription)")
        }
    }
    
    private static func encodeBookSource(_ source: BookSource) -> CodableValue {
        var dict: [String: CodableValue] = [:]
        dict["bookSourceUrl"] = .string(source.bookSourceUrl)
        dict["bookSourceName"] = .string(source.bookSourceName)
        dict["bookSourceGroup"] = .string(source.bookSourceGroup ?? "")
        dict["bookSourceType"] = .int(Int(source.bookSourceType))
        dict["enabled"] = .bool(source.enabled)
        dict["enabledExplore"] = .bool(source.enabledExplore)
        dict["searchUrl"] = .string(source.searchUrl ?? "")
        dict["exploreUrl"] = .string(source.exploreUrl ?? "")
        dict["weight"] = .int(Int(source.weight))
        dict["lastUpdateTime"] = .int(Int(source.lastUpdateTime))
        dict["respondTime"] = .int(Int(source.respondTime))
        dict["loginUrl"] = .string(source.loginUrl ?? "")
        dict["loginUi"] = .string(source.loginUi ?? "")
        dict["header"] = .string(source.header ?? "")
        return .dictionary(dict)
    }
    
    private static func applyJSONToBookSource(_ json: APIBookSourceJSON, _ source: BookSource) {
        source.bookSourceUrl = json.bookSourceUrl
        source.bookSourceName = json.bookSourceName
        source.bookSourceGroup = json.bookSourceGroup ?? ""
        source.bookSourceType = Int32(clamping: json.bookSourceType ?? 0)
        source.enabled = json.enabled ?? true
        source.enabledExplore = json.enabledExplore ?? true
        source.searchUrl = json.searchUrl ?? ""
        source.exploreUrl = json.exploreUrl ?? ""
        source.weight = Int32(clamping: json.weight ?? 0)
        source.lastUpdateTime = Int64(json.lastUpdateTime ?? 0)
        source.respondTime = Int64(json.respondTime ?? 60000)
        source.loginUrl = json.loginUrl ?? ""
        source.loginUi = json.loginUi ?? ""
        source.header = json.header ?? ""
    }
}

private struct APIBookSourceJSON: Codable {
    let bookSourceUrl: String
    let bookSourceName: String
    let bookSourceGroup: String?
    let bookSourceType: Int?
    let enabled: Bool?
    let enabledExplore: Bool?
    let searchUrl: String?
    let exploreUrl: String?
    let weight: Int?
    let lastUpdateTime: Int?
    let respondTime: Int?
    let loginUrl: String?
    let loginUi: String?
    let header: String?
}