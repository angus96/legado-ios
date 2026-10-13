//
//  ZipBuilder.swift
//  Legado-iOS
//
//  纯 Swift ZIP 打包与解压工具 - 完美适配安卓 Legado WebDAV
//

import Foundation
import Compression
import zlib // 引入系统底层 C 语言解压库

class ZipBuilder {
    
    // ZIP 文件格式常量
    fileprivate static let localFileHeaderSignature: UInt32 = 0x04034b50
    fileprivate static let centralDirectorySignature: UInt32 = 0x02014b50
    fileprivate static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    
    fileprivate static let methodStore: UInt16 = 0
    fileprivate static let methodDeflate: UInt16 = 8
    fileprivate static let flagUTF8: UInt16 = 0x0800
    
    private struct ZipEntry {
        let name: String
        let data: Data
        let compressedData: Data
        let method: UInt16
        let crc32: UInt32
        let lastModified: Date
        let localHeaderOffset: UInt32
        
        var uncompressedSize: UInt32 { UInt32(data.count) }
        var compressedSize: UInt32 { UInt32(compressedData.count) }
    }
    
    private var entries: [ZipEntry] = []
    private let useDeflate: Bool
    
    init(useDeflate: Bool = true) {
        self.useDeflate = useDeflate
    }
    
    // MARK: - [1] ZIP 打包逻辑 (原有功能保留)
    
    func addFile(name: String, data: Data, lastModified: Date = Date()) {
        let crc = computeCRC32(data)
        let entry = ZipEntry(name: name, data: data, compressedData: data, method: ZipBuilder.methodStore, crc32: crc, lastModified: lastModified, localHeaderOffset: 0)
        entries.append(entry)
    }
    
    func addFileAuto(name: String, data: Data, lastModified: Date = Date()) {
        if name == "mimetype" {
            addFile(name: name, data: data, lastModified: lastModified)
            return
        }
        
        if useDeflate && data.count > 0 {
            if let deflated = deflateData(data) {
                let crc = computeCRC32(data)
                let entry = ZipEntry(name: name, data: data, compressedData: deflated, method: ZipBuilder.methodDeflate, crc32: crc, lastModified: lastModified, localHeaderOffset: 0)
                entries.append(entry)
                return
            }
        }
        addFile(name: name, data: data, lastModified: lastModified)
    }
    
    func build() -> Data {
        var result = Data()
        var sortedEntries = entries
        if let mimetypeIndex = sortedEntries.firstIndex(where: { $0.name == "mimetype" }) {
            let mimetypeEntry = sortedEntries.remove(at: mimetypeIndex)
            sortedEntries.insert(mimetypeEntry, at: 0)
        }
        
        var currentOffset: UInt32 = 0
        for i in 0..<sortedEntries.count {
            let entry = sortedEntries[i]
            sortedEntries[i] = ZipEntry(name: entry.name, data: entry.data, compressedData: entry.compressedData, method: entry.method, crc32: entry.crc32, lastModified: entry.lastModified, localHeaderOffset: currentOffset)
            result.append(buildLocalFileHeader(entry: sortedEntries[i]))
            result.append(sortedEntries[i].compressedData)
            currentOffset = UInt32(result.count)
        }
        
        let centralDirectoryOffset = currentOffset
        for entry in sortedEntries {
            result.append(buildCentralDirectoryEntry(entry: entry))
        }
        
        let centralDirectorySize = UInt32(result.count) - centralDirectoryOffset
        result.append(buildEndOfCentralDirectory(entryCount: UInt16(sortedEntries.count), centralDirectorySize: centralDirectorySize, centralDirectoryOffset: centralDirectoryOffset))
        
        return result
    }
    
    // MARK: - [2] 全新硬核解压引擎 (新增功能)
    
    /// 从 ZIP 库读取所有文件并解压
    static func extractZip(data: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        
        guard let eocdOffset = findEOCD(in: data) else {
            throw NSError(domain: "ZipBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法解析 ZIP：找不到中央目录结尾"])
        }
        
        let cdOffset = Int(data.readUInt32(at: eocdOffset + 16))
        let cdCount = Int(data.readUInt16(at: eocdOffset + 10))
        guard cdOffset <= eocdOffset else { throw invalidArchive() }
        var currentOffset = cdOffset
        var totalExpanded = 0
        
        for _ in 0..<cdCount {
            guard currentOffset + 46 <= data.count,
                  data.readUInt32(at: currentOffset) == centralDirectorySignature else { throw invalidArchive() }
            
            let method = data.readUInt16(at: currentOffset + 10)
            let compressedSize = Int(data.readUInt32(at: currentOffset + 20))
            let uncompressedSize = Int(data.readUInt32(at: currentOffset + 24))
            let nameLen = Int(data.readUInt16(at: currentOffset + 28))
            let extraLen = Int(data.readUInt16(at: currentOffset + 30))
            let commentLen = Int(data.readUInt16(at: currentOffset + 32))
            let localHeaderOffset = Int(data.readUInt32(at: currentOffset + 42))
            let recordEnd = currentOffset + 46 + nameLen + extraLen + commentLen
            guard recordEnd <= eocdOffset, uncompressedSize <= 64 * 1024 * 1024,
                  totalExpanded <= 256 * 1024 * 1024 - uncompressedSize else { throw invalidArchive() }
            totalExpanded += uncompressedSize
            
            let nameData = data.subdata(in: currentOffset + 46 ..< currentOffset + 46 + nameLen)
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else { throw invalidArchive() }
            
            if localHeaderOffset + 30 <= data.count,
               data.readUInt32(at: localHeaderOffset) == localFileHeaderSignature {
                let lhNameLen = Int(data.readUInt16(at: localHeaderOffset + 26))
                let lhExtraLen = Int(data.readUInt16(at: localHeaderOffset + 28))
                let dataOffset = localHeaderOffset + 30 + lhNameLen + lhExtraLen
                
                if dataOffset + compressedSize <= data.count {
                    let compressedData = data.subdata(in: dataOffset ..< dataOffset + compressedSize)
                    var uncompressedData: Data?
                    
                    if method == methodStore {
                        uncompressedData = compressedData
                    } else if method == methodDeflate {
                        uncompressedData = inflateRawDeflate(data: compressedData, uncompressedSize: uncompressedSize)
                    }
                    
                    guard let fileData = uncompressedData, fileData.count == uncompressedSize,
                          ZipBuilder().computeCRC32(fileData) == data.readUInt32(at: currentOffset + 16) else { throw invalidArchive() }
                    if !name.hasSuffix("/") { result[name] = fileData }
                } else { throw invalidArchive() }
            } else { throw invalidArchive() }
            currentOffset = recordEnd
        }
        
        if result.isEmpty { throw NSError(domain: "ZipBuilder", code: 2, userInfo: [NSLocalizedDescriptionKey: "解压失败或文件为空"]) }
        return result
    }
    
    private static func findEOCD(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let minOffset = max(0, data.count - 65536 - 22)
        for i in stride(from: data.count - 22, through: minOffset, by: -1) {
            if data[i] == signature[0] && data[i+1] == signature[1] && data[i+2] == signature[2] && data[i+3] == signature[3],
               i + 22 + Int(data.readUInt16(at: i + 20)) == data.count {
                return i
            }
        }
        return nil
    }

    private static func invalidArchive() -> NSError {
        NSError(domain: "ZipBuilder", code: 3, userInfo: [NSLocalizedDescriptionKey: "ZIP 文件损坏、格式不支持或解压大小超出限制"])
    }
    
    // 调用底层 zlib 进行 Raw Deflate 解压
    private static func inflateRawDeflate(data: Data, uncompressedSize: Int) -> Data? {
        var stream = z_stream()
        return data.withUnsafeBytes { sourceBytes in
            guard let sourceBase = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return nil }
            
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: sourceBase)
            stream.avail_in = uInt(data.count)
            
            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
            defer { destBuffer.deallocate() }
            
            stream.next_out = destBuffer
            stream.avail_out = uInt(uncompressedSize)
            
            // -15 窗口位指示 zlib 去解析不带头的纯粹的 Raw Deflate (ZIP 标准格式)
            let initStatus = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else { return nil }
            defer { inflateEnd(&stream) }
            
            let status = inflate(&stream, Z_FINISH)
            if status == Z_STREAM_END, Int(stream.total_out) == uncompressedSize {
                return Data(bytes: destBuffer, count: uncompressedSize)
            }
            return nil
        }
    }
    
    // MARK: - [3] 底层构建工具 (保留)
    
    class func createZip(from files: [String: Data]) throws -> Data {
        let builder = ZipBuilder(useDeflate: false) // 为提高跨端兼容性默认采用 Store 模式
        for (name, data) in files {
            builder.addFileAuto(name: name, data: data)
        }
        return builder.build()
    }
    
    private func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour = components.hour ?? 0; let minute = components.minute ?? 0; let second = components.second ?? 0
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let year = (components.year ?? 1980) - 1980; let month = components.month ?? 1; let day = components.day ?? 1
        let dosDate = UInt16((year << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
    
    private func buildLocalFileHeader(entry: ZipEntry) -> Data {
        var data = Data(); let nameData = entry.name.data(using: .utf8) ?? Data()
        let (dosTime, dosDate) = dosDateTime(from: entry.lastModified)
        data.appendLittleEndian(ZipBuilder.localFileHeaderSignature)
        data.appendLittleEndian(UInt16(20)); data.appendLittleEndian(ZipBuilder.flagUTF8)
        data.appendLittleEndian(entry.method); data.appendLittleEndian(dosTime)
        data.appendLittleEndian(dosDate); data.appendLittleEndian(entry.crc32)
        data.appendLittleEndian(entry.compressedSize); data.appendLittleEndian(entry.uncompressedSize)
        data.appendLittleEndian(UInt16(nameData.count)); data.appendLittleEndian(UInt16(0))
        data.append(nameData)
        return data
    }
    
    private func buildCentralDirectoryEntry(entry: ZipEntry) -> Data {
        var data = Data(); let nameData = entry.name.data(using: .utf8) ?? Data()
        let (dosTime, dosDate) = dosDateTime(from: entry.lastModified)
        data.appendLittleEndian(ZipBuilder.centralDirectorySignature)
        data.appendLittleEndian(UInt16(20)); data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(ZipBuilder.flagUTF8); data.appendLittleEndian(entry.method)
        data.appendLittleEndian(dosTime); data.appendLittleEndian(dosDate)
        data.appendLittleEndian(entry.crc32); data.appendLittleEndian(entry.compressedSize)
        data.appendLittleEndian(entry.uncompressedSize); data.appendLittleEndian(UInt16(nameData.count))
        data.appendLittleEndian(UInt16(0)); data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt16(0)); data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(UInt32(0)); data.appendLittleEndian(entry.localHeaderOffset)
        data.append(nameData)
        return data
    }
    
    private func buildEndOfCentralDirectory(entryCount: UInt16, centralDirectorySize: UInt32, centralDirectoryOffset: UInt32) -> Data {
        var data = Data()
        data.appendLittleEndian(ZipBuilder.endOfCentralDirectorySignature)
        data.appendLittleEndian(UInt16(0)); data.appendLittleEndian(UInt16(0))
        data.appendLittleEndian(entryCount); data.appendLittleEndian(entryCount)
        data.appendLittleEndian(centralDirectorySize); data.appendLittleEndian(centralDirectoryOffset)
        data.appendLittleEndian(UInt16(0))
        return data
    }
    
    private func computeCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF; let table = crc32Table()
        for byte in data { let index = Int((crc ^ UInt32(byte)) & 0xFF); crc = (crc >> 8) ^ table[index] }
        return crc ^ 0xFFFFFFFF
    }
    
    private func crc32Table() -> [UInt32] {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 { if crc & 1 != 0 { crc = (crc >> 1) ^ 0xEDB88320 } else { crc >>= 1 } }
            table[i] = crc
        }
        return table
    }
    
    private func deflateData(_ data: Data) -> Data? { return nil }
}

// MARK: - Data 底层扩展
fileprivate extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: MemoryLayout<UInt16>.size))
    }
    mutating func appendLittleEndian(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: MemoryLayout<UInt32>.size))
    }
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, count >= 2, offset <= count - 2 else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, count >= 4, offset <= count - 4 else { return 0 }
        return UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
}
