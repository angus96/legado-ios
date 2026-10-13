import Foundation
import CoreData
import UIKit

enum WebDAVSyncError: LocalizedError {
    case noBackups
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .noBackups:
            return "云端没有可用备份"
        case .invalidBackup:
            return "备份文件格式不正确或解压失败"
        }
    }
}

enum WebDAVSettingsStore {
    static let serverURLKey = "webdav.serverURL"
    static let usernameKey = "webdav.username"
    static let passwordKey = "webdav.password"
    static let backupPathKey = "webdav.backupPath"
    static let defaultBackupPath = "/legado-ios/backups"

    static var backupPath: String {
        normalizePath(UserDefaults.standard.string(forKey: backupPathKey) ?? defaultBackupPath)
    }

    static func normalizePath(_ input: String) -> String {
        var path = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return defaultBackupPath
        }
        if !path.hasPrefix("/") {
            path = "/\(path)"
        }
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        return path
    }
}

@MainActor
class WebDAVSyncManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastSyncTime: Date?
    @Published var syncProgress: Double = 0

    let client: WebDAVClient
    private let context = CoreDataStack.shared.viewContext

    init(client: WebDAVClient) {
        self.client = client
    }

    func testConnection() async throws -> Bool {
        do {
            try await ensureBackupDirectoryExists()
            _ = try await client.list(path: WebDAVSettingsStore.backupPath)
            isConnected = true
            return true
        } catch {
            isConnected = false
            throw error
        }
    }

    // MARK: - 备份逻辑 (打包为安卓兼容的 ZIP)
    func backup() async throws {
        syncProgress = 0
        let payload = try BackupStore.export(context: context)
        let zipBuilder = ZipBuilder()
        let fileNames = ["books": "books.json", "sources": "bookSources.json", "rules": "replaceRules.json",
                         "chapters": "bookChapters.json", "bookmarks": "bookmarks.json"]
        for (key, name) in fileNames {
            guard let rows = payload[key] else { continue }
            let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            zipBuilder.addFileAuto(name: name, data: data)
        }
        syncProgress = 0.35

        try await ensureBackupDirectoryExists()
        let zipData = zipBuilder.build()

        let fileName = buildBackupFileName(timestamp: Date(), deviceName: UIDevice.current.name)
        let uploadPath = "\(WebDAVSettingsStore.backupPath)/\(fileName)"
        try await client.upload(path: uploadPath, data: zipData)

        syncProgress = 1
        lastSyncTime = Date()
    }

    // MARK: - 恢复逻辑 (下载并调用解压引擎)
    func restore() async throws {
        syncProgress = 0
        let backups = try await listBackups()
        guard let latestBackup = backups.first else { throw WebDAVSyncError.noBackups }

        syncProgress = 0.25
        let zipData = try await client.download(path: latestBackup.path)

        syncProgress = 0.50
        // 调用我们修改后的 ZipBuilder.extractZip
        guard let extractedFiles = try? ZipBuilder.extractZip(data: zipData) else {
            throw WebDAVSyncError.invalidBackup
        }

        syncProgress = 0.75
        try restoreFromExtractedFiles(extractedFiles)
        
        syncProgress = 1
        lastSyncTime = Date()
    }

    private func restoreFromExtractedFiles(_ files: [String: Data]) throws {
        let payload = try BackupStore.payload(from: files)
        _ = try BackupStore.restore(payload, container: CoreDataStack.shared.persistentContainer)
    }

    // MARK: - 基础辅助方法
    func listBackups() async throws -> [BackupInfo] {
        let backupPath = WebDAVSettingsStore.backupPath
        guard try await client.exists(path: backupPath) else { return [] }
        let files = try await client.list(path: backupPath)
        return files
            .filter { !$0.isDirectory && $0.name.lowercased().hasSuffix(".zip") }
            .map { file in
                let date = file.lastModified ?? parseBackupDate(from: file.name) ?? Date.distantPast
                return BackupInfo(path: file.path, date: date, size: file.size ?? 0, deviceName: parseDeviceName(from: file.name))
            }
            .sorted { $0.date > $1.date }
    }

    private func ensureBackupDirectoryExists() async throws {
        let fullPath = WebDAVSettingsStore.backupPath
        if fullPath == "/" { return }
        var current = ""
        for part in fullPath.split(separator: "/") {
            current += "/\(part)"
            if try await client.exists(path: current) { continue }
            try await client.createDirectory(path: current)
        }
    }

    private func buildBackupFileName(timestamp: Date, deviceName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let datePart = formatter.string(from: timestamp)
        return "legado_backup_\(sanitizedDeviceName(deviceName))_\(datePart).zip"
    }

    private func parseBackupDate(from fileName: String) -> Date? {
        guard fileName.hasPrefix("legado_backup_"), fileName.hasSuffix(".zip") else { return nil }
        let raw = String(fileName.dropFirst("legado_backup_".count).dropLast(".zip".count))
        let parts = raw.split(separator: "_")
        guard parts.count >= 2 else { return nil }
        let datePart = "\(parts[parts.count - 2])_\(parts[parts.count - 1])"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.date(from: datePart)
    }

    private func parseDeviceName(from fileName: String) -> String? {
        guard fileName.hasPrefix("legado_backup_") else { return nil }
        let raw = fileName.replacingOccurrences(of: "legado_backup_", with: "").replacingOccurrences(of: ".zip", with: "")
        let parts = raw.split(separator: "_")
        return parts.dropLast(2).joined(separator: " ")
    }

    private func sanitizedDeviceName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(value.unicodeScalars.filter { allowed.contains($0) })
    }

    private func latestLocalUpdateTime() -> Date {
        let books: [Book] = (try? context.fetch(Book.fetchRequest())) ?? []
        return books.map(\.updatedAt).max() ?? .distantPast
    }
}
