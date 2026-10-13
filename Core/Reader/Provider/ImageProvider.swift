//
//  ImageProvider.swift
//  Legado-iOS
//
//  基于 Android Legado 原版 ImageProvider.kt 严格一比一移植
//  原版路径: app/src/main/java/io/legado/app/model/ImageProvider.kt
//  原版行数: 212 行
//

import UIKit
import Foundation
import PDFKit
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

/// 图片提供者
/// 一比一移植自 Android Legado ImageProvider
/// 负责图片缓存、获取、尺寸测量等功能
enum ImageProvider {
    
    // MARK: - 常量 (对照原版 line 41-48)
    private static let M = 1024 * 1024
    
    /// 缓存大小 (对照原版 cacheSize)
    /// Android 原版使用 AppConfig.bitmapCacheSize，默认 50MB
    static var cacheSize: Int {
        // iOS 版本使用 AppConstants 配置，默认 100MB
        // 原版: if (AppConfig.bitmapCacheSize !in 1..1024) { AppConfig.bitmapCacheSize = 50 }
        //       return AppConfig.bitmapCacheSize * M
        let configuredSize = AppConstants.imageCacheMemoryLimit / M
        if configuredSize < 1 || configuredSize > 1024 {
            return 50 * M  // 默认 50MB，对照原版
        }
        return configuredSize * M
    }
    
    // MARK: - 错误图片 (对照原版 line 33-35)
    /// 错误占位图，防止一直重复获取图片
    /// Android 原版: private val errorBitmap: Bitmap by lazy { BitmapFactory.decodeResource(...) }
    private static let errorImage: UIImage = {
        // 创建一个简单的灰色占位图
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.systemGray4.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        // 绘制图标
        UIColor.systemGray2.setFill()
        let iconRect = CGRect(x: size.width/2 - 20, y: size.height/2 - 20, width: 40, height: 40)
        let path = UIBezierPath(ovalIn: iconRect)
        path.fill()
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }()
    
    // MARK: - LruCache (对照原版 line 50-81)
    /// 图片 LruCache 缓存
    /// Android 原版使用 androidx.collection.LruCache<String, Bitmap>
    /// iOS 使用 NSCache 实现类似功能
    static let bitmapLruCache = BitmapLruCache()
    
    /// Bitmap LruCache 类
    /// 对照 Android 原版 BitmapLruCache inner class (line 52-81)
    final class BitmapLruCache {
        
        private let cache = NSCache<NSString, UIImage>()
        private var removeCount: Int = 0
        private var currentSize: Int = 0
        private let lock = NSLock()
        
        /// 当前缓存数量 (对照原版 count)
        var count: Int {
            // 原版: putCount() + createCount() - evictionCount() - removeCount
            // NSCache 不提供这些统计，使用简化版本
            lock.lock()
            let c = removeCount
            lock.unlock()
            return c
        }
        
        init() {
            cache.totalCostLimit = ImageProvider.cacheSize
            cache.countLimit = 100
        }
        
        /// 计算 UIImage 内存大小 (对照原版 sizeOf)
        /// Android 原版: override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
        private func imageCost(_ image: UIImage) -> Int {
            // iOS: height * width * scale * 4 (RGBA)
            return Int(image.size.height * image.size.width * image.scale * 4)
        }
        
        /// 当条目被移除时的处理 (对照原版 entryRemoved)
        /// Android 原版在 entryRemoved 中检查是否为 errorBitmap，如果是则不释放
        func onEntryRemoved(key: String, oldValue: UIImage, evicted: Bool) {
            if !evicted {
                lock.lock()
                removeCount += 1
                lock.unlock()
            }
            // 错误图片不能释放，占位用，防止一直重复获取图片
            // 原版: if (oldValue != errorBitmap) { oldValue.recycle() }
            // iOS UIImage 不需要手动 recycle，由 ARC 管理
        }
        
        // MARK: - 缓存操作
        
        func get(_ key: String) -> UIImage? {
            return cache.object(forKey: key as NSString)
        }
        
        func put(_ key: String, image: UIImage) {
            ensureLruCacheSize(image)
            let cost = imageCost(image)
            cache.setObject(image, forKey: key as NSString, cost: cost)
            
            lock.lock()
            currentSize += cost
            lock.unlock()
        }
        
        func remove(_ key: String) -> UIImage? {
            let image = cache.object(forKey: key as NSString)
            if image != nil {
                cache.removeObject(forKey: key as NSString)
            }
            return image
        }
        
        func evictAll() {
            cache.removeAllObjects()
            lock.lock()
            currentSize = 0
            removeCount = 0
            lock.unlock()
        }
        
        func resize(_ newSize: Int) {
            cache.totalCostLimit = newSize
        }
        
        func maxSize() -> Int {
            return cache.totalCostLimit
        }
        
        func size() -> Int {
            lock.lock()
            let s = currentSize
            lock.unlock()
            return s
        }
        
        // MARK: - 确保缓存大小 (对照原版 line 105-119)
        private func ensureLruCacheSize(_ image: UIImage) {
            let lruMaxSize = maxSize()
            let lruSize = size()
            let byteCount = imageCost(image)
            
            let newSize: Int
            if byteCount > lruMaxSize {
                // 原版: min(256 * M, (byteCount * 1.3).toInt())
                newSize = min(256 * ImageProvider.M, Int(Double(byteCount) * 1.3))
            } else if lruSize + byteCount > lruMaxSize && count < 5 {
                // 原版: min(256 * M, (lruSize + byteCount * 1.3).toInt())
                newSize = min(256 * ImageProvider.M, Int(Double(lruSize + byteCount) * 1.3))
            } else {
                newSize = lruMaxSize
            }
            
            if newSize > lruMaxSize {
                resize(newSize)
            }
        }
    }
    
    // MARK: - 缓存操作 (对照原版 line 83-103)
    
    /// 添加图片到缓存 (对照原版 put)
    static func put(_ key: String, image: UIImage) {
        bitmapLruCache.put(key, image: image)
    }
    
    /// 从缓存获取图片 (对照原版 get)
    static func get(_ key: String) -> UIImage? {
        return bitmapLruCache.get(key)
    }
    
    /// 从缓存移除图片 (对照原版 remove)
    static func remove(_ key: String) -> UIImage? {
        return bitmapLruCache.remove(key)
    }
    
    /// 获取未回收的图片 (对照原版 getNotRecycled)
    /// Android Bitmap 有 isRecycled 概念，iOS UIImage 由 ARC 管理，无需此检查
    static func getNotRecycled(_ key: String) -> UIImage? {
        return bitmapLruCache.get(key)
    }
    
    // MARK: - 缓存图片 (对照原版 line 124-150)
    
    /// 缓存网络图片和本地书籍图片
    /// 对照 Android 原版 suspend fun cacheImage(book: Book, src: String, bookSource: BookSource?): File
    static func cacheImage(
        book: Book,
        src: String,
        bookSource: BookSource?
    ) async -> URL {
        let fileURL = BookHelp.getImage(book, src)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return fileURL }
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            await BookHelp.saveImage(bookSource: bookSource, book: book, src: src)
        } else {
            let data: Data? = try? ManagedObjectAccess.read(book) { book -> Data? in
                if book.isEpub { return EpubFile.getImage(book, src) }
                if book.isPdf { return PdfFile.getImage(book, src) }
                if book.isMobi { return MobiFile.getImage(book, src) }
                return nil
            }
            if let data { try? data.write(to: fileURL, options: .atomic) }
        }
        return fileURL
    }
    
    // MARK: - 获取图片尺寸 (对照原版 line 155-174)
    
    /// 获取图片宽度高度信息
    /// 对照 Android 原版 suspend fun getImageSize(book: Book, src: String, bookSource: BookSource?): Size
    static func getImageSize(
        book: Book,
        src: String,
        bookSource: BookSource?
    ) async -> CGSize {
        let fileURL = await cacheImage(book: book, src: src, bookSource: bookSource)
        
        // 原版使用 BitmapFactory.Options().inJustDecodeBounds = true
        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
            if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary) as? [CFString: Any] {
                let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
                let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
                
                if width > 0 && height > 0 {
                    return CGSize(width: width, height: height)
                }
            }
        }
        
        // SVG 支持 (原版 line 167-168)
        // iOS 暂不支持 SVG 尺寸获取，使用错误图片尺寸
        // 原版: val size = SvgUtils.getSize(file.absolutePath)
        //       if (size != null) return size
        
        // 原版 line 169-171: 不支持的图片类型，返回错误图片尺寸
        print("[ImageProvider] \(src) Unsupported image type")
        return errorImage.size
    }
    
    // MARK: - 获取图片 (对照原版 line 179-206)
    
    /// 获取图片，使用 LruCache 缓存
    /// 对照 Android 原版 fun getImage(book: Book, src: String, width: Int, height: Int?): Bitmap
    static func getImage(
        book: Book,
        src: String,
        width: Int,
        height: Int? = nil
    ) -> UIImage {
        // 原版 line 186-189: src 为空白时的处理
        if src.isEmpty {
            try? ManagedObjectAccess.read(book) { book in
                if book.getUseReplaceRule() { book.setUseReplaceRule(false) }
            }
        }
        
        let vFileURL = BookHelp.getImage(book, src)
        
        // 原版 line 191: if (!vFile.exists()) return errorBitmap
        if !FileManager.default.fileExists(atPath: vFileURL.path) {
            return errorImage
        }
        
        // 原版 line 194-195: 使用缓存文件路径作为 key
        let cacheKey = vFileURL.path
        if let cacheImage = getNotRecycled(cacheKey) {
            return cacheImage
        }
        
        // 原版 line 196-205: 解码图片
        do {
            let image = decodeImage(fileURL: vFileURL, width: width, height: height)
            if image != nil && image != errorImage {
                put(cacheKey, image: image!)
                return image!
            }
        } catch {
            print("[ImageProvider] decode error: \(error)")
        }
        
        // 原版 line 204: 错误图片占位，防止重复获取
        put(cacheKey, image: errorImage)
        return errorImage
    }
    
    // MARK: - 解码图片 (辅助方法)
    
    /// 解码图片文件
    /// 对照 Android 原版 BitmapUtils.decodeBitmap + SvgUtils.createBitmap
    private static func decodeImage(fileURL: URL, width: Int, height: Int?) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        // 使用 CGImageSource 进行高效解码（类似 Android BitmapFactory）
        if let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height ?? width)
            ]
            
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage)
            }
        }
        
        // 直接解码
        return UIImage(data: data)
    }
    
    // MARK: - 清空缓存 (对照原版 line 208-210)
    
    /// 清空所有缓存
    static func clear() {
        bitmapLruCache.evictAll()
    }
}

// MARK: - Book 扩展方法

/// Book 类型判断扩展
/// 对照 Android 原版 BookHelp.isEpub/isPdf/isMobi 等
extension Book {
    var isEpub: Bool {
        let path = bookUrl.lowercased()
        return path.hasSuffix(".epub")
    }
    
    var isPdf: Bool {
        let path = bookUrl.lowercased()
        return path.hasSuffix(".pdf")
    }
    
    var isMobi: Bool {
        let path = bookUrl.lowercased()
        return path.hasSuffix(".mobi")
    }
    
    func getUseReplaceRule() -> Bool {
        return readConfigObj.useReplaceRule
    }
    
    func setUseReplaceRule(_ value: Bool) {
        var config = readConfigObj
        config.useReplaceRule = value
        readConfigObj = config
    }
}

// MARK: - 占位类（待后续实现）

enum EpubFile {
    static func getImage(_ book: Book, _ src: String) -> Data? {
        guard let epubCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("epub_cache")
            .appendingPathComponent(book.bookId.uuidString) else { return nil }
        
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            guard let url = URL(string: src) else { return nil }
            return try? Data(contentsOf: url)
        }
        
        let imagePath = epubCacheDir.appendingPathComponent(src)
        if FileManager.default.fileExists(atPath: imagePath.path) {
            return try? Data(contentsOf: imagePath)
        }
        
        let bookURL = URL(string: book.bookUrl) ?? URL(fileURLWithPath: book.bookUrl)
        if bookURL.pathExtension.lowercased() == "epub" {
            return extractFromEPUB(url: bookURL, imagePath: src)
        }
        
        return nil
    }
    
    private static func extractFromEPUB(url: URL, imagePath: String) -> Data? {
        #if canImport(ZIPFoundation)
        var searchPath = imagePath
        if searchPath.hasPrefix("/") {
            searchPath = String(searchPath.dropFirst())
        }
        
        guard let archive = Archive(url: url, accessMode: .read) else { return nil }
        
        for entry in archive {
            if entry.path.hasSuffix(searchPath) || entry.path == searchPath {
                var data = Data()
                _ = try? archive.extract(entry, consumer: { chunk in
                    data.append(chunk)
                })
                return data.isEmpty ? nil : data
            }
        }
        #endif
        
        return nil
    }
}

enum PdfFile {
    static func getImage(_ book: Book, _ src: String) -> Data? {
        let bookURL = URL(string: book.bookUrl) ?? URL(fileURLWithPath: book.bookUrl)
        guard bookURL.pathExtension.lowercased() == "pdf" else { return nil }
        
        guard let document = PDFDocument(url: bookURL) else { return nil }
        
        if let pageNum = Int(src.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()),
           pageNum > 0, pageNum <= document.pageCount {
            guard let page = document.page(at: pageNum - 1) else { return nil }
            let pageRect = page.bounds(for: .mediaBox)
            let renderer = UIGraphicsImageRenderer(size: pageRect.size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(pageRect)
                ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            return image.pngData()
        }
        
        return nil
    }
}

enum MobiFile {
    static func getImage(_ book: Book, _ src: String) -> Data? {
        let bookURL = URL(string: book.bookUrl) ?? URL(fileURLWithPath: book.bookUrl)
        guard bookURL.pathExtension.lowercased() == "mobi" || bookURL.pathExtension.lowercased() == "azw3" else { return nil }
        
        return nil
    }
}
