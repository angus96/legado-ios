import Foundation
import CoreData

@MainActor
class RuleSubscriptionManager: ObservableObject {
    @Published var subscriptions: [RuleSub] = []
    @Published var isUpdating = false
    @Published var updateProgress: Double = 0
    @Published var lastError: String?

    private let context = CoreDataStack.shared.viewContext

    func loadSubscriptions(type: RuleSub.SubType? = nil) {
        let request: NSFetchRequest<RuleSub> = RuleSub.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "customOrder", ascending: true)]
        if let type = type {
            request.predicate = NSPredicate(format: "type == %d", type.rawValue)
        }
        subscriptions = (try? context.fetch(request)) ?? []
    }

    func addSubscription(name: String, url: String, type: RuleSub.SubType, autoUpdate: Bool = true) {
        let sub = RuleSub.create(in: context)
        sub.name = name
        sub.url = url
        sub.type = type.rawValue
        sub.autoUpdate = autoUpdate
        sub.customOrder = Int32(subscriptions.count)
        try? context.save()
        loadSubscriptions(type: type)
    }

    func deleteSubscription(_ sub: RuleSub) {
        context.delete(sub)
        try? context.save()
        if let type = sub.subType {
            loadSubscriptions(type: type)
        }
    }

    func updateSubscription(_ sub: RuleSub, name: String? = nil, url: String? = nil, autoUpdate: Bool? = nil) {
        if let name = name { sub.name = name }
        if let url = url { sub.url = url }
        if let autoUpdate = autoUpdate { sub.autoUpdate = autoUpdate }
        try? context.save()
    }

    func moveSubscription(from source: IndexSet, to destination: Int) {
        var mutable = subscriptions
        mutable.move(fromOffsets: source, toOffset: destination)
        for (index, sub) in mutable.enumerated() {
            sub.customOrder = Int32(index)
        }
        try? context.save()
    }

    func updateSubscription(id: Int64) async throws {
        guard let sub = subscriptions.first(where: { $0.id == id }) else {
            throw RuleSubError.notFound
        }
        try await performUpdate(sub)
    }

    func updateAllSubscriptions() async {
        guard !isUpdating else { return }
        isUpdating = true
        updateProgress = 0
        lastError = nil

        let total = Double(subscriptions.filter { $0.autoUpdate }.count)
        var completed = 0.0

        for sub in subscriptions where sub.autoUpdate {
            do {
                try await performUpdate(sub)
            } catch {
                lastError = "更新 [\(sub.name)] 失败: \(error.localizedDescription)"
            }
            completed += 1
            updateProgress = total > 0 ? completed / total : 0
        }

        isUpdating = false
        updateProgress = 1.0
    }

    private func performUpdate(_ sub: RuleSub) async throws {
        guard let url = URL(string: sub.url) else {
            throw RuleSubError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw RuleSubError.networkError
        }

        try await importRuleData(data, type: sub.subType ?? .bookSource)

        sub.lastUpdateTime = Int64(Date().timeIntervalSince1970 * 1000)
        try context.save()
    }

    private func importRuleData(_ data: Data, type: RuleSub.SubType) async throws {
        switch type {
        case .bookSource:
            try importBookSources(data)
        case .rssSource:
            try importRssSources(data)
        case .replaceRule:
            try importReplaceRules(data)
        case .httpTTS:
            try importHttpTTS(data)
        case .dictRule:
            try importDictRules(data)
        case .txtTocRule:
            try importTxtTocRules(data)
        }
    }

    private func importBookSources(_ data: Data) throws {
        let sources = try JSONDecoder().decode([ExportableSource].self, from: data)
        for source in sources {
            let request = BookSource.fetchRequest()
            request.predicate = NSPredicate(format: "bookSourceUrl == %@", source.bookSourceUrl)
            if let existing = try? context.fetch(request).first {
                updateBookSourceFromExportable(existing, source)
            } else {
                let newSource = BookSource.create(in: context)
                updateBookSourceFromExportable(newSource, source)
            }
        }
        try context.save()
    }

    private func updateBookSourceFromExportable(_ bs: BookSource, _ source: ExportableSource) {
        bs.bookSourceUrl = source.bookSourceUrl
        bs.bookSourceName = source.bookSourceName
        bs.bookSourceGroup = source.bookSourceGroup
        bs.bookSourceType = Int32(clamping: source.bookSourceType ?? 0)
        bs.bookUrlPattern = source.bookUrlPattern
        bs.header = source.header
        bs.concurrentRate = source.concurrentRate
        bs.loginUrl = source.loginUrl
        bs.searchUrl = source.searchUrl
        bs.exploreUrl = source.exploreUrl
        bs.enabled = source.enabled ?? true
        bs.enabledExplore = source.enabledExplore ?? true
        bs.weight = Int32(clamping: source.weight ?? 0)
        bs.lastUpdateTime = Int64(Date().timeIntervalSince1970)
    }

    private func importRssSources(_ data: Data) throws {
        if let array = try? JSONDecoder().decode([RssSourceCodable].self, from: data) {
            for item in array {
                let request = RssSource.fetchRequest()
                request.predicate = NSPredicate(format: "sourceUrl == %@", item.sourceUrl)
                if let existing = try? context.fetch(request).first {
                    updateRssSource(existing, item)
                } else {
                    let newSource = RssSource.create(in: context)
                    updateRssSource(newSource, item)
                }
            }
            try context.save()
        }
    }

    private func updateRssSource(_ source: RssSource, _ item: RssSourceCodable) {
        source.sourceUrl = item.sourceUrl
        source.sourceName = item.sourceName
        source.sourceIcon = item.sourceIcon
        source.sourceGroup = item.sourceGroup
        source.enabled = item.enabled ?? true
        source.sortUrl = item.sortUrl
        source.articleStyle = Int32(item.articleStyle ?? 0)
    }

    private func importReplaceRules(_ data: Data) throws {
        if let array = try? JSONDecoder().decode([ReplaceRuleCodable].self, from: data) {
            for item in array {
                let request = ReplaceRule.fetchRequest()
                request.predicate = NSPredicate(format: "ruleId == %@", replaceRuleUUID(from: item.id) as CVarArg)
                if let existing = try? context.fetch(request).first {
                    updateReplaceRule(existing, item)
                } else {
                    let newRule = ReplaceRule.create(in: context)
                    updateReplaceRule(newRule, item)
                }
            }
            try context.save()
        }
    }

    private func updateReplaceRule(_ rule: ReplaceRule, _ item: ReplaceRuleCodable) {
        rule.ruleId = replaceRuleUUID(from: item.id)
        rule.name = item.name
        rule.scopeId = item.group
        rule.pattern = item.pattern
        rule.replacement = item.replacement
        rule.isRegex = item.isRegex
        rule.scope = item.scope ?? "global"
        rule.enabled = item.enabled
        rule.order = Int32(item.order)
    }

    private func replaceRuleUUID(from legacyId: Int64) -> UUID {
        let normalized = UInt64(bitPattern: legacyId)
        let suffix = String(format: "%012llx", normalized)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") ?? UUID()
    }

    private func importHttpTTS(_ data: Data) throws {
        if let array = try? JSONDecoder().decode([HttpTTSCodable].self, from: data) {
            for item in array {
                let request = HttpTTS.fetchRequest()
                request.predicate = NSPredicate(format: "id == %lld", item.id)
                if let existing = try? context.fetch(request).first {
                    updateHttpTTS(existing, item)
                } else {
                    let newTTS = HttpTTS.create(in: context)
                    updateHttpTTS(newTTS, item)
                }
            }
            try context.save()
        }
    }

    private func updateHttpTTS(_ tts: HttpTTS, _ item: HttpTTSCodable) {
        tts.id = item.id
        tts.name = item.name
        tts.url = item.url
    }

    private func importDictRules(_ data: Data) throws {
        if let array = try? JSONDecoder().decode([DictRuleCodable].self, from: data) {
            for item in array {
                let request = DictRule.fetchRequest()
                request.predicate = NSPredicate(format: "name == %@", item.name)
                if let existing = try? context.fetch(request).first {
                    updateDictRule(existing, item)
                } else {
                    let newRule = DictRule.create(in: context)
                    updateDictRule(newRule, item)
                }
            }
            try context.save()
        }
    }

    private func updateDictRule(_ rule: DictRule, _ item: DictRuleCodable) {
        rule.name = item.name
        rule.urlRule = item.urlRule
        rule.showRule = item.showRule ?? ""
        rule.enabled = item.enabled
    }

    private func importTxtTocRules(_ data: Data) throws {
        if let array = try? JSONDecoder().decode([TxtTocRuleCodable].self, from: data) {
            for item in array {
                let request = TxtTocRule.fetchRequest()
                request.predicate = NSPredicate(format: "name == %@", item.name)
                if let existing = try? context.fetch(request).first {
                    updateTxtTocRule(existing, item)
                } else {
                    let newRule = TxtTocRule.create(in: context)
                    updateTxtTocRule(newRule, item)
                }
            }
            try context.save()
        }
    }

    private func updateTxtTocRule(_ rule: TxtTocRule, _ item: TxtTocRuleCodable) {
        rule.name = item.name
        rule.rule = item.rule
        rule.enabled = item.enabled
    }
}

struct RssSourceCodable: Codable {
    var sourceUrl: String
    var sourceName: String
    var sourceIcon: String?
    var sourceGroup: String?
    var enabled: Bool?
    var sortUrl: String?
    var articleStyle: Int?
}

struct ReplaceRuleCodable: Codable {
    var id: Int64
    var name: String
    var group: String?
    var pattern: String
    var replacement: String
    var isRegex: Bool
    var scope: String?
    var enabled: Bool
    var order: Int
}

struct HttpTTSCodable: Codable {
    var id: Int64
    var name: String
    var url: String
}

struct DictRuleCodable: Codable {
    var name: String
    var urlRule: String
    var showRule: String?
    var enabled: Bool
}

struct TxtTocRuleCodable: Codable {
    var name: String
    var rule: String
    var enabled: Bool
}

enum RuleSubError: LocalizedError {
    case invalidUrl
    case networkError
    case parseError
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidUrl: return "无效的订阅URL"
        case .networkError: return "网络请求失败"
        case .parseError: return "解析规则数据失败"
        case .notFound: return "订阅不存在"
        }
    }
}
