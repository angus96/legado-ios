import UIKit
import CoreText

class TextLine {
    var text: String = ""
    private var textColumns: [BaseColumn] = []
    
    var lineTop: Float = 0.0
    var lineBase: Float = 0.0
    var lineBottom: Float = 0.0
    var indentWidth: Float = 0.0
    var paragraphNum: Int = 0
    var chapterPosition: Int = 0
    var pagePosition: Int = 0
    var isTitle: Bool = false
    var isParagraphEnd: Bool = false
    var isImage: Bool = false
    var startX: Float = 0.0
    var coreTextLine: CTLine?
    var indentSize: Int = 0
    var extraLetterSpacing: Float = 0.0
    var extraLetterSpacingOffsetX: Float = 0.0
    var wordSpacing: Float = 0.0
    var exceed: Bool = false
    var onlyTextColumn: Bool = true
    
    private weak var parent: TextPage?
    var textPage: TextPage {
        get { parent ?? TextPage.empty }
        set { parent = newValue }
    }
    var isLeftLine: Bool = true
    var searchResultColumnCount: Int = 0
    var isReadAloud: Bool = false {
        didSet {
            if isReadAloud != oldValue {
                invalidate()
            }
            if isReadAloud {
                textPage.hasReadAloudSpan = true
            }
        }
    }
    
    static let empty = TextLine()
    
    var columns: [BaseColumn] { textColumns }
    var charSize: Int { text.count }
    var lineStart: Float { textColumns.first?.start ?? 0.0 }
    var lineEnd: Float { textColumns.last?.end ?? 0.0 }
    var chapterIndices: Range<Int> { chapterPosition..<(chapterPosition + charSize) }
    var height: Float { lineBottom - lineTop }
    
    func addColumn(_ column: BaseColumn) {
        if !(column is TextColumn) {
            onlyTextColumn = false
        }
        column.textLine = self
        textColumns.append(column)
    }
    
    func getColumn(_ index: Int) -> BaseColumn {
        return textColumns.indices.contains(index) ? textColumns[index] : textColumns.last!
    }
    
    func getColumnReverseAt(_ index: Int, offset: Int = 0) -> BaseColumn {
        let targetIndex = textColumns.count - offset - index
        return textColumns[targetIndex]
    }
    
    func getColumnsCount() -> Int {
        return textColumns.count
    }
    
    func isTouch(x: Float, y: Float, relativeOffset: Float) -> Bool {
        return y > lineTop + relativeOffset
            && y < lineBottom + relativeOffset
            && x >= lineStart
            && x <= lineEnd
    }
    
    func isTouchY(y: Float, relativeOffset: Float) -> Bool {
        return y > lineTop + relativeOffset
            && y < lineBottom + relativeOffset
    }
    
    func draw(in view: ContentTextView, context: CGContext) {
        context.saveGState()
        
        if onlyTextColumn && textColumns.count > 0 {
            fastDrawTextLine(in: view, context: context)
        } else {
            for column in columns {
                column.draw(in: view, context: context)
            }
        }
        
        context.restoreGState()
    }
    
    private func fastDrawTextLine(in view: ContentTextView, context: CGContext) {
        let provider = ChapterProvider.shared
        let font = isTitle ? provider.titleFont : provider.contentFont
        
        let textColor: UIColor
        if isReadAloud || searchResultColumnCount > 0 {
            textColor = .systemBlue
        } else {
            textColor = provider.textColor
        }
        
        let y = CGFloat(lineBase - lineTop)

        if let coreTextLine {
            context.textMatrix = .identity
            context.translateBy(x: CGFloat(startX), y: y)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            context.setFillColor(textColor.cgColor)
            CTLineDraw(coreTextLine, context)
            return
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: provider.letterSpacing
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        attributedString.draw(at: CGPoint(x: CGFloat(lineStart), y: y - font.ascender))
    }
    
    func invalidate() {
        invalidateSelf()
        textPage.invalidate()
    }
    
    func invalidateSelf() {
    }
}
