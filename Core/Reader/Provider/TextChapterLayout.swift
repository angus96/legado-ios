//
//  TextChapterLayout.swift
//  Legado
//
//  基于 Android Legado 原版 TextChapterLayout.kt 移植
//  原版路径: app/src/main/java/io/legado/app/ui/book/read/page/provider/TextChapterLayout.kt
//

import UIKit
import Foundation

/// 异步章节排版器
/// 一比一移植自 Android Legado TextChapterLayout
/// 使用 async/await + AsyncStream 实现异步排版
@MainActor
class TextChapterLayout {
    private weak var textChapter: TextChapter?
    private var textPages: [TextPage] = []
    private let book: Book
    private let bookContent: BookContent
    
    private var listener: LayoutProgressListener?
    
    private var durY: CGFloat = 0
    private var absStartX: CGFloat = 0
    private var pendingTextPage = TextPage()
    private var stringBuilder = StringBuilder()
    
    var exception: Error?
    var isCompleted = false
    
    private var pageStreamContinuation: AsyncStream<TextPage>.Continuation?
    var pageStream: AsyncStream<TextPage> {
        AsyncStream { continuation in
            self.pageStreamContinuation = continuation
        }
    }
    
    init(
        textChapter: TextChapter,
        textPages: [TextPage],
        book: Book,
        bookContent: BookContent
    ) {
        self.textChapter = textChapter
        self.textPages = textPages
        self.book = book
        self.bookContent = bookContent
    }
    
    func setProgressListener(_ listener: LayoutProgressListener?) {
        if isCompleted {
            return
        } else if exception != nil {
            listener?.onLayoutException(exception!)
        } else {
            self.listener = listener
        }
    }
    
    func cancel() {
        pageStreamContinuation?.finish()
        listener = nil
    }
    
    // MARK: - 开始排版
    func startLayout() async {
        do {
            try await layoutChapter()
        } catch {
            self.exception = error
            onException(error)
        }
    }
    
    private func layoutChapter() async throws {
        let provider = ChapterProvider.shared
        let contents = bookContent.textList
        
        let paddingLeft = provider.paddingLeft
        let paddingTop = provider.paddingTop
        let visibleWidth = provider.visibleWidth
        let visibleHeight = provider.visibleHeight
        let viewWidth = provider.viewWidth
        let doublePage = provider.doublePage
        
        absStartX = paddingLeft
        
        let titlePaintTextHeight = provider.titlePaintTextHeight
        let titlePaint = provider.titleFont
        
        let contentPaintTextHeight = provider.contentPaintTextHeight
        let contentPaint = provider.contentFont
        
        let titleBottomSpacing = provider.titleBottomSpacing
        let lineSpacingExtra = provider.lineSpacingExtra
        let paragraphSpacing = provider.paragraphSpacing
        let indentCharWidth = provider.indentCharWidth
        
        let paragraphIndent = ReadBookConfig.paragraphIndent
        let textFullJustify = ReadBookConfig.textFullJustify
        
        guard let textChapter = textChapter else { return }
        let displayTitle = textChapter.title
        
        // 1. 处理标题（非隐藏模式）
        let titleMode = ReadBookConfig.titleMode
        if titleMode != 2 {
            for titleLine in displayTitle.splitNotBlank("\n") {
                await setTypeText(
                    text: titleLine,
                    font: titlePaint,
                    textHeight: titlePaintTextHeight,
                    imageStyle: nil,
                    isTitle: true,
                    emptyContent: contents.isEmpty,
                    isVolumeTitle: false
                )
                if let lastLine = pendingTextPage.lines.last {
                    lastLine.isParagraphEnd = true
                }
                stringBuilder.append("\n")
            }
            durY += titleBottomSpacing
        }
        
        // 2. 处理正文内容
        for content in contents {
            // 检查任务取消
            try Task.checkCancellation()
            
            // 处理图片标签
            if content.contains("<img") {
                var start = 0
                let imgPattern = try NSRegularExpression(pattern: "<img[^>]+src=\"([^\"]+)\"[^>]*>", options: .caseInsensitive)
                let matches = imgPattern.matches(in: content, range: NSRange(content.startIndex..., in: content))
                
                for match in matches {
                    try Task.checkCancellation()
                    
                    // 处理图片前的文本
                    if match.range.location > start {
                        let textRange = NSRange(location: start, length: match.range.location - start)
                        let text = (content as NSString).substring(with: textRange)
                        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            await setTypeText(
                                text: text,
                                font: contentPaint,
                                textHeight: contentPaintTextHeight,
                                imageStyle: nil,
                                isTitle: false,
                                isFirstLine: start == 0
                            )
                        }
                    }
                    
                    // 处理图片
                    if let srcRange = Range(match.range(at: 1), in: content) {
                        let src = String(content[srcRange])
                        await setTypeImage(
                            src: src,
                            textHeight: contentPaintTextHeight,
                            imageStyle: nil
                        )
                    }
                    
                    start = match.range.location + match.range.length
                }
                
                // 处理剩余文本
                if start < (content as NSString).length {
                    let text = (content as NSString).substring(from: start)
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        await setTypeText(
                            text: text,
                            font: contentPaint,
                            textHeight: contentPaintTextHeight,
                            imageStyle: nil,
                            isTitle: false,
                            isFirstLine: start == 0
                        )
                    }
                }
            } else {
                // 纯文本内容
                await setTypeText(
                    text: content,
                    font: contentPaint,
                    textHeight: contentPaintTextHeight,
                    imageStyle: nil,
                    isTitle: false,
                    isFirstLine: true
                )
            }
        }
        
        // 3. 完成最后一页
        let textPage = pendingTextPage
        let endPadding: CGFloat = 20
        let durYPadding = durY + endPadding
        
        if Float(textPage.height) < Float(durYPadding) {
            textPage.height = Float(durYPadding)
        } else {
            textPage.height += Float(endPadding)
        }
        
        textPage.text = stringBuilder.toString()
        
        onPageCompleted()
        onCompleted()
    }
    
    // MARK: - 换页逻辑
    /// 当内容超出页面高度时，创建新页面
    /// 一比一移植自 Android Legado prepareNextPageIfNeed
    private func prepareNextPageIfNeed(requestHeight: CGFloat = -1) {
        let provider = ChapterProvider.shared
        let visibleHeight = provider.visibleHeight
        let viewWidth = provider.viewWidth
        let paddingLeft = provider.paddingLeft
        let doublePage = provider.doublePage
        
        if requestHeight > visibleHeight || requestHeight == -1 {
            let textPage = pendingTextPage
            
            // 更新页面高度
            if Float(textPage.height) < Float(durY) {
                textPage.height = Float(durY)
            }
            
            if doublePage && absStartX < viewWidth / 2 {
                // 双页模式：当前左列结束，切换到右列
                textPage.leftLineSize = textPage.lineSize
                absStartX = viewWidth / 2 + paddingLeft
            } else {
                // 当前页面结束
                if textPage.leftLineSize == 0 {
                    textPage.leftLineSize = textPage.lineSize
                }
                textPage.text = stringBuilder.toString()
                onPageCompleted()
                
                // 新建页面
                pendingTextPage = TextPage()
                stringBuilder.clear()
                absStartX = paddingLeft
            }
            
            durY = 0
        }
    }
    
    // MARK: - 图片排版
    /// 一比一移植自 Android Legado setTypeImage (第329-402行)
    private func setTypeImage(
        src: String,
        textHeight: CGFloat,
        imageStyle: String?
    ) async {
        let provider = ChapterProvider.shared
        let visibleWidth = provider.visibleWidth
        let visibleHeight = provider.visibleHeight
        let paddingTop = provider.paddingTop
        let paddingLeft = provider.paddingLeft
        
        var width: CGFloat = visibleWidth
        var height: CGFloat = visibleHeight * 0.5
        
        prepareNextPageIfNeed(requestHeight: durY)
        
        // 根据图片样式调整尺寸
        let style = imageStyle?.uppercased() ?? ""
        
        // 简化处理：图片居中显示
        if height > visibleHeight - durY {
            if height > visibleHeight {
                width = width * visibleHeight / height
                height = visibleHeight
            }
            prepareNextPageIfNeed(requestHeight: durY + height)
        }
        
        // 创建图片行
        let textLine = TextLine()
        textLine.isImage = true
        textLine.text = " "
        textLine.lineTop = Float(durY + paddingTop)
        
        durY += height
        textLine.lineBottom = Float(durY + paddingTop)
        
        // 计算水平居中位置
        let (start, end): (Float, Float)
        if visibleWidth > width {
            let adjustWidth = (visibleWidth - width) / 2
            start = Float(absStartX + adjustWidth)
            end = Float(absStartX + adjustWidth + width)
        } else {
            start = Float(absStartX)
            end = Float(absStartX + width)
        }
        
        textLine.addColumn(ImageColumn(start: start, end: end, src: src, book: book))
        
        calcTextLinePosition(textLine, sbLength: stringBuilder.length)
        stringBuilder.append(" ")
        pendingTextPage.addLine(textLine)
        
        durY += textHeight * CGFloat(provider.paragraphSpacing) / 10.0
    }
    
    // MARK: - 文字排版核心
    /// 一比一移植自 Android Legado setTypeText (第408-536行)
    private func setTypeText(
        text: String,
        font: UIFont,
        textHeight: CGFloat,
        imageStyle: String?,
        isTitle: Bool = false,
        isFirstLine: Bool = true,
        emptyContent: Bool = false,
        isVolumeTitle: Bool = false
    ) async {
        let provider = ChapterProvider.shared
        let visibleWidth = provider.visibleWidth
        let visibleHeight = provider.visibleHeight
        let paddingTop = provider.paddingTop
        let paddingLeft = provider.paddingLeft
        let lineSpacingExtra = provider.lineSpacingExtra
        let paragraphSpacing = provider.paragraphSpacing
        let titleTopSpacing = provider.titleTopSpacing
        
        let text = !isTitle && isFirstLine
            ? String(repeating: ChapterProvider.indentChar, count: ReadBookConfig.paragraphIndent.length)
                + String(text.drop(while: { $0.isWhitespace }))
            : text
        // 测量文本宽度
        let widthsArray = measureTextWidths(text, font: font)
        let (words, widths) = measureTextSplit(text, widthsArray: widthsArray)
        let desiredWidth = widths.reduce(0, +)
        
        // 使用 iOS TextKit 进行布局
        let lines = createTextLayout(text: text, font: font, width: visibleWidth)
        
        // 标题 Y 轴居中处理
        let isSingleImageStyle = imageStyle?.uppercased() == "SINGLE"
        if isTitle && textPages.isEmpty && pendingTextPage.lines.isEmpty {
            if emptyContent || isSingleImageStyle {
                let ty = (visibleHeight - CGFloat(lines.count) * textHeight) / 2
                durY = max(ty, titleTopSpacing)
            } else {
                durY += titleTopSpacing
            }
        }
        
        // 逐行处理
        for (lineIndex, layoutLine) in lines.enumerated() {
            let textLine = TextLine()
            textLine.isTitle = isTitle
            
            // 检查是否需要换页
            prepareNextPageIfNeed(requestHeight: durY + textHeight)
            
            let lineText = layoutLine.text
            textLine.text = lineText
            
            // 计算该行的字符宽度
            let lineWords = ChapterProvider.shared.measureText(lineText, font: font)
            let lineWidths = measureTextWidths(lineText, font: font)
            let lineDesiredWidth = lineWidths.reduce(0, +)
            
            // 根据行位置选择排版方式
            let startX: CGFloat
            if isTitle && (emptyContent || isVolumeTitle || isSingleImageStyle) {
                // 标题居中
                startX = (visibleWidth - lineDesiredWidth) / 2
            } else {
                startX = 0
            }
            
            // 添加字符到行
            await addCharsToLine(
                words: lineWords,
                widths: lineWidths,
                textLine: textLine,
                startX: startX,
                isTitle: isTitle
            )
            
            // 计算行位置
            calcTextLinePosition(textLine, sbLength: stringBuilder.length)
            stringBuilder.append(lineText)
            
            // 设置行垂直位置
            textLine.lineTop = Float(durY + paddingTop)
            textLine.lineBase = Float(durY + paddingTop + font.ascender)
            textLine.lineBottom = Float(durY + textHeight + paddingTop)
            
            pendingTextPage.addLine(textLine)
            durY += textHeight * lineSpacingExtra
            
            if Float(pendingTextPage.height) < Float(durY) {
                pendingTextPage.height = Float(durY)
            }
        }
        
        if let lastLine = pendingTextPage.lines.last {
            lastLine.isParagraphEnd = true
        }
        stringBuilder.append("\n")
        durY += paragraphSpacing
    }
    
    // MARK: - 添加字符到行
    private func addCharsToLine(
        words: [String],
        widths: [CGFloat],
        textLine: TextLine,
        startX: CGFloat,
        isTitle: Bool
    ) async {
        let provider = ChapterProvider.shared
        let absStartX = provider.paddingLeft
        let indentCharWidth = provider.indentCharWidth
        let paragraphIndent = ReadBookConfig.paragraphIndent
        let textFullJustify = ReadBookConfig.textFullJustify
        
        var x = startX
        textLine.startX = Float(absStartX + startX)
        
        // 缩进已经参与整段测量，不能再替换每一行开头的正文字符。
        await addCharsToLineNatural(words: words, widths: widths, textLine: textLine, startX: startX)
    }

    // MARK: - 自然排版
    private func addCharsToLineNatural(
        words: [String],
        widths: [CGFloat],
        textLine: TextLine,
        startX: CGFloat
    ) async {
        let absStartX = ChapterProvider.shared.paddingLeft
        var x = startX
        
        for (index, char) in words.enumerated() {
            let cw = widths[index]
            let x1 = x + cw
            
            textLine.addColumn(
                TextColumn(
                    start: Float(absStartX + x),
                    end: Float(absStartX + x1),
                    charData: char
                )
            )
            x = x1
        }
    }
    
    // MARK: - 计算行位置
    /// 一比一移植自 Android Legado calcTextLinePosition (第538-556行)
    private func calcTextLinePosition(_ textLine: TextLine, sbLength: Int) {
        // 计算段落编号
        let lastLine = pendingTextPage.lines.last { $0.paragraphNum > 0 }
            ?? textPages.last?.lines.last { $0.paragraphNum > 0 }
        
        let paragraphNum: Int
        if let line = lastLine {
            paragraphNum = line.isParagraphEnd ? line.paragraphNum + 1 : line.paragraphNum
        } else {
            paragraphNum = 1
        }
        
        textLine.paragraphNum = paragraphNum
        
        // 计算章节位置
        let lastChapterPos: Int
        if let lastPage = textPages.last, let lastLine = lastPage.lines.last {
            lastChapterPos = lastLine.chapterPosition + lastLine.charSize + (lastLine.isParagraphEnd ? 1 : 0)
        } else {
            lastChapterPos = 0
        }
        
        textLine.chapterPosition = lastChapterPos + sbLength
        textLine.pagePosition = sbLength
    }
    
    private var textMeasure: TextMeasure?
    
    // MARK: - 文本测量工具（使用TextMeasure缓存优化）
    private func measureTextWidths(_ text: String, font: UIFont) -> [CGFloat] {
        if textMeasure == nil || textMeasure!.font != font {
            textMeasure = TextMeasure(font: font)
        }
        let result = textMeasure!.measureTextSplit(text: text)
        return result.widths.map { $0 + ChapterProvider.shared.letterSpacing }
    }
    
    private func measureTextSplit(_ text: String, widthsArray: [CGFloat], start: Int = 0) -> ([String], [CGFloat]) {
        if textMeasure == nil {
            textMeasure = TextMeasure(font: ChapterProvider.shared.contentFont)
        }
        let result = textMeasure!.measureTextSplit(text: text)
        return (result.strings, result.widths.map { $0 + ChapterProvider.shared.letterSpacing })
    }
    
    private func isZeroWidthChar(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let code = scalar.value
        return code == 8203 || code == 8204 || code == 8205 || code == 8288
    }
    
    private func createTextLayout(text: String, font: UIFont, width: CGFloat) -> [TextLayoutLine] {
        let useZhLayout = ReadBookConfig.useZhLayout
        
        if useZhLayout {
            return createZhTextLayout(text: text, font: font, width: width)
        } else {
            return ChapterProvider.shared.createTextLayout(text: text, font: font, width: width)
        }
    }
    
    private func createZhTextLayout(text: String, font: UIFont, width: CGFloat) -> [TextLayoutLine] {
        if textMeasure == nil || textMeasure!.font != font {
            textMeasure = TextMeasure(font: font)
        }
        
        let result = textMeasure!.measureTextSplit(text: text)
        let indentSize = ReadBookConfig.paragraphIndent.length
        
        let zhLayout = ZhLayout(
            text: text,
            font: font,
            width: width,
            words: result.strings,
            widths: result.widths.map { $0 + ChapterProvider.shared.letterSpacing },
            indentSize: indentSize
        )
        
        var lines: [TextLayoutLine] = []
        for i in 0..<zhLayout.count {
            let start = zhLayout.getLineStart(i)
            let end = zhLayout.getLineEnd(i)
            
            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(text.startIndex, offsetBy: end)
            let lineText = String(text[startIndex..<endIndex])
            
            lines.append(TextLayoutLine(
                text: lineText,
                start: start,
                end: end,
                width: zhLayout.getLineWidth(i)
            ))
        }
        
        return lines
    }
    
    // MARK: - 页面完成回调
    private func onPageCompleted() {
        guard let textChapter = textChapter else { return }
        
        let textPage = pendingTextPage
        textPage.index = textPages.count
        textPage.chapterIndex = Int(textChapter.chapter?.index ?? 0)
        textPage.chapterSize = textChapter.chaptersSize
        textPage.title = textChapter.title
        textPage.doublePage = ChapterProvider.shared.doublePage
        textPage.paddingTop = ChapterProvider.shared.paddingTop
        textPage.isCompleted = true
        textPage.textChapter = textChapter
        textPage.upLinesPosition()
        textPage.upRenderHeight()
        
        textPages.append(textPage)
        textChapter.appendPage(textPage)
        pageStreamContinuation?.yield(textPage)
        
        listener?.onLayoutPageCompleted(textPages.count - 1, page: textPage)
    }
    
    private func onCompleted() {
        isCompleted = true
        textChapter?.isCompleted = true
        pageStreamContinuation?.finish()
        listener?.onLayoutCompleted()
        listener = nil
    }
    
    private func onException(_ error: Error) {
        pageStreamContinuation?.finish()
        listener?.onLayoutException(error)
        listener = nil
    }
}

struct BookContent {
    var textList: [String] = []
    var sameTitleRemoved: Bool = false
    var effectiveReplaceRules: [ReplaceRule]? = nil
}

extension String {
    func splitNotBlank(_ separator: String) -> [String] {
        return self.split(separator: separator)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
