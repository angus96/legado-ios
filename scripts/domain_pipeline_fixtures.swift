import Foundation
import CoreData

final class DebugLogger {
    static let shared = DebugLogger()
    func log(_ message: String) { print("LOG: \(message)") }
}

// 本机命令行测试只覆盖普通 HTTP 请求；WebKit 需要在 iOS 运行环境验证。
final class BackstageWebView {
    init(url: String, html: String? = nil, tag: String? = nil, headerMap: [String: String],
         sourceRegex: String? = nil, javaScript: String? = nil, delayTime: Int64) {}
    func getStrResponse() async throws -> StrResponse { throw URLError(.unsupportedURL) }
}

final class CoreDataStack {
    static let shared = CoreDataStack()
    var persistentContainer: NSPersistentContainer!
    var viewContext: NSManagedObjectContext { persistentContainer.viewContext }
    func newBackgroundContext() -> NSManagedObjectContext { persistentContainer.newBackgroundContext() }
}

func loadTestModel(_ url: URL) throws -> NSManagedObjectModel {
    let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
    let types: [String: NSAttributeType] = [
        "String": .stringAttributeType, "UUID": .UUIDAttributeType, "Date": .dateAttributeType,
        "Binary": .binaryDataAttributeType, "Boolean": .booleanAttributeType,
        "Integer 16": .integer16AttributeType, "Integer 32": .integer32AttributeType,
        "Integer 64": .integer64AttributeType, "Double": .doubleAttributeType, "Float": .floatAttributeType,
        "Transformable": .transformableAttributeType,
    ]
    var entities: [String: NSEntityDescription] = [:]
    for row in rows {
        let name = row["name"] as! String
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = ["Book", "BookSource", "BookChapter", "Cookie"].contains(name) ? name : "NSManagedObject"
        entity.properties = (row["attributes"] as! [[String: String]]).map { item in
            let attribute = NSAttributeDescription()
            attribute.name = item["name"]!
            attribute.attributeType = types[item["attributeType"]!]!
            attribute.isOptional = item["optional"] == "YES"
            if let value = item["defaultValueString"] {
                switch attribute.attributeType {
                case .booleanAttributeType: attribute.defaultValue = value == "YES"
                case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: attribute.defaultValue = Int64(value)
                case .doubleAttributeType, .floatAttributeType: attribute.defaultValue = Double(value)
                default: attribute.defaultValue = value
                }
            }
            return attribute
        }
        entities[name] = entity
    }
    for row in rows {
        let entity = entities[row["name"] as! String]!
        for item in row["relationships"] as! [[String: String]] {
            let relation = NSRelationshipDescription()
            relation.name = item["name"]!
            relation.destinationEntity = entities[item["destinationEntity"]!]
            relation.isOptional = item["optional"] == "YES"
            relation.minCount = Int(item["minCount"] ?? "0")!
            relation.maxCount = item["toMany"] == "YES" ? 0 : 1
            relation.deleteRule = item["deletionRule"] == "Cascade" ? .cascadeDeleteRule : .nullifyDeleteRule
            entity.properties.append(relation)
        }
    }
    for row in rows {
        let entity = entities[row["name"] as! String]!
        for item in row["relationships"] as! [[String: String]] {
            if let inverse = item["inverseName"], let target = item["inverseEntity"] {
                entity.relationshipsByName[item["name"]!]?.inverseRelationship = entities[target]?.relationshipsByName[inverse]
            }
        }
    }
    let model = NSManagedObjectModel()
    model.entities = Array(entities.values)
    return model
}
