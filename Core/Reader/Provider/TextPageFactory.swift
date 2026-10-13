//
//  TextPageFactory.swift
//  Legado
//
//  基于 Android Legado 原版 TextPageFactory.kt 移植
//  原版路径: app/src/main/java/io/legado/app/ui/book/read/page/provider/TextPageFactory.kt
//

import Foundation

/// 数据源协议
@MainActor
protocol PageDataSource {
    var currentChapter: TextChapter? { get }
    var prevChapter: TextChapter? { get }
    var nextChapter: TextChapter? { get }
    var pageIndex: Int { get }
    
    func hasPrevChapter() -> Bool
    func hasNextChapter() -> Bool
}

/// 页面工厂
/// 一比一移植自 Android Legado TextPageFactory
/// 管理当前页、上一页、下一页的获取
@MainActor
class TextPageFactory {
    private let dataSource: PageDataSource
    
    init(dataSource: PageDataSource) {
        self.dataSource = dataSource
    }
    
    // MARK: - 页面导航
    func hasPrev() -> Bool {
        return dataSource.hasPrevChapter() || dataSource.pageIndex > 0
    }
    
    func hasNext() -> Bool {
        guard let currentChapter = dataSource.currentChapter else { return false }
        return dataSource.hasNextChapter() || !currentChapter.isLastIndex(dataSource.pageIndex)
    }
    
    func hasNextPlus() -> Bool {
        guard let currentChapter = dataSource.currentChapter else { return false }
        return dataSource.hasNextChapter() || dataSource.pageIndex < currentChapter.pageSize - 2
    }
    
    func moveToFirst() {
        ReadBook.shared.setPageIndex(0)
    }
    
    func moveToLast() {
        guard let currentChapter = dataSource.currentChapter else {
            ReadBook.shared.setPageIndex(0)
            return
        }
        if currentChapter.pageSize == 0 {
            ReadBook.shared.setPageIndex(0)
        } else {
            ReadBook.shared.setPageIndex(currentChapter.pageSize - 1)
        }
    }
    
    func moveToNext(upContent: Bool) -> Bool {
        guard hasNext() else { return false }
        
        let pageIndex = dataSource.pageIndex
        guard let currentChapter = dataSource.currentChapter else { return false }
        
        if currentChapter.isLastIndex(pageIndex) {
            ReadBook.shared.moveToNextChapter(upContent, false)
        } else {
            if pageIndex < 0 || currentChapter.isLastIndexCurrent(pageIndex) {
                return false
            }
            ReadBook.shared.setPageIndex(pageIndex + 1)
        }
        
        return true
    }
    
    func moveToPrev(upContent: Bool) -> Bool {
        guard hasPrev() else { return false }
        
        if dataSource.pageIndex <= 0 {
            guard let prevChapter = dataSource.prevChapter else { return false }
            if !prevChapter.isCompleted {
                return false
            }
            ReadBook.shared.moveToPrevChapter(upContent, upContentInPlace: false, startAtEnd: true)
        } else {
            guard dataSource.currentChapter != nil else { return false }
            ReadBook.shared.setPageIndex(dataSource.pageIndex - 1)
        }
        
        return true
    }
    
    // MARK: - 获取页面
    var curPage: TextPage {
        if let msg = ReadBook.shared.msg {
            let page = TextPage(text: msg)
            return page.format()
        }
        if let chapter = dataSource.currentChapter {
            if let page = chapter.getPage(dataSource.pageIndex) {
                return page
            }
            let page = TextPage(title: chapter.title)
            page.textChapter = chapter
            return page.format()
        }
        return TextPage().format()
    }
    
    var nextPage: TextPage {
        if let msg = ReadBook.shared.msg {
            let page = TextPage(text: msg)
            return page.format()
        }
        if let chapter = dataSource.currentChapter {
            let pageIndex = dataSource.pageIndex
            if pageIndex < chapter.pageSize - 1 {
                if let page = chapter.getPage(pageIndex + 1) {
                    return page.removePageAloudSpan()
                }
                return TextPage(title: chapter.title).format()
            }
            if !chapter.isCompleted {
                return TextPage(title: chapter.title).format()
            }
        }
        if let nextChapter = dataSource.nextChapter {
            if let page = nextChapter.getPage(0) {
                return page.removePageAloudSpan()
            }
            return TextPage(title: nextChapter.title).format()
        }
        return TextPage().format()
    }
    
    var prevPage: TextPage {
        if let msg = ReadBook.shared.msg {
            let page = TextPage(text: msg)
            return page.format()
        }
        if let chapter = dataSource.currentChapter {
            let pageIndex = dataSource.pageIndex
            if pageIndex > 0 {
                if let page = chapter.getPage(pageIndex - 1) {
                    return page.removePageAloudSpan()
                }
                return TextPage(title: chapter.title).format()
            }
            if !chapter.isCompleted {
                return TextPage(title: chapter.title).format()
            }
        }
        if let prevChapter = dataSource.prevChapter {
            if let page = prevChapter.lastPage {
                return page.removePageAloudSpan()
            }
            return TextPage(title: prevChapter.title).format()
        }
        return TextPage().format()
    }
    
    var nextPlusPage: TextPage {
        guard let chapter = dataSource.currentChapter else {
            return TextPage().format()
        }
        let pageIndex = dataSource.pageIndex
        if pageIndex < chapter.pageSize - 2 {
            if let page = chapter.getPage(pageIndex + 2) {
                return page.removePageAloudSpan()
            }
            return TextPage(title: chapter.title).format()
        }
        if !chapter.isCompleted {
            return TextPage(title: chapter.title).format()
        }
        if let nextChapter = dataSource.nextChapter {
            if pageIndex < chapter.pageSize - 1 {
                if let page = nextChapter.getPage(0) {
                    return page.removePageAloudSpan()
                }
                return TextPage(title: nextChapter.title).format()
            }
            if let page = nextChapter.getPage(1) {
                return page.removePageAloudSpan()
            }
            return TextPage(text: "继续滑动").format()
        }
        return TextPage().format()
    }
}
