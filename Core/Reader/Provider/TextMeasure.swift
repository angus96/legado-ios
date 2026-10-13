import UIKit

/// 缓存完整字符的宽度，组合音标和 emoji 不拆成独立 Unicode 标量。
class TextMeasure {
    private(set) var font: UIFont
    private var widths: [Character: CGFloat] = [:]

    init(font: UIFont) { self.font = font }

    func measureTextSplit(text: String) -> (strings: [String], widths: [CGFloat]) {
        let characters = Array(text)
        return (characters.map(String.init), characters.map { character in
            if let cached = widths[character] { return cached }
            let width = String(character).size(withAttributes: [.font: font]).width
            widths[character] = width
            return width
        })
    }

    func measureText(text: String) -> CGFloat { measureTextSplit(text: text).widths.reduce(0, +) }

    func setFont(_ font: UIFont) {
        self.font = font
        widths.removeAll()
    }
}
