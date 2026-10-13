import Foundation
import CoreData

enum BackupStoreError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let detail) = self { return "备份格式不正确：\(detail)" }
        return nil
    }
}

/// 备份数据库字段；正文文件和本地 EPUB/TXT 文件由用户另行保留。
enum BackupStore {
    static let entities = ["sources": "BookSource", "books": "Book", "rules": "ReplaceRule",
                           "chapters": "BookChapter", "bookmarks": "Bookmark"]
    private static let identities = ["BookSource": "sourceId", "Book": "bookId", "ReplaceRule": "ruleId",
                                     "BookChapter": "chapterId", "Bookmark": "bookmarkId"]

    static func export(context: NSManagedObjectContext) throws -> [String: Any] {
        try context.performAndWait {
            var payload: [String: Any] = ["version": "2.0", "timestamp": Date().timeIntervalSince1970]
            for (key, entity) in entities {
                let objects = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
                payload[key] = try objects.map { object -> [String: Any] in
                    var fields: [String: Any] = [:]
                    for (name, attribute) in object.entity.attributesByName {
                        guard let value = object.value(forKey: name) else { continue }
                        if let data = value as? Data {
                            if name.hasPrefix("rule"), name.hasSuffix("Data"),
                               let json = try? JSONSerialization.jsonObject(with: data) {
                                fields[String(name.dropLast(4))] = json
                            } else {
                                fields[name] = ["base64": data.base64EncodedString()]
                            }
                        } else if attribute.attributeType == .UUIDAttributeType, let uuid = value as? UUID {
                            fields[name] = uuid.uuidString
                        } else if let date = value as? Date {
                            fields[name] = date.timeIntervalSince1970
                        } else {
                            fields[name] = value
                        }
                    }
                    return fields
                }
            }
            return payload
        }
    }

    static func payload(from files: [String: Data]) throws -> [String: Any] {
        let names = ["sources": ["bookSources.json", "bookSource.json"], "books": ["books.json"],
                     "rules": ["replaceRules.json"], "chapters": ["bookChapters.json"], "bookmarks": ["bookmarks.json"]]
        var payload: [String: Any] = [:]
        for (key, candidates) in names {
            if let data = candidates.compactMap({ files[$0] }).first {
                payload[key] = try JSONSerialization.jsonObject(with: data)
            }
        }
        _ = try validatedRecords(payload)
        return payload
    }

    static func restore(_ payload: [String: Any], container: NSPersistentContainer) throws -> [String: Int] {
        let records = try validatedRecords(payload)
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return try context.performAndWait {
            do {
                var counts: [String: Int] = [:]
                var bookAliases: [String: UUID] = [:]
                for key in ["sources", "books", "rules", "chapters", "bookmarks"] {
                    guard let rows = records[key], let entityName = entities[key] else { continue }
                    for var row in rows {
                        if key == "chapters" || key == "bookmarks" {
                            if let original = row["bookId"] as? String, let actual = bookAliases[original] {
                                row["bookId"] = actual.uuidString
                            }
                        }
                        let object = try findOrCreate(entity: entityName, fields: row, context: context)
                        let previousURL = object.entity.name == "Book" ? object.value(forKey: "bookUrl") as? String : nil
                        let previousOrigin = object.entity.name == "Book" ? object.value(forKey: "origin") as? String : nil
                        try apply(row, to: object)
                        if key == "books" {
                            if let incoming = row["bookId"] as? String, let actual = object.value(forKey: "bookId") as? UUID {
                                bookAliases[incoming] = actual
                            }
                            if let previousURL, previousURL != object.value(forKey: "bookUrl") as? String ||
                                previousOrigin != object.value(forKey: "origin") as? String {
                                if let chapters = object.value(forKey: "chapters") as? Set<NSManagedObject> {
                                    chapters.forEach { context.delete($0) }
                                }
                            }
                            let origin = object.value(forKey: "origin") as? String ?? ""
                            let sourceRequest = NSFetchRequest<NSManagedObject>(entityName: "BookSource")
                            if let id = UUID(uuidString: origin) {
                                sourceRequest.predicate = NSPredicate(format: "sourceId == %@", id as CVarArg)
                            } else { sourceRequest.predicate = NSPredicate(format: "bookSourceUrl == %@", origin) }
                            object.setValue(try context.fetch(sourceRequest).first, forKey: "source")
                        } else if key == "chapters" || key == "bookmarks" {
                            let request = NSFetchRequest<NSManagedObject>(entityName: "Book")
                            guard let bookID = object.value(forKey: "bookId") as? UUID else { throw BackupStoreError.invalid("缺少书籍编号") }
                            request.predicate = NSPredicate(format: "bookId == %@", bookID as CVarArg)
                            guard let book = try context.fetch(request).first else { throw BackupStoreError.invalid("章节或书签对应的书籍不存在") }
                            object.setValue(book, forKey: "book")
                            if key == "chapters" {
                                // 备份中的缓存路径不能证明本机仍然存在相应正文。
                                object.setValue(false, forKey: "isCached")
                            }
                        }
                    }
                    counts[key] = rows.count
                }
                try context.save()
                return counts
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    static func validatedRecords(_ payload: [String: Any]) throws -> [String: [[String: Any]]] {
        var result: [String: [[String: Any]]] = [:]
        for key in entities.keys {
            guard let raw = payload[key] else { continue }
            guard let rows = raw as? [[String: Any]] else { throw BackupStoreError.invalid("\(key) 必须是列表") }
            for row in rows {
                let required: [String]
                switch key {
                case "sources": required = ["bookSourceUrl"]
                case "books": required = ["bookUrl"]
                case "rules": required = ["pattern"]
                case "chapters": required = ["bookId", "chapterUrl", "title"]
                default: required = ["bookId", "chapterTitle", "content"]
                }
                for name in required {
                    guard let value = row[name] as? String, (name == "pattern" || name == "content" || !value.isEmpty) else {
                        throw BackupStoreError.invalid("\(key) 缺少 \(name)")
                    }
                }
            }
            result[key] = rows
        }
        guard !result.isEmpty else { throw BackupStoreError.invalid("未找到书籍、书源或规则数据") }
        return result
    }

    private static func findOrCreate(entity: String, fields: [String: Any], context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.fetchLimit = 1
        if let identity = identities[entity], let text = fields[identity] as? String, let id = UUID(uuidString: text) {
            request.predicate = NSPredicate(format: "%K == %@", identity, id as CVarArg)
            if let existing = try context.fetch(request).first { return existing }
        }
        if entity == "BookSource", let url = fields["bookSourceUrl"] as? String {
            request.predicate = NSPredicate(format: "bookSourceUrl == %@", url)
        } else if entity == "Book", let url = fields["bookUrl"] as? String {
            request.predicate = NSPredicate(format: "bookUrl == %@ AND origin == %@", url, fields["origin"] as? String ?? "")
        } else if entity == "BookChapter", let text = fields["bookId"] as? String,
                  let id = UUID(uuidString: text), let index = JSONNumber.int32(fields["index"]) {
            request.predicate = NSPredicate(format: "bookId == %@ AND index == %d", id as CVarArg, index)
        } else { request.predicate = NSPredicate(value: false) }
        if let existing = try context.fetch(request).first { return existing }
        let object = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        for (name, attribute) in object.entity.attributesByName where !attribute.isOptional && object.value(forKey: name) == nil {
            switch attribute.attributeType {
            case .stringAttributeType: object.setValue("", forKey: name)
            case .UUIDAttributeType: object.setValue(UUID(), forKey: name)
            case .dateAttributeType: object.setValue(Date(), forKey: name)
            default: break
            }
        }
        if let identity = identities[entity], let text = fields[identity] as? String, let id = UUID(uuidString: text) {
            object.setValue(id, forKey: identity)
        }
        return object
    }

    private static func apply(_ fields: [String: Any], to object: NSManagedObject) throws {
        for (name, attribute) in object.entity.attributesByName {
            if name == identities[object.entity.name ?? ""] { continue }
            let raw = fields[name] ?? (name.hasPrefix("rule") && name.hasSuffix("Data") ? fields[String(name.dropLast(4))] : nil)
            guard let raw else { continue }
            if raw is NSNull, attribute.isOptional { object.setValue(nil, forKey: name); continue }
            let value: Any?
            switch attribute.attributeType {
            case .stringAttributeType: value = raw as? String
            case .integer32AttributeType: value = JSONNumber.int32(raw)
            case .integer64AttributeType: value = JSONNumber.int64(raw)
            case .booleanAttributeType:
                if let number = raw as? NSNumber { value = number.boolValue }
                else if let text = raw as? String { value = (text as NSString).boolValue }
                else { value = nil }
            case .UUIDAttributeType: value = (raw as? String).flatMap(UUID.init(uuidString:))
            case .dateAttributeType:
                if let number = raw as? NSNumber, number.doubleValue.isFinite { value = Date(timeIntervalSince1970: number.doubleValue) }
                else { value = (raw as? String).flatMap { ISO8601DateFormatter().date(from: $0) } }
            case .binaryDataAttributeType:
                if let encoded = (raw as? [String: Any])?["base64"] as? String { value = Data(base64Encoded: encoded) }
                else if JSONSerialization.isValidJSONObject(raw) { value = try JSONSerialization.data(withJSONObject: raw) }
                else { value = nil }
            default: value = raw
            }
            guard let value else { throw BackupStoreError.invalid("\(object.entity.name ?? "").\(name) 的值无效或超出范围") }
            object.setValue(value, forKey: name)
        }
    }
}
