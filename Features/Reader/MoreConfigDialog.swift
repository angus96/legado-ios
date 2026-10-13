//
//  MoreConfigDialog.swift
//  Legado-iOS
//
//  对应 Android dialog_more_config.xml
//  "设置"按钮打开：屏幕方向/超时/全屏/TTS/点击翻页/音量翻页/手势冲突等开关集合
//

import SwiftUI

struct MoreConfigDialog: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var isPresented: Bool

    let onClickAction: () -> Void
    let onPageKey: () -> Void
    let onPadding: () -> Void
    let onTipConfig: () -> Void

    // 屏幕/显示
    @AppStorage("config.hideStatusBar") private var hideStatusBar: Bool = true
    @AppStorage("config.hideNavigationBar") private var hideNavigationBar: Bool = true
    @AppStorage("config.keepScreenOn") private var keepScreenOn: Bool = true
    @AppStorage("config.screenOrientation") private var screenOrientation: Int = 0 // 0自动 1竖 2横

    // 翻页
    @AppStorage("config.clickTurnPage") private var clickTurnPage: Bool = true
    @AppStorage("config.clickAllNext") private var clickAllNext: Bool = false
    @AppStorage("config.volumeKeyPage") private var volumeKeyPage: Bool = false
    @AppStorage("config.volumeKeyPageReverse") private var volumeKeyPageReverse: Bool = false

    // 页面
    @AppStorage("config.hideHeader") private var hideHeader: Bool = false
    @AppStorage("config.hideFooter") private var hideFooter: Bool = false
    @AppStorage("config.showBrightnessAuto") private var showBrightnessAuto: Bool = false
    @AppStorage("config.readBodyToLh") private var readBodyToLh: Bool = false

    // 手势
    @AppStorage("config.disableScrollClick") private var disableScrollClick: Bool = false

    // TTS
    @AppStorage("tts.autoAutoPage") private var autoPage: Bool = false

    // 替换规则
    @AppStorage("reader.useReplace") private var useReplace: Bool = true
    @AppStorage("reader.delRubyTag") private var delRubyTag: Bool = false
    @AppStorage("reader.delHTag") private var delHTag: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section("屏幕") {
                    Toggle("隐藏状态栏", isOn: $hideStatusBar)
                    Toggle("隐藏底部导航", isOn: $hideNavigationBar)
                    Toggle("保持屏幕常亮", isOn: $keepScreenOn)
                    Picker("屏幕方向", selection: $screenOrientation) {
                        Text("自动").tag(0)
                        Text("竖屏").tag(1)
                        Text("横屏").tag(2)
                    }
                }

                Section("翻页") {
                    Toggle("点击屏幕翻页", isOn: $clickTurnPage)
                    Toggle("点击翻页只向下", isOn: $clickAllNext)
                    Toggle("音量键翻页", isOn: $volumeKeyPage)
                    Toggle("音量键翻页反向", isOn: $volumeKeyPageReverse)
                        .disabled(!volumeKeyPage)

                    Button(action: onClickAction) {
                        HStack {
                            Text("点击区域")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button(action: onPageKey) {
                        HStack {
                            Text("按键设置")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }

                Section("页面") {
                    Toggle("隐藏页眉", isOn: $hideHeader)
                    Toggle("隐藏页脚", isOn: $hideFooter)
                    Toggle("显示自动亮度按钮", isOn: $showBrightnessAuto)
                    Toggle("正文对齐到行高", isOn: $readBodyToLh)

                    Button(action: onPadding) {
                        HStack {
                            Text("页面边距")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button(action: onTipConfig) {
                        HStack {
                            Text("页眉页脚信息")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }

                Section("交互") {
                    Toggle("禁用滚动模式点击翻页", isOn: $disableScrollClick)
                }

                Section("朗读") {
                    Toggle("朗读时自动翻页", isOn: $autoPage)
                }

                Section("内容处理") {
                    Toggle("使用替换净化", isOn: $useReplace)
                    Toggle("去除Ruby注音", isOn: $delRubyTag)
                    Toggle("去除H标题", isOn: $delHTag)
                }
            }
            .onChange(of: useReplace) { _ in
                viewModel.useReplaceRule = useReplace
                ReadBook.shared.loadContent(resetPageOffset: false, forceRebuild: true)
            }
            .navigationTitle("更多设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - 二级：点击区域配置（对应 dialog_click_action_config.xml）

struct ClickActionConfigDialog: View {
    @Binding var isPresented: Bool
    @AppStorage("click.topLeft") private var topLeft: Int = 0
    @AppStorage("click.topCenter") private var topCenter: Int = 0
    @AppStorage("click.topRight") private var topRight: Int = 0
    @AppStorage("click.middleLeft") private var middleLeft: Int = 1 // prev
    @AppStorage("click.middleCenter") private var middleCenter: Int = 2 // menu
    @AppStorage("click.middleRight") private var middleRight: Int = 3 // next
    @AppStorage("click.bottomLeft") private var bottomLeft: Int = 0
    @AppStorage("click.bottomCenter") private var bottomCenter: Int = 0
    @AppStorage("click.bottomRight") private var bottomRight: Int = 0

    private let actions: [(Int, String)] = [
        (0, "无"), (1, "上一页"), (2, "显示菜单"), (3, "下一页"),
        (4, "下一章"), (5, "上一章"), (6, "朗读"), (7, "搜索")
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("上部") {
                    picker("左上", $topLeft)
                    picker("中上", $topCenter)
                    picker("右上", $topRight)
                }
                Section("中部") {
                    picker("左中", $middleLeft)
                    picker("中心", $middleCenter)
                    picker("右中", $middleRight)
                }
                Section("下部") {
                    picker("左下", $bottomLeft)
                    picker("中下", $bottomCenter)
                    picker("右下", $bottomRight)
                }
            }
            .navigationTitle("点击区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isPresented = false }
                }
            }
        }
    }

    private func picker(_ title: String, _ value: Binding<Int>) -> some View {
        Picker(title, selection: value) {
            ForEach(actions, id: \.0) { action in
                Text(action.1).tag(action.0)
            }
        }
    }
}

// MARK: - 二级：按键配置（对应 dialog_page_key.xml）

struct PageKeyDialog: View {
    @Binding var isPresented: Bool
    @AppStorage("config.volumeKeyPage") private var volumeKeyPage: Bool = false
    @AppStorage("config.volumeKeyPageReverse") private var volumeKeyPageReverse: Bool = false
    @AppStorage("config.volumeKeyPageWhenRead") private var volumeKeyPageWhenRead: Bool = true

    var body: some View {
        NavigationView {
            Form {
                Section("音量键") {
                    Toggle("音量键翻页", isOn: $volumeKeyPage)
                    Toggle("反向（上键下一页）", isOn: $volumeKeyPageReverse)
                        .disabled(!volumeKeyPage)
                    Toggle("仅阅读界面响应", isOn: $volumeKeyPageWhenRead)
                        .disabled(!volumeKeyPage)
                }
            }
            .navigationTitle("按键设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { isPresented = false }
                }
            }
        }
    }
}
