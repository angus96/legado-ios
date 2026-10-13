//
//  SourceViewModel.swift
//  Legado-iOS
//
//  书源管理 ViewModel
//

import Foundation
import CoreData
import SwiftUI

@MainActor
class SourceViewModel: ObservableObject {
    @Published var sources: [BookSource] = []
    @Published var errorMessage: String?
    
    // MARK: - 分组管理
    @Published var allGroups: [String] = []
    @Published var selectedGroup: String?
    
    @AppStorage("customSourceGroups") private var customGroupsData: Data = Data()
    
    var customGroups: [String] {
        get {
            guard !customGroupsData.isEmpty,
                  let array = try? JSONDecoder().decode([String].self, from: customGroupsData) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                customGroupsData = data
            }
        }
    }
    
    var filteredSources: [BookSource] {
        if let group = selectedGroup {
            return sources.filter { $0.bookSourceGroup == group }
        }
        return sources
    }
    
    func updateGroups() {
        var groupSet = Set<String>()
        for source in sources {
            if let g = source.bookSourceGroup, !g.isEmpty {
                groupSet.insert(g)
            }
        }
        groupSet.formUnion(customGroups)
        allGroups = Array(groupSet).sorted()
    }
    
    func createGroup(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = customGroups
        if !current.contains(trimmed) {
            current.append(trimmed)
            customGroups = current
            updateGroups()
        }
    }
    
    func deleteGroup(_ name: String) {
        // 从书源中移除该分组
        let context = CoreDataStack.shared.viewContext
        var needsSave = false
        for source in sources where source.bookSourceGroup == name {
            source.bookSourceGroup = nil
            needsSave = true
        }
        if needsSave {
            try? context.save()
        }
        
        // 从自定义分组中移除
        var current = customGroups
        if let idx = current.firstIndex(of: name) {
            current.remove(at: idx)
            customGroups = current
        }
        
        if selectedGroup == name {
            selectedGroup = nil
        }
        
        updateGroups()
    }
    
    func loadSources() async {
        do {
            let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "customOrder", ascending: true)]
            request.includesPendingChanges = false
            
            sources = try CoreDataStack.shared.viewContext.fetch(request)
            updateGroups()
        } catch {
            errorMessage = "加载书源失败：\(error.localizedDescription)"
        }
    }
    
    func createSource(
        name: String,
        url: String,
        group: String,
        type: Int32,
        searchUrl: String,
        exploreUrl: String,
        ruleSearch: String,
        ruleBookInfo: String,
        ruleToc: String,
        ruleContent: String
    ) -> Bool {
        let context = CoreDataStack.shared.viewContext
        let source = BookSource.create(in: context)
        
        source.bookSourceName = name
        source.bookSourceUrl = url
        source.bookSourceGroup = group.isEmpty ? nil : group
        source.bookSourceType = type
        source.searchUrl = searchUrl.isEmpty ? nil : searchUrl
        source.exploreUrl = exploreUrl.isEmpty ? nil : exploreUrl
        do {
            source.ruleSearchData = try encodeRuleJSON(from: ruleSearch)
            source.ruleBookInfoData = try encodeRuleJSON(from: ruleBookInfo)
            source.ruleTocData = try encodeRuleJSON(from: ruleToc)
            source.ruleContentData = try encodeRuleJSON(from: ruleContent)
        } catch {
            context.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
        
        do {
            try CoreDataStack.shared.save()
            Task { await loadSources() }
            return true
        } catch {
            context.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
            Task { await loadSources() }
            return false
        }
    }
    
    func updateSource(
        _ source: BookSource,
        name: String,
        url: String,
        group: String,
        type: Int32,
        searchUrl: String,
        exploreUrl: String,
        ruleSearch: String,
        ruleBookInfo: String,
        ruleToc: String,
        ruleContent: String
    ) -> Bool {
        let context = CoreDataStack.shared.viewContext
        source.bookSourceName = name
        source.bookSourceUrl = url
        source.bookSourceGroup = group.isEmpty ? nil : group
        source.bookSourceType = type
        source.searchUrl = searchUrl.isEmpty ? nil : searchUrl
        source.exploreUrl = exploreUrl.isEmpty ? nil : exploreUrl
        do {
            source.ruleSearchData = try encodeRuleJSON(from: ruleSearch)
            source.ruleBookInfoData = try encodeRuleJSON(from: ruleBookInfo)
            source.ruleTocData = try encodeRuleJSON(from: ruleToc)
            source.ruleContentData = try encodeRuleJSON(from: ruleContent)
        } catch {
            context.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
        
        do {
            try CoreDataStack.shared.save()
            Task { await loadSources() }
            return true
        } catch {
            context.rollback()
            errorMessage = "保存失败：\(error.localizedDescription)"
            Task { await loadSources() }
            return false
        }
    }
    
    func deleteSource(_ source: BookSource) {
        let context = CoreDataStack.shared.viewContext
        context.delete(source)
        do {
            try CoreDataStack.shared.save()
        } catch {
            context.rollback()
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
        Task {
            await loadSources()
        }
    }
    
    func deleteSources(at indexSet: IndexSet) {
        let context = CoreDataStack.shared.viewContext
        for index in indexSet {
            context.delete(sources[index])
        }
        do {
            try CoreDataStack.shared.save()
        } catch {
            context.rollback()
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
        Task {
            await loadSources()
        }
    }
    
    func importFromURL(_ urlString: String) async -> Int {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        if let legado = parseLegadoImportLink(trimmed) {
            if legado.src.hasPrefix("[") || legado.src.hasPrefix("{") {
                return importFromText(legado.src)
            }
            return await importFromRemoteURL(legado.src, requestWithoutUA: legado.requestWithoutUA)
        }

        return await importFromRemoteURL(trimmed, requestWithoutUA: false)
    }

    private func importFromRemoteURL(_ urlString: String, requestWithoutUA: Bool) async -> Int {
        guard let url = URL(string: urlString) else {
            errorMessage = "无效的 URL"
            return 0
        }

        do {
            let data: Data
            if requestWithoutUA {
                var request = URLRequest(url: url)
                request.setValue("null", forHTTPHeaderField: "User-Agent")
                let (d, _) = try await URLSession.shared.data(for: request)
                data = d
            } else {
                let (d, _) = try await URLSession.shared.data(from: url)
                data = d
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return importFromJSON(json)
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return importSingleSource(json)
            }
            errorMessage = "导入失败：不支持的 JSON 格式"
            return 0
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
            return 0
        }
    }

    private func parseLegadoImportLink(_ input: String) -> (src: String, requestWithoutUA: Bool)? {
        guard let url = URL(string: input), url.scheme == "legado" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let srcItem = components.queryItems?.first(where: { $0.name == "src" }),
              let srcValue = srcItem.value, !srcValue.isEmpty else {
            return nil
        }

        let decoded = srcValue.removingPercentEncoding ?? srcValue
        var src = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        var requestWithoutUA = false
        if src.hasSuffix("#requestWithoutUA") {
            requestWithoutUA = true
            src = String(src.dropLast("#requestWithoutUA".count))
        }

        if src.isEmpty { return nil }
        return (src: src, requestWithoutUA: requestWithoutUA)
    }
    
    func importFromText(_ text: String) -> Int {
        guard let data = text.data(using: .utf8) else {
            errorMessage = "无效的文本"
            return 0
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return importFromJSON(json)
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return importSingleSource(json)
            }
            errorMessage = "导入失败：不支持的 JSON 格式"
            return 0
        } catch {
            errorMessage = "解析 JSON 失败：\(error.localizedDescription)"
            return 0
        }
    }

    func importFromFiles(_ urls: [URL]) async -> SourceImportSummary {
        errorMessage = nil

        var summary = SourceImportSummary()
        guard !urls.isEmpty else {
            summary.failedCount = 1
            summary.detailMessage = "未选择文件"
            return summary
        }

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let parsed = try Self.parseSourceFile(data: data, fileExtension: url.pathExtension.lowercased())
                let fileSummary = importParsedSources(parsed)
                summary.merge(fileSummary)
            } catch {
                summary.failedCount += 1
                summary.detailMessage = "文件导入失败：\(error.localizedDescription)"
            }
        }

        return summary
    }
    
    private func importFromJSON(_ sources: [[String: Any]]) -> Int {
        let context = CoreDataStack.shared.viewContext

        var importedCount = 0
        for sourceData in sources {
            guard let url = sourceData["bookSourceUrl"] as? String, !url.isEmpty,
                  let name = sourceData["bookSourceName"] as? String, !name.isEmpty else {
                continue
            }

            let source = findOrCreateSource(for: sourceData, in: context)
            source.bookSourceUrl = url
            source.bookSourceName = name
            applySourceData(source, sourceData)
            importedCount += 1
        }
        
        do {
            try CoreDataStack.shared.save()
            Task { await loadSources() }
            return importedCount
        } catch {
            context.rollback()
            errorMessage = "导入失败：\(error.localizedDescription)"
            Task { await loadSources() }
            return 0
        }
    }
    
    private func importSingleSource(_ sourceData: [String: Any]) -> Int {
        let context = CoreDataStack.shared.viewContext
        guard let url = sourceData["bookSourceUrl"] as? String, !url.isEmpty,
              let name = sourceData["bookSourceName"] as? String, !name.isEmpty else {
            errorMessage = "导入失败：书源数据缺少必要字段"
            return 0
        }

        let source = findOrCreateSource(for: sourceData, in: context)
        source.bookSourceUrl = url
        source.bookSourceName = name
        applySourceData(source, sourceData)

        do {
            try CoreDataStack.shared.save()
            Task { await loadSources() }
            return 1
        } catch {
            context.rollback()
            errorMessage = "导入失败：\(error.localizedDescription)"
            Task { await loadSources() }
            return 0
        }
    }

    private func importParsedSources(_ parsed: ParsedSourceFile) -> SourceImportSummary {
        let context = CoreDataStack.shared.viewContext
        var summary = SourceImportSummary(failedCount: parsed.failedCount)
        var seenUrls = Set<String>()

        for candidate in parsed.candidates {
            if seenUrls.contains(candidate.bookSourceUrl) {
                summary.skippedCount += 1
                continue
            }

            let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "bookSourceUrl == %@", candidate.bookSourceUrl)

            if (try? context.fetch(request).first) != nil {
                summary.skippedCount += 1
                seenUrls.insert(candidate.bookSourceUrl)
                continue
            }

            let source = BookSource.create(in: context)
            source.bookSourceUrl = candidate.bookSourceUrl
            source.bookSourceName = candidate.bookSourceName
            applySourceData(source, candidate.rawData)
            seenUrls.insert(candidate.bookSourceUrl)
            summary.successCount += 1
        }

        do {
            try CoreDataStack.shared.save()
            Task { await loadSources() }
        } catch {
            context.rollback()
            summary.detailMessage = "保存失败：\(error.localizedDescription)"
            summary.failedCount += summary.successCount
            summary.successCount = 0
            Task { await loadSources() }
        }

        return summary
    }

    private func int32Value(_ value: Any?) -> Int32? { JSONNumber.int32(value) }

    private func int64Value(_ value: Any?) -> Int64? { JSONNumber.int64(value) }

    private func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool:
            return b
        case let n as NSNumber:
            return n.boolValue
        case let s as String:
            let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "y"].contains(v) { return true }
            if ["false", "0", "no", "n"].contains(v) { return false }
            return nil
        default:
            return nil
        }
    }

    private func jsonDataValue(_ value: Any?) -> Data? {
        guard let value else { return nil }
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        return try? JSONSerialization.data(withJSONObject: value)
    }

    private func findOrCreateSource(for data: [String: Any], in context: NSManagedObjectContext) -> BookSource {
        let url = data["bookSourceUrl"] as? String ?? ""
        if !url.isEmpty {
            let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "bookSourceUrl == %@", url)
            if let existing = try? context.fetch(request).first {
                return existing
            }
        }
        return BookSource.create(in: context)
    }

    private func encodeRuleJSON(from text: String) throws -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw SourceValidationError.invalidEncoding
        }
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: jsonObject)
    }

    private static func parseSourceFile(data: Data, fileExtension: String) throws -> ParsedSourceFile {
        switch fileExtension {
        case "txt":
            return try parseTextSourceFile(data: data)
        case "json":
            return try parseJSONSourceFile(data: data)
        default:
            if let json = try? parseJSONSourceFile(data: data) {
                return json
            }
            return try parseTextSourceFile(data: data)
        }
    }

    private static func parseJSONSourceFile(data: Data) throws -> ParsedSourceFile {
        let object = try JSONSerialization.jsonObject(with: data)

        if let sources = object as? [[String: Any]] {
            return validateSourceObjects(sources)
        }

        if let source = object as? [String: Any] {
            return validateSourceObjects([source])
        }

        throw SourceImportError.unsupportedJSONFormat
    }

    private static func parseTextSourceFile(data: Data) throws -> ParsedSourceFile {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SourceImportError.invalidEncoding
        }

        var candidates: [SourceImportCandidate] = []
        var failedCount = 0

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData),
                  let source = json as? [String: Any] else {
                failedCount += 1
                continue
            }

            if let candidate = validateSourceObject(source) {
                candidates.append(candidate)
            } else {
                failedCount += 1
            }
        }

        return ParsedSourceFile(candidates: candidates, failedCount: failedCount)
    }

    private static func validateSourceObjects(_ objects: [[String: Any]]) -> ParsedSourceFile {
        var candidates: [SourceImportCandidate] = []
        var failedCount = 0

        for object in objects {
            if let candidate = validateSourceObject(object) {
                candidates.append(candidate)
            } else {
                failedCount += 1
            }
        }

        return ParsedSourceFile(candidates: candidates, failedCount: failedCount)
    }

    private static func validateSourceObject(_ object: [String: Any]) -> SourceImportCandidate? {
        guard let url = normalizedStringValue(object["bookSourceUrl"]),
              let name = normalizedStringValue(object["bookSourceName"]),
              !url.isEmpty,
              !name.isEmpty else {
            return nil
        }

        return SourceImportCandidate(bookSourceUrl: url, bookSourceName: name, rawData: object)
    }

    private static func normalizedStringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return nil
        }
    }
    
    private func applySourceData(_ source: BookSource, _ data: [String: Any]) {
        source.bookSourceGroup = data["bookSourceGroup"] as? String
        if let v = int32Value(data["bookSourceType"]) { source.bookSourceType = v }
        if let v = int32Value(data["customOrder"]) { source.customOrder = v }
        if let v = boolValue(data["enabled"]) { source.enabled = v }
        if let v = boolValue(data["enabledExplore"]) { source.enabledExplore = v }
        if let v = boolValue(data["enabledCookieJar"]) { source.enabledCookieJar = v }
        if let v = int32Value(data["weight"]) { source.weight = v }
        if let v = int64Value(data["respondTime"]) { source.respondTime = v }
        if let v = int64Value(data["lastUpdateTime"]) { source.lastUpdateTime = v }

        source.bookUrlPattern = data["bookUrlPattern"] as? String
        source.concurrentRate = data["concurrentRate"] as? String
        source.header = data["header"] as? String
        source.loginUrl = data["loginUrl"] as? String
        source.loginUi = data["loginUi"] as? String
        source.loginCheckJs = data["loginCheckJs"] as? String
        source.coverDecodeJs = data["coverDecodeJs"] as? String
        source.jsLib = data["jsLib"] as? String

        source.bookSourceComment = data["bookSourceComment"] as? String
        source.variableComment = data["variableComment"] as? String
        source.variable = data["variable"] as? String

        source.searchUrl = data["searchUrl"] as? String
        source.exploreUrl = data["exploreUrl"] as? String
        source.exploreScreen = data["exploreScreen"] as? String

        if let v = jsonDataValue(data["ruleSearch"]) { source.ruleSearchData = v }
        if let v = jsonDataValue(data["ruleExplore"]) { source.ruleExploreData = v }
        if let v = jsonDataValue(data["ruleBookInfo"]) { source.ruleBookInfoData = v }
        if let v = jsonDataValue(data["ruleToc"]) { source.ruleTocData = v }
        if let v = jsonDataValue(data["ruleContent"]) { source.ruleContentData = v }
        if let v = jsonDataValue(data["ruleReview"]) { source.ruleReviewData = v }
    }
    
    func exportAllSources() -> Data? {
        let exportSources = sources.map { ExportableSource(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(exportSources)
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }
}

private enum SourceValidationError: LocalizedError {
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "规则内容编码无效"
        }
    }
}

private enum SourceImportError: LocalizedError {
    case invalidEncoding
    case unsupportedJSONFormat

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "文件编码无效"
        case .unsupportedJSONFormat:
            return "不支持的 JSON 格式"
        }
    }
}

struct SourceImportSummary {
    var successCount: Int = 0
    var skippedCount: Int = 0
    var failedCount: Int = 0
    var detailMessage: String?

    mutating func merge(_ other: SourceImportSummary) {
        successCount += other.successCount
        skippedCount += other.skippedCount
        failedCount += other.failedCount
        if detailMessage == nil {
            detailMessage = other.detailMessage
        }
    }

    var message: String {
        let base = "成功 \(successCount) 个，跳过 \(skippedCount) 个，失败 \(failedCount) 个"
        if let detailMessage, !detailMessage.isEmpty {
            return base + "\n" + detailMessage
        }
        return base
    }
}

private struct SourceImportCandidate {
    let bookSourceUrl: String
    let bookSourceName: String
    let rawData: [String: Any]
}

private struct ParsedSourceFile {
    let candidates: [SourceImportCandidate]
    let failedCount: Int
}
