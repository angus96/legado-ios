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
    
    @State private var incomingFile: IncomingFile?
    @State private var returnToBookshelf = false
    @State private var didOpenTestFile = false
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
            Group {
                if let file = incomingFile {
                    FileAssociationHandler(url: file.url, automaticallyImportText: true, onImported: {
                        hasCompletedWelcome = true
                        returnToBookshelf = true
                    }, onClose: { incomingFile = nil })
                    .id(file.id)
                } else if hasCompletedWelcome {
                    MainTabView(initialTab: returnToBookshelf ? 0 : nil).withRouter()
                } else {
                    WelcomeView()
                }
            }
            .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
            .onOpenURL(perform: handleOpenURL)
            .alert("不支持的文件类型", isPresented: $unsupportedFileError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("Legado 支持接收 TXT、EPUB 和 JSON 文件。")
            }
            .task {
                #if DEBUG
                guard !didOpenTestFile else { return }
                didOpenTestFile = true
                if let file = try? StabilityTestBootstrap.incomingTextFixture() { handleOpenURL(file) }
                #endif
            }
        }
    }

    private struct IncomingFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private func handleOpenURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let supportedExtensions = ["txt", "epub", "json"]
        
        if url.isFileURL && supportedExtensions.contains(ext) {
            incomingFile = IncomingFile(url: url)
        } else {
            unsupportedFileError = true
        }
    }
}
