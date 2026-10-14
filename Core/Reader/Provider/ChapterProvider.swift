//
//  ChapterProvider.swift
//  Legado
//
//  基于 Android Legado 原版 ChapterProvider.kt 移植
//  原版路径: app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt
//

import UIKit
import Foundation
import CoreText

/// 排版进度监听协议
protocol LayoutProgressListener: AnyObject {
    func onLayoutPageCompleted(_ index: Int, page: TextPage)
    func onLayoutCompleted()
    func onLayoutException(_ error: Error)
}

/// 章节排版器
/// 一比一移植自 Android Legado ChapterProvider
/// 负责将章节内容排版成 TextPage 数组
class ChapterProvider {
    
    static let shared = ChapterProvider()
    
    // MARK: - 常量
    static let srcReplaceChar = "▩"
    static let reviewChar = "▨"
    static let indentChar = "　"
    
    // MARK: - 视图尺寸
    var viewWidth: CGFloat = 0
    var viewHeight: CGFloat = 0
    
    // MARK: - 边距
    var paddingLeft: CGFloat = 20
    var paddingTop: CGFloat = 10
    var paddingRight: CGFloat = 20
    var paddingBottom: CGFloat = 10
    
    // MARK: - 可见区域
    var visibleWidth: CGFloat { viewWidth - paddingLeft - paddingRight }
    var visibleHeight: CGFloat { viewHeight - paddingTop - paddingBottom }
    var visibleRight: CGFloat { viewWidth - paddingRight }
    var visibleBottom: CGFloat { paddingTop + visibleHeight }
    
    // MARK: - 间距
    var lineSpacingExtra: CGFloat = 1.2
    var paragraphSpacing: CGFloat = 10
    var letterSpacing: CGFloat = 0
    var titleTopSpacing: CGFloat = 30
    var titleBottomSpacing: CGFloat = 20
    
    // MARK: - 字体相关
    var indentCharWidth: CGFloat = 0
    var titlePaintTextHeight: CGFloat = 0
    var contentPaintTextHeight: CGFloat = 0
    
    // MARK: - Paint (iOS 使用字体属性)
    var titleFont: UIFont = .systemFont(ofSize: 20, weight: .bold)
    var contentFont: UIFont = .systemFont(ofSize: 16)
    var textColor: UIColor = .black
    
    // MARK: - 双页模式
    var doublePage: Bool = false
    
    private init() { updateStyle(titleFont: titleFont, contentFont: contentFont) }
    
    // MARK: - 更新样式
    func updateStyle(
        titleFont: UIFont? = nil,
        contentFont: UIFont? = nil,
        textColor: UIColor? = nil,
        lineSpacing: CGFloat? = nil,
        paragraphSpacing: CGFloat? = nil
    ) {
        if let titleFont = titleFont {
            self.titleFont = titleFont
            titlePaintTextHeight = titleFont.lineHeight
        }
        if let contentFont = contentFont {
            self.contentFont = contentFont
            contentPaintTextHeight = contentFont.lineHeight
        }
        if let textColor = textColor {
            self.textColor = textColor
        }
        if let lineSpacing = lineSpacing {
            self.lineSpacingExtra = lineSpacing
        }
        if let paragraphSpacing = paragraphSpacing {
            self.paragraphSpacing = paragraphSpacing
        }
        
        // 计算缩进字符宽度
        let indentStr = String(repeating: Self.indentChar, count: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: contentFont ?? self.contentFont]
        indentCharWidth = (indentStr as NSString).size(withAttributes: attributes).width
    }
    
    // MARK: - 更新视图尺寸
    func updateViewSize(width: CGFloat, height: CGFloat) {
        guard width > 0 && height > 0 else { return }
        viewWidth = width
        viewHeight = height
    }
    
    // MARK: - 更新边距
    func updatePadding(
        left: CGFloat? = nil,
        top: CGFloat? = nil,
        right: CGFloat? = nil,
        bottom: CGFloat? = nil
    ) {
        if let left = left { paddingLeft = left }
        if let top = top { paddingTop = top }
        if let right = right { paddingRight = right }
        if let bottom = bottom { paddingBottom = bottom }
    }
    
    // MARK: - 测量文本
    func measureText(_ text: String, font: UIFont) -> [String] {
        var words: [String] = []
        for char in text {
            words.append(String(char))
        }
        return words
    }
    
    // MARK: - 计算文本宽度
    func measureTextWidths(_ text: String, font: UIFont) -> [CGFloat] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return text.map { char in
            String(char).size(withAttributes: attributes).width
        }
    }
    
    // MARK: - 换行与绘制共用同一份 CoreText 排版
    func createTextLayout(text: String, font: UIFont, width: CGFloat) -> [TextLayoutLine] {
        guard !text.isEmpty, width > 0, width.isFinite else { return [] }
        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font, .kern: letterSpacing,
                         NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        let characters = Array(text)
        var utf16Offsets = [0]
        for character in characters {
            utf16Offsets.append(utf16Offsets.last! + String(character).utf16.count)
        }

        var lines: [TextLayoutLine] = []
        var start = 0
        while start < characters.count {
            let suggestedEnd = utf16Offsets[start] + CTTypesetterSuggestLineBreak(typesetter, utf16Offsets[start], Double(width))
            var end = start + 1
            while end < characters.count && utf16Offsets[end + 1] <= suggestedEnd { end += 1 }

            func avoidHangingPunctuation(_ proposedEnd: Int) -> Int {
                guard ReadBookConfig.useZhLayout, proposedEnd < characters.count else { return proposedEnd }
                var candidate = proposedEnd
                while candidate > start + 1 &&
                    (ZhLayout.postPanc.contains(String(characters[candidate])) ||
                     ZhLayout.prePanc.contains(String(characters[candidate - 1]))) {
                    candidate -= 1
                }
                return candidate
            }
            end = avoidHangingPunctuation(end)
            func makeLine(_ end: Int) -> TextLayoutLine {
                let range = CFRange(location: utf16Offsets[start], length: utf16Offsets[end] - utf16Offsets[start])
                return TextLayoutLine(text: String(characters[start..<end]),
                                      coreTextLine: CTTypesetterCreateLine(typesetter, range),
                                      utf16Start: range.location)
            }
            var line = makeLine(end)
            // 系统换行可能允许标点悬挂；按最终字形的宽度收回，不能占用右边距。
            while line.width > width && end > start + 1 {
                end = avoidHangingPunctuation(end - 1)
                line = makeLine(end)
            }
            lines.append(line)
            start = end
        }
        return lines
    }
}

/// 保留实际绘制的字形，避免逐字估宽与整行绘制产生不同结果。
struct TextLayoutLine {
    let text: String
    let coreTextLine: CTLine
    let utf16Start: Int
    let width: CGFloat
    let drawOffsetX: CGFloat

    init(text: String, coreTextLine: CTLine, utf16Start: Int) {
        self.text = text
        self.coreTextLine = coreTextLine
        self.utf16Start = utf16Start
        let advance = CGFloat(CTLineGetTypographicBounds(coreTextLine, nil, nil, nil))
        let ink = CTLineGetImageBounds(coreTextLine, nil)
        drawOffsetX = ink.isNull ? 0 : max(0, -ink.minX)
        width = max(advance, ink.isNull ? 0 : ink.maxX) + drawOffsetX
    }
}
