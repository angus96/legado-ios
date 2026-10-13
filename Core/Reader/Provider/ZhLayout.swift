import UIKit

class ZhLayout {
    static let postPanc: Set<String> = [
        "，", "。", "：", "？", "！", "、", "”", "’", "）", "》", "}",
        "】", ")", ">", "]", "}", ",", ".", "?", "!", ":", "」", "；", ";"
    ]
    
    static let prePanc: Set<String> = [
        "“", "（", "《", "【", "‘", "‘", "(", "<", "[", "{", "「"
    ]
    
    private var lineStart: [Int] = []
    private var lineWidth: [CGFloat] = []
    private var lineCount: Int = 0
    private let font: UIFont
    private let cnCharWidth: CGFloat
    
    enum BreakMode {
        case normal
        case breakOneChar
        case breakMoreChar
        case cps1
        case cps2
        case cps3
    }
    
    var lines: [ZhLine] = []
    
    struct ZhLine {
        var start: Int
        var end: Int
        var width: CGFloat
    }
    
    init(text: String, font: UIFont, width: CGFloat, words: [String], widths: [CGFloat], indentSize: Int) {
        self.font = font
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        self.cnCharWidth = ("我" as NSString).size(withAttributes: attributes).width
        
        lineStart = Array(repeating: 0, count: 10)
        lineWidth = Array(repeating: 0, count: 10)
        
        var line = 0
        var lineW: CGFloat = 0
        var cwPre: CGFloat = 0
        var length = 0
        
        for (index, s) in words.enumerated() {
            let cw = widths[index]
            var breakMode: BreakMode = .normal
            var breakLine = false
            lineW += cw
            var offset: CGFloat = 0
            var breakCharCnt = 0
            
            if lineW > width {
                if index >= 1 && isPrePanc(words[index - 1]) {
                    if index >= 2 && isPrePanc(words[index - 2]) {
                        breakMode = .cps2
                    } else {
                        breakMode = .breakOneChar
                    }
                } else if isPostPanc(words[index]) {
                    if index >= 1 && isPostPanc(words[index - 1]) {
                        breakMode = .cps1
                    } else if index >= 2 && isPrePanc(words[index - 2]) {
                        breakMode = .cps3
                    } else {
                        breakMode = .breakOneChar
                    }
                } else {
                    breakMode = .normal
                }
                
                var reCheck = false
                var breakIndex = 0
                if breakMode == .cps1 && (inCompressible(widths[index]) || inCompressible(widths[index - 1])) {
                    reCheck = true
                }
                if breakMode == .cps2 && (inCompressible(widths[index - 1]) || inCompressible(widths[index - 2])) {
                    reCheck = true
                }
                if breakMode == .cps3 && (inCompressible(widths[index]) || inCompressible(widths[index - 2])) {
                    reCheck = true
                }
                if breakMode != .normal && index < words.count - 1 && isPostPanc(words[index + 1]) {
                    reCheck = true
                }
                
                var breakLength = 0
                if reCheck && index > 2 {
                    let startPos = line == 0 ? indentSize : lineStart[line]
                    breakMode = .normal
                    for i in stride(from: index, through: 1 + startPos, by: -1) {
                        if i == index {
                            breakIndex = 0
                            cwPre = 0
                        } else {
                            breakIndex += 1
                            breakLength += words[i].count
                            cwPre += widths[i]
                        }
                        if !isPostPanc(words[i]) && !isPrePanc(words[i - 1]) {
                            breakMode = .breakMoreChar
                            break
                        }
                    }
                }
                
                switch breakMode {
                case .normal:
                    offset = cw
                    ensureCapacity(line + 1)
                    lineStart[line + 1] = length
                    breakCharCnt = 1
                    
                case .breakOneChar:
                    offset = cw + cwPre
                    ensureCapacity(line + 1)
                    lineStart[line + 1] = length - words[index - 1].count
                    breakCharCnt = 2
                    
                case .breakMoreChar:
                    offset = cw + cwPre
                    ensureCapacity(line + 1)
                    lineStart[line + 1] = length - breakLength
                    breakCharCnt = breakIndex + 1
                    
                case .cps1, .cps2, .cps3:
                    offset = 0
                    ensureCapacity(line + 1)
                    lineStart[line + 1] = length + s.count
                    breakCharCnt = 0
                }
                
                breakLine = true
            }
            
            if breakLine {
                lineWidth[line] = lineW - offset
                lineW = offset
                line += 1
            }
            
            if index == words.count - 1 {
                if !breakLine {
                    offset = 0
                    ensureCapacity(line + 1)
                    lineStart[line + 1] = length + s.count
                    lineWidth[line] = lineW - offset
                    lineW = offset
                    line += 1
                } else if breakCharCnt > 0 {
                    ensureCapacity(line + 1)
                    lineStart[line + 1] = lineStart[line] + breakCharCnt
                    lineWidth[line] = lineW
                    line += 1
                }
            }
            
            length += s.count
            cwPre = cw
        }
        
        // 循环只登记换行处，最后一行（包括不足一行的短段落）仍需提交。
        if length > lineStart[line] {
            ensureCapacity(line + 1)
            lineStart[line + 1] = length
            lineWidth[line] = lineW
            line += 1
        }
        lineCount = line
        
        for i in 0..<lineCount {
            lines.append(ZhLine(
                start: lineStart[i],
                end: lineStart[i + 1],
                width: lineWidth[i]
            ))
        }
    }
    
    private func ensureCapacity(_ line: Int) {
        if lineStart.count <= line + 1 {
            lineStart.append(contentsOf: Array(repeating: 0, count: 10))
            lineWidth.append(contentsOf: Array(repeating: 0, count: 10))
        }
    }
    
    private func isPostPanc(_ string: String) -> Bool {
        return ZhLayout.postPanc.contains(string)
    }
    
    private func isPrePanc(_ string: String) -> Bool {
        return ZhLayout.prePanc.contains(string)
    }
    
    private func inCompressible(_ width: CGFloat) -> Bool {
        return width < cnCharWidth
    }
    
    private func measureWidth(_ text: String, font: UIFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return text.size(withAttributes: attributes).width
    }
    
    var count: Int {
        return lineCount
    }
    
    func getLineStart(_ line: Int) -> Int {
        return lineStart[line]
    }
    
    func getLineEnd(_ line: Int) -> Int {
        return lineStart[line + 1]
    }
    
    func getLineWidth(_ line: Int) -> CGFloat {
        return lineWidth[line]
    }
}