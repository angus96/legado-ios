//
//  ChapterProvider.swift
//  Legado
//
//  基于 Android Legado 原版 ChapterProvider.kt 移植
//  原版路径: app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt
//

import UIKit
import Foundation

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
    
    // MARK: - 创建 TextLayout (iOS 使用 TextKit)
    func createTextLayout(text: String, font: UIFont, width: CGFloat) -> [TextLayoutLine] {
        guard !text.isEmpty, width > 0 else { return [] }
        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        
        let textStorage = NSTextStorage(attributedString: attributedString)
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        
        var lines: [TextLayoutLine] = []
        var currentY: CGFloat = 0
        var prevGlyphRange = NSRange(location: 0, length: 0)
        
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) { rect, usedRect, textContainer, glyphRange, stop in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let lineText = (text as NSString).substring(with: charRange)
            
            let line = TextLayoutLine(
                text: lineText,
                rect: rect,
                baseline: usedRect.origin.y + usedRect.size.height,
                glyphRange: glyphRange,
                charRange: charRange
            )
            lines.append(line)
        }
        
        return lines
    }
}

/// 文本排版行信息 (iOS TextKit 辅助结构)
struct TextLayoutLine {
    let text: String
    let rect: CGRect
    let baseline: CGFloat
    let glyphRange: NSRange
    let charRange: NSRange
    
    init(text: String, rect: CGRect, baseline: CGFloat, glyphRange: NSRange, charRange: NSRange) {
        self.text = text
        self.rect = rect
        self.baseline = baseline
        self.glyphRange = glyphRange
        self.charRange = charRange
    }
    
    init(text: String, start: Int, end: Int, width: CGFloat) {
        self.text = text
        self.rect = CGRect(x: 0, y: 0, width: width, height: 0)
        self.baseline = 0
        self.glyphRange = NSRange(location: 0, length: end - start)
        self.charRange = NSRange(location: start, length: end - start)
    }
}