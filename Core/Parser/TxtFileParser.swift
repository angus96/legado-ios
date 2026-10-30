import Foundation

enum TxtFileParserError: LocalizedError {
    case fileNotFound
    case unreadableData
    case encodingDetectionFailed
    case invalidChapterRange

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "TXT 文件不存在"
        case .unreadableData:
            return "TXT 文件读取失败"
        case .encodingDetectionFailed:
            return "TXT 编码识别失败"
        case .invalidChapterRange:
            return "TXT 章节范围无效"
        }
    }
}

final class TxtFileParser {

    struct ParsedBook {
        let content: String
        let chapters: [ParsedChapter]
        let encoding: String.Encoding
        let encodingName: String
        let tocPattern: String?
        let intro: String?
        let wordCount: Int
    }

    struct ParsedChapter {
        let title: String
        let index: Int
        let range: NSRange
        let contentRange: NSRange
        let wordCount: Int

        var metadataTag: String {
            "txt:\(range.location):\(range.length):\(contentRange.location):\(contentRange.length)"
        }
    }

    private struct CacheEntry {
        let modifiedAt: Date
        let parsedBook: ParsedBook
    }

    private struct EncodingCandidate {
        let encoding: String.Encoding
        let name: String
    }

    private static let cacheLock = NSLock()
    private struct CacheKey: Hashable {
        let path: String
        let pattern: String?
    }
    private static var cache: [CacheKey: CacheEntry] = [:]

    private static let bufferChapterLength = 10 * 1024
    private static let introLength = 500
    // “第一章正文……”是正文行；带空格的“第一章 正文”仍可作为标题。
    private static let defaultChapterPatterns: [String] = [
        #"(?m)^[ 　\t]{0,4}(?:序章|楔子|正文(?=[ 　\t]|$)|终章|后记|尾声|番外|第[ 　\t]{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟A-Za-z]{1,12}[ 　\t]{0,4}(?:章|节(?!课)|卷|集|部|篇|回)(?!正文)).{0,30}$"#,
        #"(?m)^[ 　\t]{0,4}\d{1,5}[、.．:：,， _—\-].{1,30}$"#,
        #"(?m)^[ 　\t]{0,4}.*卷.*章.{0,30}$"#,
        #"(?m)^[ 　\t]{0,4}(?:Chapter|Section|Part|Episode)\s*\d{1,4}.{0,30}$"#
    ]
    private static let leadingPaddingPattern = #"^[\n\s]+"#

    static func parse(file url: URL, preferredPattern: String? = nil) throws -> ParsedBook {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TxtFileParserError.fileNotFound
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date) ?? .distantPast
        let cacheKey = CacheKey(path: url.standardizedFileURL.path, pattern: preferredPattern?.isEmpty == false ? preferredPattern : nil)

        cacheLock.lock()
        if let entry = cache[cacheKey], entry.modifiedAt == modifiedAt {
            cacheLock.unlock()
            return entry.parsedBook
        }
        cacheLock.unlock()

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw TxtFileParserError.unreadableData
        }

        let detectedEncoding = try detectEncoding(for: data)
        guard var content = String(data: data, encoding: detectedEncoding.encoding) else {
            throw TxtFileParserError.encodingDetectionFailed
        }

        if content.hasPrefix("\u{FEFF}") {
            content.removeFirst()
        }
        content = normalizeNewlines(in: content)

        let selectedPattern = preferredPattern?.isEmpty == false ? preferredPattern : bestPattern(for: content)
        let chapters = splitChapters(content: content, pattern: selectedPattern)
        let intro = chapters.first?.title == "前言" ? String(extract(range: chapters[0].contentRange, from: content).prefix(introLength)) : nil

        let parsedBook = ParsedBook(
            content: content,
            chapters: chapters,
            encoding: detectedEncoding.encoding,
            encodingName: detectedEncoding.name,
            tocPattern: selectedPattern,
            intro: intro,
            wordCount: content.count
        )

        cacheLock.lock()
        cache[cacheKey] = CacheEntry(modifiedAt: modifiedAt, parsedBook: parsedBook)
        cacheLock.unlock()

        return parsedBook
    }

    static func readChapter(file url: URL, chapterIndex: Int, metadataTag: String?, preferredPattern: String? = nil) throws -> String {
        let parsedBook = try parse(file: url, preferredPattern: preferredPattern)

        if let range = contentRange(from: metadataTag),
           range.location <= parsedBook.content.utf16.count,
           range.length <= parsedBook.content.utf16.count - range.location {
            return formattedChapterContent(from: range, in: parsedBook.content)
        }

        guard parsedBook.chapters.indices.contains(chapterIndex) else {
            throw TxtFileParserError.invalidChapterRange
        }
        return formattedChapterContent(from: parsedBook.chapters[chapterIndex].contentRange, in: parsedBook.content)
    }

    private static func splitChapters(content: String, pattern: String?) -> [ParsedChapter] {
        guard let pattern, let regex = try? NSRegularExpression(pattern: pattern) else {
            return splitWithoutTableOfContents(content: content)
        }

        let fullRange = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: fullRange)
        guard !matches.isEmpty else {
            return splitWithoutTableOfContents(content: content)
        }

        var chapters: [ParsedChapter] = []
        var chapterIndex = 0

        if matches[0].range.location > 0 {
            let introRange = NSRange(location: 0, length: matches[0].range.location)
            let introText = extract(range: introRange, from: content).trimmingCharacters(in: .whitespacesAndNewlines)
            if !introText.isEmpty {
                chapters.append(
                    ParsedChapter(
                        title: "前言",
                        index: chapterIndex,
                        range: introRange,
                        contentRange: introRange,
                        wordCount: introText.count
                    )
                )
                chapterIndex += 1
            }
        }

        for (offset, match) in matches.enumerated() {
            let nextStart = offset + 1 < matches.count ? matches[offset + 1].range.location : nsLength(of: content)
            let chapterRange = NSRange(location: match.range.location, length: max(0, nextStart - match.range.location))
            let rawTitle = extract(range: match.range, from: content)
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentStart = contentStart(after: match.range, in: content)
            let contentRange = NSRange(location: contentStart, length: max(0, nextStart - contentStart))
            let chapterText = extract(range: contentRange, from: content).trimmingCharacters(in: .whitespacesAndNewlines)

            chapters.append(
                ParsedChapter(
                    title: title.isEmpty ? "第\(chapterIndex + 1)章" : title,
                    index: chapterIndex,
                    range: chapterRange,
                    contentRange: contentRange,
                    wordCount: chapterText.count
                )
            )
            chapterIndex += 1
        }

        return chapters.isEmpty ? splitWithoutTableOfContents(content: content) : chapters
    }

    private static func splitWithoutTableOfContents(content: String) -> [ParsedChapter] {
        var chapters: [ParsedChapter] = []
        let totalLength = nsLength(of: content)
        var location = 0
        var index = 0

        while location < totalLength {
            let remaining = totalLength - location
            let targetLength = min(bufferChapterLength, remaining)
            let end = bestChapterBreak(in: content, start: location, length: targetLength, totalLength: totalLength)
            let range = NSRange(location: location, length: max(0, end - location))
            let chapterContent = extract(range: range, from: content)
            let trimmed = chapterContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chapters.append(
                    ParsedChapter(
                        title: "第\(index + 1)章",
                        index: index,
                        range: range,
                        contentRange: range,
                        wordCount: trimmed.count
                    )
                )
                index += 1
            }
            location = max(end, location + 1)
        }

        if chapters.isEmpty {
            let fullRange = NSRange(location: 0, length: totalLength)
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return [ParsedChapter(title: "第1章", index: 0, range: fullRange, contentRange: fullRange, wordCount: trimmed.count)]
        }

        return chapters
    }

    private static func detectEncoding(for data: Data) throws -> EncodingCandidate {
        if data.starts(with: [0xFF, 0xFE]) {
            return EncodingCandidate(encoding: .utf16LittleEndian, name: "UTF-16LE")
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return EncodingCandidate(encoding: .utf16BigEndian, name: "UTF-16BE")
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return EncodingCandidate(encoding: .utf8, name: "UTF-8")
        }

        let candidates = [
            EncodingCandidate(encoding: .utf8, name: "UTF-8"),
            EncodingCandidate(encoding: gb18030Encoding(), name: "GBK"),
            EncodingCandidate(encoding: gb2312Encoding(), name: "GB2312"),
            EncodingCandidate(encoding: big5Encoding(), name: "BIG5"),
            EncodingCandidate(encoding: .ascii, name: "ASCII")
        ]

        var bestCandidate: EncodingCandidate?
        var bestScore = Int.min

        for candidate in candidates {
            guard let text = String(data: data, encoding: candidate.encoding) else { continue }
            let score = score(text: text, originalData: data, encoding: candidate.encoding)
            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }

        guard let bestCandidate else {
            throw TxtFileParserError.encodingDetectionFailed
        }
        return bestCandidate
    }

    private static func bestPattern(for content: String) -> String? {
        let sample = String(content.prefix(512_000))
        var selectedPattern: String?
        var maxMatches = 1

        for pattern in defaultChapterPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: sample, range: NSRange(sample.startIndex..., in: sample))
            var count = 0
            var lastLocation = -10_000

            for match in matches {
                if match.range.location - lastLocation > 100 {
                    count += 1
                    lastLocation = match.range.location
                }
            }

            if count >= maxMatches {
                maxMatches = count
                selectedPattern = pattern
            }
        }

        return selectedPattern
    }

    private static func score(text: String, originalData: Data, encoding: String.Encoding) -> Int {
        if text.isEmpty { return Int.min / 2 }

        let utf16 = text.utf16
        let total = max(1, utf16.count)
        let replacementCount = text.reduce(into: 0) { partialResult, char in
            if char == "�" { partialResult += 1 }
        }
        let controlCount = text.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            if CharacterSet.controlCharacters.contains(scalar) && scalar.value != 10 && scalar.value != 13 && scalar.value != 9 {
                partialResult += 1
            }
        }
        let chineseCount = text.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                partialResult += 1
            default:
                break
            }
        }
        let suspiciousFragments = ["锘", "鈥", "銆", "鏂", "闂", "Ã", "â", "¤"]
        let suspiciousCount = suspiciousFragments.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }

        var score = 0
        if let encodedBack = text.data(using: encoding), encodedBack == originalData {
            score += 80
        }

        score += max(0, chineseCount * 2)
        score -= replacementCount * 120
        score -= controlCount * 40
        score -= suspiciousCount * 30

        if encoding == .utf8, replacementCount == 0 {
            score += 20
        }

        if chineseCount == 0, encoding != .ascii, text.contains(where: { $0.isASCII == false }) {
            score -= 15
        }

        return score - (controlCount * 100 / total)
    }

    private static func gb18030Encoding() -> String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
    }

    private static func gb2312Encoding() -> String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
            )
        )
    }

    private static func big5Encoding() -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0620))
    }

    private static func contentRange(from metadataTag: String?) -> NSRange? {
        guard let metadataTag, metadataTag.hasPrefix("txt:") else { return nil }
        let components = metadataTag.split(separator: ":")
        guard components.count == 5,
              let location = Int(components[3]),
              let length = Int(components[4]), location >= 0, length >= 0,
              location <= Int.max - length else {
            return nil
        }
        return NSRange(location: location, length: length)
    }

    private static func formattedChapterContent(from range: NSRange, in content: String) -> String {
        let rawContent = extract(range: range, from: content)
        let formatted = rawContent.replacingOccurrences(of: leadingPaddingPattern, with: "　　", options: .regularExpression)
        return formatted.isEmpty ? "　　" : formatted
    }

    private static func contentStart(after titleRange: NSRange, in content: String) -> Int {
        let totalLength = nsLength(of: content)
        var location = min(totalLength, titleRange.location + titleRange.length)
        let nsContent = content as NSString

        while location < totalLength {
            let char = nsContent.substring(with: NSRange(location: location, length: 1))
            if char == "\n" || char == "\r" {
                location += 1
                while location < totalLength {
                    let nextChar = nsContent.substring(with: NSRange(location: location, length: 1))
                    if nextChar == "\n" || nextChar == "\r" {
                        location += 1
                    } else {
                        break
                    }
                }
                break
            }
            location += 1
        }
        return location
    }

    private static func bestChapterBreak(in content: String, start: Int, length: Int, totalLength: Int) -> Int {
        let nsContent = content as NSString
        let targetEnd = min(start + length, totalLength)
        if targetEnd >= totalLength { return totalLength }

        var location = targetEnd
        while location < totalLength {
            let char = nsContent.substring(with: NSRange(location: location, length: 1))
            if char == "\n" || char == "\r" {
                return location + 1
            }
            location += 1
            if location - targetEnd > 512 { break }
        }
        return targetEnd
    }

    private static func normalizeNewlines(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func extract(range: NSRange, from text: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    private static func nsLength(of text: String) -> Int {
        (text as NSString).length
    }
}
