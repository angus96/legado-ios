//
//  ReadStyleDialog.swift
//  Legado-iOS
//
//  对应 Android dialog_read_book_style.xml：阅读"界面"按钮弹出的底部样式配置
//  横向 6 按钮 + 字号/字间距/行间距/段间距 SeekBar + 5 翻页动画 + 主题横向列表
//

import SwiftUI

struct ReadStyleDialog: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var isPresented: Bool

    @AppStorage("pageAnimation") private var pageAnimationRaw: Int = PageAnimationType.cover.rawValue
    @AppStorage("textBold") private var textBold: Bool = false
    @AppStorage("chineseConvertMode") private var chineseConvertMode: Int = ChineseConvertMode.none.rawValue
    @AppStorage("paragraphIndentRaw") private var paragraphIndentRaw: Int = 2
    @AppStorage("readerBgColorIndex") private var bgColorIndex: Int = 0

    @State private var showingFontPicker = false
    @State private var showingPaddingConfig = false
    @State private var showingTipConfig = false

    private let themeList: [StyleTheme] = StyleTheme.presets

    var body: some View {
        VStack(spacing: 0) {
            grabHandle

            topActionRow
                .padding(.top, 16)

            Group {
                detailSeekBar(
                    title: "字号",
                    value: Binding(
                        get: { Double(viewModel.fontSize) },
                        set: { viewModel.fontSize = CGFloat($0) }
                    ),
                    range: 12...45,
                    step: 1,
                    valueFormatter: { "\(Int($0))" }
                )
                detailSeekBar(
                    title: "字间距",
                    value: Binding(
                        get: { Double(viewModel.letterSpacing) },
                        set: { viewModel.letterSpacing = CGFloat($0) }
                    ),
                    range: 0...10,
                    step: 0.1,
                    valueFormatter: { String(format: "%.1f", $0) }
                )
                detailSeekBar(
                    title: "行间距",
                    value: Binding(
                        get: { Double(viewModel.lineSpacing) },
                        set: { viewModel.lineSpacing = CGFloat($0) }
                    ),
                    range: 1...20,
                    step: 1,
                    valueFormatter: { "\(Int($0))" }
                )
                detailSeekBar(
                    title: "段间距",
                    value: Binding(
                        get: { Double(viewModel.paragraphSpacing) },
                        set: { viewModel.paragraphSpacing = CGFloat($0) }
                    ),
                    range: 0...20,
                    step: 1,
                    valueFormatter: { "\(Int($0))" }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)

            separator

            Text("翻页动画")
                .font(.caption)
                .opacity(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            pageAnimationGroup
                .padding(.horizontal, 11)

            separator

            Text("背景主题")
                .font(.caption)
                .opacity(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            themeRow
                .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        .onChange(of: textBold) { _ in viewModel.upPageAnim() }
        .onChange(of: paragraphIndentRaw) { _ in viewModel.upPageAnim() }
        .sheet(isPresented: $showingPaddingConfig) {
            PaddingConfigDialog(isPresented: $showingPaddingConfig)
                .presentationDetentsIfAvailable([.medium])
        }
        .sheet(isPresented: $showingTipConfig) {
            TipConfigDialog(isPresented: $showingTipConfig)
                .presentationDetentsIfAvailable([.medium])
        }
    }

    private var grabHandle: some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
    }

    // MARK: - Top 6 buttons (横向)

    private var topActionRow: some View {
        HStack(spacing: 0) {
            styleChipButton(title: textBold ? "粗体" : "常规") { textBold.toggle() }
            Spacer(minLength: 4)
            styleChipButton(title: "字体") { showingFontPicker = true }
            Spacer(minLength: 4)
            styleChipButton(title: indentTitle()) { cyclingIndent() }
            Spacer(minLength: 4)
            styleChipButton(title: chineseConvertTitle()) { cyclingChineseConvert() }
            Spacer(minLength: 4)
            styleChipButton(title: "边距") { showingPaddingConfig = true }
            Spacer(minLength: 4)
            styleChipButton(title: "信息") { showingTipConfig = true }
        }
        .padding(.horizontal, 16)
    }

    private func styleChipButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 44)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.secondarySystemBackground))
                )
                .foregroundColor(.primary)
        }
    }

    private func indentTitle() -> String {
        "缩进\(paragraphIndentRaw)"
    }

    private func cyclingIndent() {
        paragraphIndentRaw = (paragraphIndentRaw + 1) % 5
        if let next = ParagraphIndent(rawValue: paragraphIndentRaw) {
            ReadBookConfig.paragraphIndent = next
        }
    }

    private func chineseConvertTitle() -> String {
        ChineseConvertMode(rawValue: chineseConvertMode)?.title ?? "不转换"
    }

    private func cyclingChineseConvert() {
        chineseConvertMode = (chineseConvertMode + 1) % ChineseConvertMode.allCases.count
    }

    // MARK: - DetailSeekBar (仿 Android DetailSeekBar)

    private func detailSeekBar(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueFormatter: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: 56, alignment: .leading)

            Button {
                if value.wrappedValue - step >= range.lowerBound {
                    value.wrappedValue = (value.wrappedValue - step).rounded(toStep: step)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .foregroundColor(.primary)

            Slider(value: value, in: range, step: step)

            Button {
                if value.wrappedValue + step <= range.upperBound {
                    value.wrappedValue = (value.wrappedValue + step).rounded(toStep: step)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .foregroundColor(.primary)

            Text(valueFormatter(value.wrappedValue))
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 翻页动画 RadioGroup

    private var pageAnimationGroup: some View {
        HStack(spacing: 8) {
            ForEach(PageAnimationType.allCases, id: \.rawValue) { anim in
                Button {
                    pageAnimationRaw = anim.rawValue
                    viewModel.upPageAnim()
                } label: {
                    Text(anim.title)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    pageAnimationRaw == anim.rawValue
                                    ? Color.accentColor.opacity(0.2)
                                    : Color(.secondarySystemBackground)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    pageAnimationRaw == anim.rawValue
                                    ? Color.accentColor
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .foregroundColor(.primary)
                }
            }
        }
    }

    // MARK: - 主题横向列表

    private var themeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(themeList.enumerated()), id: \.offset) { index, theme in
                    Button {
                        bgColorIndex = index
                        viewModel.backgroundColor = theme.background
                        viewModel.textColor = theme.text
                    } label: {
                        VStack(spacing: 4) {
                            Text("文")
                                .font(.system(size: 22))
                                .foregroundColor(theme.text)
                                .frame(width: 56, height: 70)
                                .background(theme.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            bgColorIndex == index
                                            ? Color.accentColor
                                            : Color(.systemGray4),
                                            lineWidth: bgColorIndex == index ? 2 : 1
                                        )
                                )
                                .cornerRadius(6)
                            Text(theme.name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(height: 0.8)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

// MARK: - Style theme presets

struct StyleTheme: Identifiable {
    let id = UUID()
    let name: String
    let background: Color
    let text: Color

    static let presets: [StyleTheme] = [
        StyleTheme(name: "默认", background: .white, text: .black),
        StyleTheme(name: "护眼", background: Color(red: 1.0, green: 0.96, blue: 0.88), text: Color(red: 0.17, green: 0.15, blue: 0.12)),
        StyleTheme(name: "浅绿", background: Color(red: 0.85, green: 0.95, blue: 0.85), text: Color(red: 0.1, green: 0.2, blue: 0.1)),
        StyleTheme(name: "羊皮纸", background: Color(red: 0.96, green: 0.91, blue: 0.81), text: Color(red: 0.25, green: 0.17, blue: 0.1)),
        StyleTheme(name: "淡蓝", background: Color(red: 0.9, green: 0.95, blue: 1.0), text: Color(red: 0.1, green: 0.15, blue: 0.3)),
        StyleTheme(name: "夜间", background: Color(red: 0.12, green: 0.12, blue: 0.12), text: Color(red: 0.85, green: 0.85, blue: 0.85)),
        StyleTheme(name: "深灰", background: Color(red: 0.2, green: 0.2, blue: 0.2), text: Color(red: 0.9, green: 0.9, blue: 0.9))
    ]
}

// MARK: - Helpers

private extension Double {
    func rounded(toStep step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step).rounded() * step
    }
}

extension View {
    @ViewBuilder
    func presentationDetentsIfAvailable(_ detents: Set<PresentationDetent>) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents(detents)
        } else {
            self
        }
    }
}

// MARK: - Placeholders for secondary dialogs (A5 将替换)

struct PaddingConfigDialog: View {
    @Binding var isPresented: Bool
    @AppStorage("readerPaddingLeft") private var paddingLeft: Double = 16
    @AppStorage("readerPaddingTop") private var paddingTop: Double = 16
    @AppStorage("readerPaddingRight") private var paddingRight: Double = 16
    @AppStorage("readerPaddingBottom") private var paddingBottom: Double = 16

    var body: some View {
        NavigationView {
            Form {
                Section("页面边距") {
                    stepper("左边距", value: $paddingLeft)
                    stepper("上边距", value: $paddingTop)
                    stepper("右边距", value: $paddingRight)
                    stepper("下边距", value: $paddingBottom)
                }
            }
            .navigationTitle("边距设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isPresented = false }
                }
            }
        }
    }

    private func stepper(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue))")
                .foregroundColor(.secondary)
            Stepper("", value: value, in: 0...64, step: 2)
                .labelsHidden()
        }
    }
}

struct TipConfigDialog: View {
    @Binding var isPresented: Bool
    @AppStorage("showHeader") private var showHeader: Bool = true
    @AppStorage("showFooter") private var showFooter: Bool = true
    @AppStorage("headerContent") private var headerContent: String = "章节名"
    @AppStorage("footerContent") private var footerContent: String = "进度"

    var body: some View {
        NavigationView {
            Form {
                Section("页眉") {
                    Toggle("显示页眉", isOn: $showHeader)
                    if showHeader {
                        Picker("内容", selection: $headerContent) {
                            Text("章节名").tag("章节名")
                            Text("书名").tag("书名")
                            Text("书名+章节").tag("书名+章节")
                            Text("时间").tag("时间")
                        }
                    }
                }
                Section("页脚") {
                    Toggle("显示页脚", isOn: $showFooter)
                    if showFooter {
                        Picker("内容", selection: $footerContent) {
                            Text("进度").tag("进度")
                            Text("页码").tag("页码")
                            Text("时间").tag("时间")
                            Text("章节进度").tag("章节进度")
                        }
                    }
                }
            }
            .navigationTitle("信息栏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isPresented = false }
                }
            }
        }
    }
}
