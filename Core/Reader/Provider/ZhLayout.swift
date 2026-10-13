import Foundation

/// 按实际字宽换行，优先避免标点出现在行首、左括号留在行尾。
/// 放不下的标点随前文移到下一行，不借用左右边距。
final class ZhLayout {
    static let postPanc: Set<String> = [
        "，", "。", "：", "？", "！", "、", "”", "’", "）", "》",
        "】", ")", ">", "]", "}", ",", ".", "?", "!", ":", "」", "；", ";"
    ]
    static let prePanc: Set<String> = ["“", "（", "《", "【", "‘", "(", "<", "[", "{", "「"]

    struct ZhLine {
        let start: Int
        let end: Int
        let width: CGFloat
    }

    private(set) var lines: [ZhLine] = []

    init(words: [String], widths: [CGFloat], width: CGFloat) {
        guard width > 0, width.isFinite, words.count == widths.count else { return }
        var positions = [0]
        var advances: [CGFloat] = [0]
        for (word, advance) in zip(words, widths) {
            positions.append(positions.last! + word.count)
            advances.append(advances.last! + (advance.isFinite ? max(0, advance) : 0))
        }
        var start = 0
        while start < words.count {
            var end = start
            while end < words.count {
                // 单个字符即使宽于整行也必须前进，避免极窄区域陷入循环。
                if end > start && advances[end + 1] - advances[start] > width { break }
                end += 1
            }
            if end < words.count {
                var candidate = end
                while candidate > start + 1 &&
                    (Self.postPanc.contains(words[candidate]) || Self.prePanc.contains(words[candidate - 1])) {
                    candidate -= 1
                }
                if !Self.postPanc.contains(words[candidate]) && !Self.prePanc.contains(words[candidate - 1]) {
                    end = candidate
                }
            }
            lines.append(ZhLine(start: positions[start], end: positions[end],
                                width: advances[end] - advances[start]))
            start = end
        }
    }

    var count: Int { lines.count }
    func getLineStart(_ line: Int) -> Int { lines[line].start }
    func getLineEnd(_ line: Int) -> Int { lines[line].end }
    func getLineWidth(_ line: Int) -> CGFloat { lines[line].width }
}
