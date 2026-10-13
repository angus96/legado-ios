//
//  CookieManager.swift
//  Legado-iOS
//
//  Cookie 管理器 - 对标 Android Cookie 持久化
//  功能：存储、读取、自动注入 Cookie
//

import Foundation
import CoreData

/// Cookie 管理器
/// 负责书源 Cookie 的持久化和自动注入
final class CookieManager {
    static let shared = CookieManager()
    
    private let sessionCookieStorage: HTTPCookieStorage
    private let storageContext: NSManagedObjectContext
    
    init(stack: CoreDataStack = .shared, cookieStorage: HTTPCookieStorage = .shared) {
        sessionCookieStorage = cookieStorage
        storageContext = stack.newBackgroundContext()
    }
    
    // MARK: - 存储 Cookie
    
    /// 保存 Cookie 到数据库
    /// - Parameters:
    ///   - url: 关联的 URL（通常是书源地址）
    ///   - cookieString: Cookie 字符串（如 "key1=value1; key2=value2"）
    func saveCookie(url: String, cookieString: String) {
        let context = storageContext
        
        // 检查是否已存在
        let fetchRequest: NSFetchRequest<Cookie> = Cookie.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "url == %@", url)
        
        do {
            try context.performAndWait {
                let existing = try context.fetch(fetchRequest).first
            
            if let existing = existing {
                existing.cookie = cookieString
            } else {
                _ = Cookie.create(in: context, url: url, cookie: cookieString)
            }
            
            try context.save()
            updateSessionCookies(url: url, cookieString: cookieString)
            }
            
        } catch {
            context.performAndWait { context.rollback() }
            DebugLogger.shared.log("保存 Cookie 失败: \(error)")
        }
    }
    
    /// 从 HTTPURLResponse 提取并保存 Cookie
    func saveCookies(from response: HTTPURLResponse, for url: URL) {
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { headers, field in
            headers[String(describing: field.key)] = String(describing: field.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        guard !cookies.isEmpty else { return }
        let hostKey = url.host ?? url.absoluteString
        do {
            try storageContext.performAndWait {
                sessionCookieStorage.setCookies(cookies, for: url, mainDocumentURL: nil)
                let cookieString = (sessionCookieStorage.cookies(for: url) ?? [])
                    .map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                let request = Cookie.fetchRequest()
                request.predicate = NSPredicate(format: "url == %@", hostKey)
                if let existing = try storageContext.fetch(request).first {
                    existing.cookie = cookieString
                } else {
                    _ = Cookie.create(in: storageContext, url: hostKey, cookie: cookieString)
                }
                try storageContext.save()
            }
        } catch {
            storageContext.performAndWait { storageContext.rollback() }
            DebugLogger.shared.log("保存响应 Cookie 失败: \(error)")
        }
    }
    
    // MARK: - 读取 Cookie
    
    /// 获取指定 URL 的 Cookie
    func getCookie(for url: String) -> String? {
        let context = storageContext
        
        let fetchRequest: NSFetchRequest<Cookie> = Cookie.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "url == %@", url)
        fetchRequest.fetchLimit = 1
        
        do {
            return try context.performAndWait { try context.fetch(fetchRequest).first?.cookie }
        } catch {
            DebugLogger.shared.log("读取 Cookie 失败: \(error)")
            return nil
        }
    }
    
    /// 获取所有 Cookie
    func getAllCookies() -> [(url: String, cookie: String)] {
        let context = storageContext
        
        let fetchRequest: NSFetchRequest<Cookie> = Cookie.fetchRequest()
        
        do {
            return try context.performAndWait {
                let cookies = try context.fetch(fetchRequest)
                return cookies.map { ($0.url, $0.cookie) }
            }
        } catch {
            DebugLogger.shared.log("读取所有 Cookie 失败: \(error)")
            return []
        }
    }
    
    // MARK: - 注入 Cookie
    
    /// 为请求添加 Cookie Header
    func addCookieHeader(to request: inout URLRequest, for url: URL) {
        // 优先使用 session 中的 Cookie
        if let cookies = sessionCookieStorage.cookies(for: url),
           !cookies.isEmpty {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            return
        }
        
        // 从数据库读取
        let hostKey = url.host ?? url.absoluteString
        if let cookieString = getCookie(for: hostKey) {
            request.setValue(cookieString, forHTTPHeaderField: "Cookie")
        }
    }
    
    // MARK: - 删除 Cookie
    
    /// 删除指定 URL 的 Cookie
    func deleteCookie(for url: String) {
        let context = storageContext
        
        let fetchRequest: NSFetchRequest<Cookie> = Cookie.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "url == %@", url)
        
        do {
            try context.performAndWait {
                let cookies = try context.fetch(fetchRequest)
                cookies.forEach { context.delete($0) }
                try context.save()
                let host = URL(string: url)?.host ?? url
                sessionCookieStorage.cookies?.filter { $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host }
                    .forEach { sessionCookieStorage.deleteCookie($0) }
            }
        } catch {
            DebugLogger.shared.log("删除 Cookie 失败: \(error)")
        }
    }
    
    /// 清空所有 Cookie
    func clearAllCookies() {
        let context = storageContext
        
        let fetchRequest = Cookie.fetchRequest()
        
        do {
            try context.performAndWait {
                try context.fetch(fetchRequest).forEach { context.delete($0) }
                try context.save()
                if let cookies = sessionCookieStorage.cookies {
                    cookies.forEach { sessionCookieStorage.deleteCookie($0) }
                }
            }
        } catch {
            DebugLogger.shared.log("清空 Cookie 失败: \(error)")
        }
    }
    
    // MARK: - Private
    
    private func updateSessionCookies(url: String, cookieString: String) {
        let domain = URL(string: url)?.host ?? url
        guard !domain.isEmpty else { return }
        
        // 解析 Cookie 字符串
        let cookiePairs = cookieString.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        
        for pair in cookiePairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let name = String(parts[0])
            let value = String(parts[1])
            
            let cookie = HTTPCookie(properties: [
                .name: name,
                .value: value,
                .domain: domain,
                .path: "/",
                .secure: "FALSE"
            ])
            
            if let cookie = cookie {
                sessionCookieStorage.setCookie(cookie)
            }
        }
    }
}
