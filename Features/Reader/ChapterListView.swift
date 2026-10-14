import SwiftUI
import CoreData

struct ChapterListView: View {
    @ObservedObject var viewModel: ReaderViewModel
    let book: Book
    var onSelectChapter: ((BookChapter) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .asc
    
    enum SortOrder {
        case asc, desc
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                chapterList
            }
            .navigationTitle("章节目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { sortOrder = sortOrder == .asc ? .desc : .asc }) {
                        Image(systemName: sortOrder == .asc ? "arrow.up" : "arrow.down")
                    }
                }
            }
            .task { await loadChapters() }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索章节", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var chapterList: some View {
        Group {
            if isLoading && chapters.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredChapters.isEmpty {
                Text("暂无章节")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredChapters, id: \.chapterId) { chapter in
                        Button(action: {
                            if let onSelectChapter { onSelectChapter(chapter) }
                            else { viewModel.jumpToChapter(Int(chapter.index)) }
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    if chapter.isVIP {
                                        Text("VIP")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                                Spacer()
                                
                                if chapter.index == book.durChapterIndex {
                                    Image(systemName: "book.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                }
                                
                                if chapter.isCached {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("toc.chapter.\(chapter.index)")
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private var filteredChapters: [BookChapter] {
        let sorted = sortOrder == .asc ? chapters : chapters.reversed()
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func loadChapters() async {
        isLoading = true
        defer { isLoading = false }
        
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<BookChapter> = BookChapter.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", book.bookId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BookChapter.index, ascending: true)]
        
        do {
            chapters = try (book.managedObjectContext ?? context).fetch(request)
        } catch {
            DebugLogger.shared.log("加载章节列表失败: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ChapterListView(viewModel: ReaderViewModel(), book: Book.create(in: CoreDataStack.shared.viewContext))
}
