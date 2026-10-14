//
//  ReadMenu.swift
//  Legado-iOS
//
//  对应 Android view_read_menu.xml：顶部 TitleBar + 左侧亮度条 + 底部 4 FAB + 章节进度 + 目录/朗读/界面/设置
//  作为 ReaderView 的点击菜单覆盖层
//

import SwiftUI

struct ReadMenu: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var isShown: Bool

    let book: Book?
    let isNightMode: Bool
    let isAutoPageActive: Bool

    let onBack: () -> Void
    let onChangeSource: () -> Void
    let onChapterList: () -> Void
    let onReadAloud: () -> Void
    let onStyleConfig: () -> Void
    let onSettings: () -> Void
    let onSearch: () -> Void
    let onAutoPage: () -> Void
    let onReplaceRule: () -> Void
    let onToggleNight: () -> Void
    let onPrevChapter: () -> Void
    let onNextChapter: () -> Void
    let onJumpChapter: (Int) -> Void

    @AppStorage("readerBrightness") private var savedBrightness: Double = 0.5
    @AppStorage("readerBrightnessAuto") private var isBrightnessAuto: Bool = false
    @AppStorage("readerBrightnessLeft") private var brightnessOnLeft: Bool = true

    @State private var brightness: Double = Double(UIScreen.main.brightness)

    private var primaryText: Color { viewModel.textColor }
    private var menuBgColor: Color { viewModel.backgroundColor }
    private var menuBgColorSemi: Color { viewModel.backgroundColor.opacity(0.85) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMenu() }

                VStack(spacing: 0) {
                    topTitleBar
                        .padding(.top, geo.safeAreaInsets.top)
                        .background(menuBgColor)
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(primaryText.opacity(0.15)),
                            alignment: .bottom
                        )
                        .transition(.move(edge: .top))

                    Spacer()

                    bottomSection
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                        .transition(.move(edge: .bottom))
                }
                .ignoresSafeArea(.container, edges: [.top, .bottom])

                brightnessRail
                    .frame(width: 40, height: geo.size.height * 0.45)
                    .position(
                        x: brightnessOnLeft ? 28 : geo.size.width - 28,
                        y: geo.size.height * 0.5
                    )
                    .transition(.opacity)
            }
        }
        .onAppear {
            brightness = Double(UIScreen.main.brightness)
        }
    }

    // MARK: - Top Title Bar (对应 TitleBar + title_bar_addition)

    private var topTitleBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(primaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("返回")
                .accessibilityIdentifier("reader.back")

                VStack(alignment: .leading, spacing: 2) {
                    Text(book?.name ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(primaryText)
                    Text(viewModel.currentChapter?.title ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(primaryText.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onChangeSource) {
                    Text(book?.originName ?? "书源")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: 120)
                        .background(Color.accentColor.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(2)
                }
                .accessibilityIdentifier("reader.changeSource")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Left Brightness Rail (对应 ll_brightness)

    private var brightnessRail: some View {
        VStack(spacing: 8) {
            Button {
                isBrightnessAuto.toggle()
                if isBrightnessAuto {
                    brightness = Double(UIScreen.main.brightness)
                }
            } label: {
                Image(systemName: isBrightnessAuto ? "a.circle.fill" : "sun.min")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }

            GeometryReader { g in
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(height: max(1, CGFloat(brightness) * g.size.height))
                        .offset(y: (g.size.height - CGFloat(brightness) * g.size.height) / 2)
                }
                .frame(width: 4)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let h = g.size.height
                            let y = max(0, min(h, h - v.location.y))
                            let value = Double(y / h)
                            brightness = value
                            if !isBrightnessAuto {
                                UIScreen.main.brightness = CGFloat(value)
                                savedBrightness = value
                            }
                        }
                )
            }
            .frame(width: 24)

            Button {
                brightnessOnLeft.toggle()
            } label: {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 10)
        .background(menuBgColor.opacity(0.7))
        .cornerRadius(5)
    }

    // MARK: - Bottom Section (FAB 行 + 章节控制 + 4 图文按钮)

    private var bottomSection: some View {
        VStack(spacing: 0) {
            floatingFabs
            bottomControlPanel
                .background(menuBgColor)
        }
    }

    private var floatingFabs: some View {
        HStack(spacing: 0) {
            Spacer()
            fabButton(icon: "magnifyingglass", action: onSearch)
            Spacer()
            fabButton(
                icon: isAutoPageActive ? "pause.fill" : "play.fill",
                action: onAutoPage
            )
            Spacer()
            fabButton(icon: "arrow.left.arrow.right", action: onReplaceRule)
            Spacer()
            fabButton(
                icon: isNightMode ? "sun.max.fill" : "moon.fill",
                action: onToggleNight
            )
            .accessibilityIdentifier("reader.theme")
            .accessibilityLabel("切换日夜主题")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func fabButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(primaryText)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(menuBgColor)
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                )
        }
    }

    private var bottomControlPanel: some View {
        VStack(spacing: 4) {
            chapterProgressRow
            mainActionRow
        }
        .padding(.vertical, 4)
    }

    // 上一章 - 进度条 - 下一章
    private var chapterProgressRow: some View {
        HStack(spacing: 10) {
            Button("上一章", action: onPrevChapter)
                .font(.system(size: 14))
                .foregroundColor(primaryText)
                .disabled(viewModel.currentChapterIndex <= 0)
                .opacity(viewModel.currentChapterIndex <= 0 ? 0.4 : 1)

            Slider(
                value: Binding(
                    get: { Double(viewModel.currentChapterIndex) },
                    set: { onJumpChapter(Int($0)) }
                ),
                in: 0...Double(max(1, viewModel.totalChapters - 1)),
                step: 1
            )
            .tint(primaryText.opacity(0.6))
            .frame(height: 25)

            Button("下一章", action: onNextChapter)
                .font(.system(size: 14))
                .foregroundColor(primaryText)
                .disabled(viewModel.currentChapterIndex >= viewModel.totalChapters - 1)
                .opacity(viewModel.currentChapterIndex >= viewModel.totalChapters - 1 ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    // 目录 / 朗读 / 界面 / 设置
    private var mainActionRow: some View {
        GeometryReader { geometry in
            let totalWeight: CGFloat = 8
            let buttonWidth: CGFloat = 60
            let totalButtonWidth = buttonWidth * 4
            let availableSpace = geometry.size.width - totalButtonWidth
            let weightUnit = availableSpace / totalWeight
            
            HStack(spacing: 0) {
                Spacer().frame(width: weightUnit * 1)
                mainActionButton(icon: "list.bullet", title: "目录", action: onChapterList)
                    .frame(width: buttonWidth)
                Spacer().frame(width: weightUnit * 2)
                mainActionButton(icon: "speaker.wave.2", title: "朗读", action: onReadAloud)
                    .frame(width: buttonWidth)
                Spacer().frame(width: weightUnit * 2)
                mainActionButton(icon: "textformat", title: "界面", action: onStyleConfig)
                    .frame(width: buttonWidth)
                Spacer().frame(width: weightUnit * 2)
                mainActionButton(icon: "gearshape", title: "设置", action: onSettings)
                    .frame(width: buttonWidth)
                Spacer().frame(width: weightUnit * 1)
            }
        }
        .frame(height: 44)
        .padding(.bottom, 7)
    }

    private func mainActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(width: 60)
            .foregroundColor(primaryText)
        }
    }

    private func dismissMenu() {
        withAnimation(.easeInOut(duration: 0.2)) { isShown = false }
    }
}
