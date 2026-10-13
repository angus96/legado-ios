//
//  BackupRestoreView.swift
//  Legado-iOS
//
//  备份与恢复视图
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @StateObject private var viewModel = BackupRestoreViewModel()
    @State private var showingExport = false
    @State private var showingImport = false
    
    var body: some View {
        Form {
            Section {
                Button(action: { showingExport = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("导出数据")
                    }
                }
                
                Button(action: viewModel.backupAll) {
                    HStack {
                        Image(systemName: "doc")
                        Text("备份书架和规则")
                    }
                }
            } header: {
                Label("备份", systemImage: "square.and.arrow.up")
            } footer: {
                Text("包含书架、书源规则、目录、书签和替换规则。正文缓存、本地书籍文件及 RSS 等设置需要另行保存。")
            }
            
            Section(header: Label("恢复", systemImage: "square.and.arrow.down")) {
                Button(action: { showingImport = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("导入数据")
                    }
                }
                
                Button(action: viewModel.restoreFromBackup) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("从备份恢复")
                    }
                }
            }
            
            Section(header: Label("云同步", systemImage: "cloud")) {
                NavigationLink {
                    WebDAVConfigView()
                } label: {
                    HStack {
                        Image(systemName: "externaldrive.badge.wifi")
                        Text("WebDAV 同步")
                    }
                }

                Toggle("iCloud 同步", isOn: .constant(false))
                
                Text("iCloud 同步功能开发中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button(role: .destructive, action: viewModel.clearAllData) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清空所有数据")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("备份与恢复")
        .sheet(isPresented: $showingExport) {
            ExportDataView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingImport) {
            ImportDataView(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $viewModel.showingRestoreImporter,
            allowedContentTypes: [.json, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let fileURL = urls.first else { return }
                viewModel.restoreFromBackupFile(fileURL)
            case .failure(let error):
                viewModel.alertMessage = "选择文件失败：\(error.localizedDescription)"
                viewModel.showingAlert = true
            }
        }
        .alert("提示", isPresented: $viewModel.showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }
}

// MARK: - ViewModel
@MainActor
class BackupRestoreViewModel: ObservableObject {
    @Published var isBackingUp = false
    @Published var isRestoring = false
    @Published var showingRestoreImporter = false
    @Published var showingAlert = false
    @Published var alertMessage: String?
    
    private let context = CoreDataStack.shared.viewContext
    
    // MARK: - 备份所有数据
    func backupAll() {
        isBackingUp = true
        
        do {
            let dataDict = try BackupStore.export(context: context)

            let jsonData = try JSONSerialization.data(withJSONObject: dataDict, options: .prettyPrinted)
            
            // 保存到文件
            try saveExportFile(data: jsonData, filename: "legado_backup_\(Date().timeIntervalSince1970).json")
            
            isBackingUp = false
            alertMessage = "备份成功！"
            showingAlert = true
        } catch {
            isBackingUp = false
            alertMessage = "备份失败：\(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    // MARK: - 从备份恢复
    func restoreFromBackup() {
        showingRestoreImporter = true
    }

    func restoreFromBackupFile(_ fileURL: URL) {
        isRestoring = true
        defer { isRestoring = false }

        let granted = fileURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let result = try restoreFromBackupData(data)
            let summary = [
                "书籍 \(result.books) 本",
                "书源 \(result.sources) 个",
                "规则 \(result.rules) 条"
            ].joined(separator: "，")
            alertMessage = "恢复成功：\(summary)"
        } catch {
            alertMessage = "恢复失败：\(error.localizedDescription)"
        }
        showingAlert = true
    }
    
    // MARK: - 清空所有数据
    func clearAllData() {
        // 删除所有实体
        let entities = ["Book", "BookSource", "BookChapter", "Bookmark", "ReplaceRule"]
        
        for entityName in entities {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
            if let objects = try? context.fetch(fetchRequest) {
                for object in objects {
                    context.delete(object)
                }
            }
        }
        
        try? CoreDataStack.shared.save()
        
        alertMessage = "数据已清空"
        showingAlert = true
    }
    
    private func restoreFromBackupData(_ data: Data) throws -> (books: Int, sources: Int, rules: Int) {
        let object = try JSONSerialization.jsonObject(with: data)
        let payload: [String: Any]
        if let dictionary = object as? [String: Any] {
            if dictionary["bookSourceUrl"] != nil { payload = ["sources": [dictionary]] }
            else if dictionary["bookUrl"] != nil { payload = ["books": [dictionary]] }
            else { payload = dictionary }
        } else if let rows = object as? [[String: Any]], let first = rows.first {
            if first["bookSourceUrl"] != nil { payload = ["sources": rows] }
            else if first["bookUrl"] != nil { payload = ["books": rows] }
            else { payload = ["rules": rows] }
        } else { throw BackupStoreError.invalid("未找到可恢复的数据") }
        let result = try BackupStore.restore(payload, container: CoreDataStack.shared.persistentContainer)
        return (result["books"] ?? 0, result["sources"] ?? 0, result["rules"] ?? 0)
    }

    private func saveExportFile(data: Data, filename: String) throws {
        // 保存到 Documents 目录
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documents.appendingPathComponent(filename)
        
        try data.write(to: fileURL, options: .atomic)
        
        // 使用 UIActivityViewController 分享
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            activityVC.popoverPresentationController?.sourceView = rootVC.view
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 1, height: 1)
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - 导出数据视图
struct ExportDataView: View {
    @ObservedObject var viewModel: BackupRestoreViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var exportBooks = true
    @State private var exportSources = true
    @State private var exportRules = true
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("导出书籍", isOn: $exportBooks)
                    Toggle("导出书源", isOn: $exportSources)
                    Toggle("导出规则", isOn: $exportRules)
                }
                
                Section {
                    Button("导出") {
                        viewModel.backupAll()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("导出数据")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 导入数据视图
struct ImportDataView: View {
    @ObservedObject var viewModel: BackupRestoreViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("选择备份文件")
                    .font(.title2)
                
                Text("支持.json 格式的备份文件")
                    .foregroundColor(.secondary)
                
                Button("从文件选择") {
                    dismiss()
                    viewModel.restoreFromBackup()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("导入数据")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    BackupRestoreView()
}
