import Foundation

@main
struct ReaderLayoutChecks {
    static func main() {
        let samples = ["甲乙丙，。", "甲乙丙《（丁戊）》", "，。！？；：", "短句。",
                       "Wi👨‍👩‍👧‍👦e\u{301}，正文。", String(repeating: "甲乙，。丙丁《戊己》！？", count: 500)]
        var checked = 0
        for text in samples {
            let words = text.map(String.init)
            for size in [18.0, 20, 24, 30] {
                for spacing in [0.0, 1.5, 5] {
                    let widths = words.map { _ in CGFloat(size + spacing) }
                    for width in [80.5, 90, 100, 143.5, 288, 358] {
                        let layout = ZhLayout(words: words, widths: widths, width: width)
                        var next = 0
                        for line in layout.lines {
                            precondition(line.start == next && line.end > line.start)
                            precondition(line.width <= width + 0.001, "正文不能占用右边距")
                            next = line.end
                        }
                        precondition(next == words.count, "换行不能丢失或重复文字")
                        checked += 1
                    }
                }
            }
        }
        print("PASS \(checked) reader wrapping cases preserve text and horizontal bounds")
    }
}
