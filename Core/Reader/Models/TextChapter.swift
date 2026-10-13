//
//  TextChapter.swift
//  Legado
//
//  基于 Android Legado 原版 TextChapter.kt 移植
//  原版路径: app/src/main/java/io/legado/app/ui/book/read/page/entities/TextChapter.kt
//

import Foundation

/// 章节信息
/// 一比一移植自 Android Legado TextChapter 数据类
/// 用于管理一个章节的所有页面数据
class TextChapter {
    let chapter: BookChapter?
    let position: Int
    let title: String
    let chaptersSize: Int
    let sameTitleRemoved: Bool
    let isVip: Bool
    let isPay: Bool
    let effectiveReplaceRules: [ReplaceRule]?
    
    private var textPages: [TextPage] = []
    var pages: [TextPage] { textPages }
    
    var isCompleted: Bool = false

    func appendPage(_ page: TextPage) { textPages.append(page) }
    
    static let empty = TextChapter(
        chapter: nil,
        position: -1,
        title: "emptyTextChapter",
        chaptersSize: -1,
        sameTitleRemoved: false,
        isVip: false,
        isPay: false,
        effectiveReplaceRules: nil
    )
    
    init(
        chapter: BookChapter?,
        position: Int,
        title: String,
        chaptersSize: Int,
        sameTitleRemoved: Bool,
        isVip: Bool,
        isPay: Bool,
        effectiveReplaceRules: [ReplaceRule]?
    ) {
        self.chapter = chapter
        self.position = position
        self.title = title
        self.chaptersSize = chaptersSize
        self.sameTitleRemoved = sameTitleRemoved
        self.isVip = isVip
        self.isPay = isPay
        self.effectiveReplaceRules = effectiveReplaceRules
    }
    
    func getPage(_ index: Int) -> TextPage? {
        return pages.indices.contains(index) ? pages[index] : nil
    }
    
    func getPageByReadPos(_ readPos: Int) -> TextPage? {
        return getPage(getPageIndexByCharIndex(readPos))
    }
    
    var lastPage: TextPage? { pages.last }
    var lastIndex: Int { pages.indices.last ?? -1 }
    var lastReadLength: Int { getReadLength(lastIndex) }
    var pageSize: Int { pages.count }
    
    func isLastIndex(_ index: Int) -> Bool {
        return isCompleted && index >= pages.count - 1
    }
    
    func isLastIndexCurrent(_ index: Int) -> Bool {
        return index >= pages.count - 1
    }
    
    func getReadLength(_ pageIndex: Int) -> Int {
        if pageIndex < 0 || pages.isEmpty { return 0 }
        let targetIndex = min(pageIndex, lastIndex)
        return pages[targetIndex].chapterPosition
    }
    
    func getNextPageLength(_ length: Int) -> Int {
        let pageIndex = getPageIndexByCharIndex(length)
        if pageIndex + 1 >= pageSize {
            return -1
        }
        return getReadLength(pageIndex + 1)
    }
    
    func getPrevPageLength(_ length: Int) -> Int {
        let pageIndex = getPageIndexByCharIndex(length)
        if pageIndex - 1 < 0 {
            return -1
        }
        return getReadLength(pageIndex - 1)
    }
    
    func getContent() -> String {
        var result = ""
        for page in pages {
            result += page.text
        }
        return result
    }
    
    func getUnRead(_ pageIndex: Int) -> String {
        var result = ""
        if pages.isEmpty { return result }
        for index in min(max(0, pageIndex), pages.count)..<pages.count {
            result += pages[index].text
        }
        return result
    }
    
    func getPageIndexByCharIndex(_ charIndex: Int) -> Int {
        let pageSize = pages.count
        if pageSize == 0 {
            return -1
        }
        
        for (index, page) in pages.enumerated() {
            if page.chapterPosition > charIndex {
                return max(0, index - 1)
            }
        }
        
        let index = pageSize - 1
        if !isCompleted {
            let page = pages[index]
            let pageEndPos = page.chapterPosition + page.charSize
            if charIndex > pageEndPos {
                return -1
            }
        }
        return index
    }
    
    func clearSearchResult() {
        for page in pages {
            for column in page.searchResult {
                column.selected = false
                column.isSearchResult = false
            }
            page.searchResult.removeAll()
        }
    }
}
