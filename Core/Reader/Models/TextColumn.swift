import UIKit

class TextColumn: BaseColumn, Hashable {
    var start: Float
    var end: Float
    let charData: String
    private weak var parent: TextLine?
    var textLine: TextLine {
        get { parent ?? TextLine.empty }
        set { parent = newValue }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(end)
        hasher.combine(charData)
    }
    
    static func == (lhs: TextColumn, rhs: TextColumn) -> Bool {
        return lhs.start == rhs.start && lhs.end == rhs.end && lhs.charData == rhs.charData
    }
    
    var selected: Bool = false {
        didSet {
            if selected != oldValue {
                textLine.invalidate()
            }
        }
    }
    
    var isSearchResult: Bool = false {
        didSet {
            if isSearchResult != oldValue {
                textLine.invalidate()
                if isSearchResult {
                    textLine.searchResultColumnCount += 1
                } else {
                    textLine.searchResultColumnCount -= 1
                }
            }
        }
    }
    
    init(start: Float, end: Float, charData: String) {
        self.start = start
        self.end = end
        self.charData = charData
    }
    
    func draw(in view: ContentTextView, context: CGContext) {
        let provider = ChapterProvider.shared
        let font = textLine.isTitle ? provider.titleFont : provider.contentFont
        
        let textColor: UIColor
        if textLine.isReadAloud || isSearchResult {
            textColor = .systemBlue
        } else {
            textColor = provider.textColor
        }
        
        let y = CGFloat(textLine.lineBase - textLine.lineTop)
        let x = CGFloat(start)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let attributedString = NSAttributedString(string: charData, attributes: attributes)
        attributedString.draw(at: CGPoint(x: x, y: y - font.ascender))
        
        if selected {
            context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.3).cgColor)
            context.fill(CGRect(x: CGFloat(start), y: 0, width: CGFloat(end - start), height: CGFloat(textLine.height)))
        }
    }
}