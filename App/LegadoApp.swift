//
//  LegadoApp.swift
//  Legado-iOS
//
//  应用入口 - 包含欢迎流程
//

import SwiftUI
import CoreData

@main
@MainActor
struct LegadoApp: App {
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    
    @State private var importedFileURL: URL?
    @State private var showFileImport = false
    @State private var unsupportedFileError = false

    init() {
        #if DEBUG
        StabilityTestBootstrap.prepareIfRequested()
        #endif
        RSSRefreshManager.shared.registerBackgroundTaskIfNeeded()
        _ = BackgroundCacheService.shared
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedWelcome {
                MainTabView()
                    .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
                    .withRouter()
                    .onOpenURL { url in
                        handleOpenURL(url)
                    }
                    .sheet(isPresented: $showFileImport) {
                        if let url = importedFileURL {
                            FileAssociationHandler(url: url)
                        }
                    }
                    .alert("不支持的文件类型", isPresented: $unsupportedFileError) {
                        Button("确定", role: .cancel) { }
                    } message: {
                        Text("Legado 仅支持打开 TXT、EPUB 和 JSON 文件。")
                    }
            } else {
                WelcomeView()
                    .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
                    .onOpenURL { url in
                        // 欢迎页也处理，但等完成欢迎后再显示
                        handleOpenURL(url)
                    }
            }
        }
    }
    
    private func handleOpenURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let supportedExtensions = ["txt", "epub", "json"]
        
        if supportedExtensions.contains(ext) {
            importedFileURL = url
            showFileImport = true
        } else {
            unsupportedFileError = true
        }
    }
}
