//
//  RuleAnalyzer.swift
//  Legado-iOS
//
//  通用的规则切分处理 - 对标 Android RuleAnalyzer.kt
//

import Foundation

/// 规则分析器 - 处理规则字符串的切分和解析
class RuleAnalyzer {
    private let queue: String       // 被处理字符串
    private let characters: [Character]
    private let indices: [String.Index]
    private var pos: Int = 0        // 当前处理到的位置
    private var start: Int = 0      // 当前处理字段的开始
    private var startX: Int = 0     // 当前规则的开始
    
    private var rules: [String] = []  // 分割出的规则列表
    var elementsType: String = ""     // 当前分割字符串
    
    private let isCode: Bool          // 是否为代码模式
    
    init(data: String, code: Bool = false) {
        self.queue = data
        self.characters = Array(data)
        self.indices = Array(data.indices) + [data.endIndex]
        self.isCode = code
    }
    
    // MARK: - 修剪
    
    /// 修剪当前规则之前的"@"或者空白符
    func trim() {
        if pos >= characters.count { return }
        let char = queue[indices[pos]]
        if char == "@" || char < "!" {
            pos += 1
            while pos < characters.count {
                let c = queue[indices[pos]]
                if c != "@" && c >= "!" { break }
                pos += 1
            }
            start = pos
            startX = pos
        }
    }
    
    /// 将pos重置为0，方便复用
    func reSetPos() {
        pos = 0
        start = 0
        startX = 0
        rules.removeAll()
        elementsType = ""
    }
    
    // MARK: - 查找方法
    
    /// 从剩余字串中拉出一个字符串，直到但不包括匹配序列
    /// - Parameter seq: 查找的字符串（区分大小写）
    /// - Returns: 是否找到相应字段
    private func consumeTo(_ seq: String) -> Bool {
        guard !seq.isEmpty, pos >= 0, pos <= characters.count else { return false }
        start = pos
        let cursor = indices[pos]
        guard let range = queue.range(of: seq, range: cursor..<queue.endIndex) else {
            return false
        }
        pos = queue.distance(from: queue.startIndex, to: range.lowerBound)
        return true
    }
    
    /// 从剩余字串中拉出一个字符串，直到匹配序列中一项
    /// - Parameter seqs: 匹配字符串序列
    /// - Returns: 成功返回true并设置间隔
    // MARK: - 平衡组解析
    
    /// 拉出一个代码平衡组（处理转义字符）
    private func chompCodeBalanced(open: Character, close: Character) -> Bool {
        chompBalancedGroup(open: open, close: close, code: true)
    }
    
    /// 拉出一个规则平衡组（xpath和jsoup中引号内转义字符无效）
    private func chompRuleBalanced(open: Character, close: Character) -> Bool {
        chompBalancedGroup(open: open, close: close, code: false)
    }

    private func chompBalancedGroup(open: Character, close: Character, code: Bool) -> Bool {
        guard pos >= 0, pos < characters.count, characters[pos] == open else { return false }
        let closing: [Character: Character] = ["[": "]", "(": ")", "{": "}"]
        var expected: [Character] = [close]
        var quote: Character?
        var cursor = pos + 1
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\", code || quote == nil {
                cursor = min(cursor + 2, characters.count)
                continue
            }
            if let currentQuote = quote {
                if character == currentQuote { quote = nil }
            } else if character == "'" || character == "\"" || (code && character == "`") {
                quote = character
            } else if let end = closing[character] {
                expected.append(end)
            } else if character == "]" || character == ")" || character == "}" {
                guard expected.last == character else { return false }
                expected.removeLast()
                if expected.isEmpty {
                    pos = cursor + 1
                    return true
                }
            }
            cursor += 1
        }
        return false
    }
    
    /// 平衡组解析（根据模式选择）
    private func chompBalanced(open: Character, close: Character) -> Bool {
        return isCode ? chompCodeBalanced(open: open, close: close) : chompRuleBalanced(open: open, close: close)
    }
    
    // MARK: - 规则切分
    
    /// 切分规则字符串
    /// - Parameter splits: 分隔符列表
    /// - Returns: 规则列表
    func splitRule(_ splits: String...) -> [String] {
        splitRule(splits)
    }

    func splitRule(_ splits: [String]) -> [String] {
        guard !splits.isEmpty, splits.allSatisfy({ !$0.isEmpty }) else {
            return [String(queue.dropFirst(pos))]
        }
        var delimiter: String?
        var partStart = startX
        let length = characters.count
        while pos < length {
            let cursor = indices[pos]
            let character = queue[cursor]
            if character == "[" || character == "(" {
                let close: Character = character == "[" ? "]" : ")"
                guard chompBalanced(open: character, close: close) else { return rules }
                continue
            }
            let candidates = delimiter.map { [$0] } ?? splits
            if let matched = candidates.first(where: { queue[cursor...].hasPrefix($0) }) {
                delimiter = matched
                elementsType = matched
                rules.append(String(queue[indices[partStart]..<cursor]))
                pos += matched.count
                partStart = pos
            } else { pos += 1 }
        }
        rules.append(String(queue[indices[partStart]...]))
        return rules
    }

    // MARK: - 内嵌规则替换
    
    /// 替换内嵌规则（使用起始和结束标志）
    /// - Parameters:
    ///   - inner: 起始标志，如 "{$."
    ///   - startStep: 不属于规则部分的前置字符长度
    ///   - endStep: 不属于规则部分的后置字符长度
    ///   - resolver: 查找到内嵌规则时的解析函数
    /// - Returns: 替换后的字符串
    func innerRule(inner: String, startStep: Int = 1, endStep: Int = 1, resolver: (String) -> String?) -> String {
        guard !inner.isEmpty, startStep >= 0, endStep >= 0 else { return "" }
        let result = StringBuilder()
        
        while consumeTo(inner) {
            let posPre = pos
            if chompCodeBalanced(open: "{", close: "}"), posPre + startStep <= pos - endStep {
                let startIndex = indices[posPre + startStep]
                let endIndex = indices[pos - endStep]
                let innerContent = String(queue[startIndex..<endIndex])
                
                if let resolved = resolver(innerContent), !resolved.isEmpty {
                    let prefixStart = indices[startX]
                    let prefixEnd = indices[posPre]
                    result.append(String(queue[prefixStart..<prefixEnd]))
                    result.append(resolved)
                    startX = pos
                    continue
                }
            }
            // A missing inner value must not advance past the matched group or the string end.
            pos = posPre + inner.count
        }
        
        if startX == 0 { return "" }
        
        result.append(String(queue[indices[startX]...]))
        return result.toString()
    }
    
    /// 替换内嵌规则（使用起始和结束字符串）
    func innerRule(startStr: String, endStr: String, resolver: (String) -> String?) -> String {
        guard !startStr.isEmpty, !endStr.isEmpty else { return queue }
        let result = StringBuilder()
        
        while consumeTo(startStr) {
            pos += startStr.count
            let posPre = pos
            
            if consumeTo(endStr) {
                let startIndex = indices[posPre]
                let endIndex = indices[pos]
                let innerContent = String(queue[startIndex..<endIndex])
                
                if let resolved = resolver(innerContent) {
                    let prefixStart = indices[startX]
                    let prefixEnd = indices[posPre - startStr.count]
                    result.append(String(queue[prefixStart..<prefixEnd]))
                    result.append(resolved)
                    
                    pos += endStr.count
                    startX = pos
                } else {
                    pos += endStr.count
                }
            } else {
                break
            }
        }
        
        if startX == 0 { return queue }
        
        result.append(String(queue[indices[startX]...]))
        return result.toString()
    }
}

// MARK: - 辅助类型

/// 字符串构建器
class StringBuilder {
    private var string: String = ""
    
    var length: Int { string.count }
    
    func append(_ str: String) {
        string += str
    }
    
    func clear() {
        string = ""
    }
    
    func toString() -> String {
        return string
    }
}

// MARK: - 便捷扩展

extension RuleAnalyzer {
    
    /// 静态方法：切分规则字符串
    static func split(_ rule: String, separators: String...) -> [String] {
        let analyzer = RuleAnalyzer(data: rule)
        if separators.isEmpty {
            return analyzer.splitRule("&&", "||", "%%", "@")
        }
        return analyzer.splitRule(separators)
    }
    
    /// 静态方法：解析内嵌规则
    static func resolveInnerRules(_ rule: String, resolver: (String) -> String?) -> String {
        let analyzer = RuleAnalyzer(data: rule, code: true)
        return analyzer.innerRule(inner: "{{", startStep: 2, endStep: 2, resolver: resolver)
    }
}
