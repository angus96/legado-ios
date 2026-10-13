import SwiftUI
import CoreData

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ReaderViewModel()
    @StateObject private var ttsManager = TTSManager()
    @StateObject private var autoPageTurnManager = AutoPageTurnManager()
    @StateObject private var readingEnhancementManager = ReadingEnhancementManager()

    @State private var showingSettings = false
    @State private var showingStyleConfig = false
    @State private var showingChapterList = false
    @State private var showingTTSControls = false
    @State private var showingAutoPageTurn = false
    @State private var showingBookmarks = false
    @State private var showingChangeSource = false
    @State private var showingEffectiveReplaces = false
    @State private var showingSearchInBook = false
    @State private var showingClickAction = false
    @State private var showingPageKey = false
    @State private var showingPadding = false
    @State private var showingTip = false
    @State private var showUI = false
    @State private var isNightMode = false

    let bookId: UUID

    private var book: Book? {
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                viewModel.backgroundColor.ignoresSafeArea()

                if let currentBook = book, currentBook.isHardcover {
                    EPUBWebPagedView(viewModel: viewModel) {
                        autoPageTurnManager.handleTouch()
                        withAnimation { showUI.toggle() }
                    }
                } else {
                    ReadViewWrapper(viewModel: viewModel) {
                        autoPageTurnManager.handleTouch()
                        withAnimation { showUI.toggle() }
                    }
                    .accessibilityIdentifier("reader.canvas")
                }

                if showUI {
                    ReadMenu(
                        viewModel: viewModel,
                        isShown: $showUI,
                        book: book,
                        isNightMode: isNightMode,
                        isAutoPageActive: autoPageTurnManager.isActive,
                        onBack: {
                            viewModel.saveProgress()
                            dismiss()
                        },
                        onChangeSource: { showingChangeSource = true },
                        onChapterList: { showingChapterList = true },
                        onReadAloud: { showingTTSControls = true },
                        onStyleConfig: { showingStyleConfig = true },
                        onSettings: { showingSettings = true },
                        onSearch: { showingSearchInBook = true },
                        onAutoPage: { showingAutoPageTurn = true },
                        onReplaceRule: { showingEffectiveReplaces = true },
                        onToggleNight: toggleNightMode,
                        onPrevChapter: { Task { await viewModel.prevChapter() } },
                        onNextChapter: { Task { await viewModel.nextChapter() } },
                        onJumpChapter: { viewModel.jumpToChapter($0) }
                    )
                }

                if showingChapterList, let currentBook = book {
                    ChapterDrawer(
                        isPresented: $showingChapterList,
                        viewModel: viewModel,
                        book: currentBook,
                        onChangeSource: { showingChangeSource = true },
                        onSearchInBook: { showingSearchInBook = true }
                    )
                    .zIndex(10)
                }

                AutoPageTurnOverlay(manager: autoPageTurnManager)

                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                if let error = viewModel.errorMessage {
                    VStack {
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                    }
                    .padding()
                }
            }
            .onAppear {
                viewModel.loadBook(byId: bookId)
                autoPageTurnManager.onTurnPage = { viewModel.turnToNextPage() }
                autoPageTurnManager.onChapterComplete = {
                    Task { @MainActor in await viewModel.nextChapter() }
                }
                readingEnhancementManager.onNightModeChanged = { isNight in
                    viewModel.applyTheme(isNight ? .dark : .light)
                }
                readingEnhancementManager.startReadingSession()
            }
            .onDisappear {
                viewModel.saveProgress()
                viewModel.cleanup()
                ttsManager.stop()
                autoPageTurnManager.stop()
                readingEnhancementManager.endReadingSession()
            }
            .onChange(of: viewModel.currentPageIndex) { _ in autoPageTurnManager.reset() }
            .alert("阅读提醒", isPresented: Binding(
                get: { readingEnhancementManager.showReminder },
                set: { if !$0 { readingEnhancementManager.dismissReminder() } }
            )) {
                Button("知道了") { readingEnhancementManager.dismissReminder() }
            } message: {
                Text("阅读一段时间了，休息一下眼睛。")
            }
            .sheet(isPresented: $showingSettings) {
                MoreConfigDialog(
                    viewModel: viewModel,
                    isPresented: $showingSettings,
                    onClickAction: {
                        showingSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingClickAction = true }
                    },
                    onPageKey: {
                        showingSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingPageKey = true }
                    },
                    onPadding: {
                        showingSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingPadding = true }
                    },
                    onTipConfig: {
                        showingSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingTip = true }
                    }
                )
            }
            .sheet(isPresented: $showingStyleConfig) {
                if #available(iOS 16.0, *) {
                    ReadStyleDialog(viewModel: viewModel, isPresented: $showingStyleConfig)
                        .presentationDetents([.fraction(0.7), .large])
                        .presentationDragIndicator(.visible)
                } else {
                    ReadStyleDialog(viewModel: viewModel, isPresented: $showingStyleConfig)
                }
            }
            .sheet(isPresented: $showingChangeSource) {
                if let book = book {
                    ChangeSourceSheet(isPresented: $showingChangeSource, book: book) {
                        viewModel.loadBook(byId: bookId)
                    }
                }
            }
            .sheet(isPresented: $showingBookmarks) {
                if let book = book { BookmarkSheet(viewModel: viewModel, book: book) }
            }
            .sheet(isPresented: $showingTTSControls) {
                if #available(iOS 16.0, *) {
                    ReadAloudDialog(
                        ttsManager: ttsManager,
                        viewModel: viewModel,
                        isPresented: $showingTTSControls,
                        onChapterList: {
                            showingTTSControls = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingChapterList = true }
                        },
                        onMainMenu: { showingTTSControls = false },
                        onToBackstage: { showingTTSControls = false },
                        onSettings: {
                            showingTTSControls = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingSettings = true }
                        }
                    )
                    .presentationDetents([.fraction(0.5), .medium])
                    .presentationDragIndicator(.visible)
                } else {
                    ReadAloudDialog(
                        ttsManager: ttsManager,
                        viewModel: viewModel,
                        isPresented: $showingTTSControls,
                        onChapterList: { showingTTSControls = false },
                        onMainMenu: { showingTTSControls = false },
                        onToBackstage: { showingTTSControls = false },
                        onSettings: { showingTTSControls = false }
                    )
                }
            }
            .sheet(isPresented: $showingAutoPageTurn) {
                if #available(iOS 16.0, *) {
                    AutoReadDialog(
                        manager: autoPageTurnManager,
                        isPresented: $showingAutoPageTurn,
                        onChapterList: {
                            showingAutoPageTurn = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingChapterList = true }
                        },
                        onMainMenu: { showingAutoPageTurn = false },
                        onSettings: {
                            showingAutoPageTurn = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showingSettings = true }
                        }
                    )
                    .presentationDetents([.fraction(0.3), .medium])
                    .presentationDragIndicator(.visible)
                } else {
                    AutoReadDialog(
                        manager: autoPageTurnManager,
                        isPresented: $showingAutoPageTurn,
                        onChapterList: { showingAutoPageTurn = false },
                        onMainMenu: { showingAutoPageTurn = false },
                        onSettings: { showingAutoPageTurn = false }
                    )
                }
            }
            .sheet(isPresented: $showingEffectiveReplaces) {
                ReplaceRuleView()
            }
            .sheet(isPresented: $showingSearchInBook) {
                if let book = book {
                    SearchInBookView(book: book)
                }
            }
            .sheet(isPresented: $showingClickAction) {
                ClickActionConfigDialog(isPresented: $showingClickAction)
            }
            .sheet(isPresented: $showingPageKey) {
                PageKeyDialog(isPresented: $showingPageKey)
            }
            .sheet(isPresented: $showingPadding) {
                PaddingConfigDialog(isPresented: $showingPadding)
            }
            .sheet(isPresented: $showingTip) {
                TipConfigDialog(isPresented: $showingTip)
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .statusBar(hidden: !showUI)
    }

    private func toggleNightMode() {
        isNightMode = viewModel.theme != .dark
        viewModel.applyTheme(isNightMode ? .dark : .light)
    }
}

#Preview { Text("ReaderView Preview") }
