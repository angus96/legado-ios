import SwiftUI

struct ChapterCacheView: View {
    @StateObject private var model: ChapterCacheViewModel
    @State private var searchText = ""
    private enum InputField: Hashable { case search, start, end }
    @FocusState private var focusedInput: InputField?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(book: Book) {
        _model = StateObject(wrappedValue: ChapterCacheViewModel(book: book))
    }

    var body: some View {
        NavigationStack {
            List {
                if model.isLoading {
                    HStack { ProgressView(); Text("正在读取目录…") }
                }
                if !model.chapters.isEmpty {
                    selectionSection
                    progressSection
                    Section("章节") {
                        TextField("搜索章节", text: $searchText)
                            .focused($focusedInput, equals: .search)
                            .submitLabel(.done)
                            .onSubmit { focusedInput = nil }
                        ForEach(filteredChapters) { item in
                            Button {
                                focusedInput = nil
                                model.toggle(item)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: model.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(.accentColor)
                                    Text("\(item.number). \(item.title)")
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                    Spacer(minLength: 4)
                                    if item.isCached { Text("已缓存").font(.caption).foregroundColor(.secondary) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isCaching)
                            .accessibilityIdentifier("cache.chapter.\(item.number)")
                            .accessibilityValue(model.selectedIDs.contains(item.id) ? "已选择" : "未选择")
                        }
                    }
                }
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                        if model.chapters.isEmpty && !model.isLoading {
                            Button("重新读取目录") { Task { await model.loadChapters() } }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("缓存章节")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(model.isCaching ? "停止并关闭" : "关闭") {
                        model.stopCaching()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedInput = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(model.isCaching ? (model.isStopping ? "正在停止…" : "停止缓存") : "开始缓存（\(model.selectedIDs.count) 章）") {
                        focusedInput = nil
                        if model.isCaching { model.stopCaching() } else { model.startCaching() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isLoading || model.isStopping || model.selectedIDs.isEmpty)
                    .accessibilityIdentifier("cache.startStop")
                    Text("关闭此页或进入后台会停止缓存，已缓存章节会保留。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
        .task { await model.loadChapters() }
        .onDisappear { model.stopCaching() }
        .onChange(of: scenePhase) { if $0 == .background { model.stopCaching() } }
    }

    private var selectionSection: some View {
        Section {
            HStack {
                Text("已选 \(model.selectedIDs.count) / 共 \(model.chapters.count) 章")
                    .accessibilityIdentifier("cache.selection")
                Spacer()
                Button("全选") { model.selectedIDs = Set(model.chapters.map(\.id)) }
                    .accessibilityIdentifier("cache.selectAll")
                Button("清空") { model.selectedIDs = [] }
            }
            .buttonStyle(.borderless)
            HStack {
                TextField("起始序号", text: $model.startNumber)
                    .focused($focusedInput, equals: .start)
                    .accessibilityIdentifier("cache.rangeStart")
                Text("至").foregroundColor(.secondary)
                TextField("结束序号", text: $model.endNumber)
                    .focused($focusedInput, equals: .end)
                    .accessibilityIdentifier("cache.rangeEnd")
                Button("选取范围") {
                    focusedInput = nil
                    model.selectRange()
                }
                .buttonStyle(.borderless)
                .fixedSize()
            }
            .keyboardType(.numberPad)
        } header: {
            Text("缓存范围")
        } footer: {
            Text("默认全选。可按序号选择范围，也可逐章勾选；已有缓存会自动跳过。")
        }
        .disabled(model.isCaching)
    }

    @ViewBuilder
    private var progressSection: some View {
        if model.targetCount > 0 {
            Section("缓存进度") {
                Text(model.status).accessibilityIdentifier("cache.status")
                ProgressView(value: Double(model.completedCount), total: Double(model.targetCount))
                Text("已处理 \(model.completedCount) / \(model.targetCount) 章 · 新增 \(model.savedCount) · 已有 \(model.skippedCount) · 失败 \(model.failedCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("所选章节中，已有 \(model.cachedSelectionCount) 章可离线阅读")
                    .font(.caption)
                if !model.failures.isEmpty {
                    DisclosureGroup("失败详情（\(model.failedCount) 章）") {
                        ForEach(Array(model.failures.enumerated()), id: \.offset) { _, message in
                            Text(message).font(.caption).foregroundColor(.red)
                        }
                        Text("重新开始会跳过已有缓存，重试未完成的章节。")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var filteredChapters: [CacheChapterItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return keyword.isEmpty ? model.chapters : model.chapters.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) || String($0.number) == keyword
        }
    }
}
