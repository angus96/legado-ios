import Foundation

enum ReadingProgressMapper {
    static func chapterIndex(previousIndex: Int, previousCount: Int, title: String?, newTitles: [String]) -> Int {
        guard !newTitles.isEmpty else { return 0 }
        if let title, !title.isEmpty, let index = newTitles.firstIndex(of: title) { return index }
        let progress = Double(max(0, previousIndex)) / Double(max(1, previousCount))
        let mapped = min(Double(newTitles.count - 1), max(0, progress * Double(newTitles.count)))
        return Int(mapped)
    }
}
