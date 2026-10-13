import SwiftUI
import UIKit

struct ReadViewWrapper: UIViewRepresentable {
    @ObservedObject var viewModel: ReaderViewModel
    let onTap: () -> Void
    @AppStorage("pageAnimation") private var pageAnimationRaw = PageAnimationType.cover.rawValue
    
    func makeUIView(context: Context) -> ReadView {
        let readView = ReadView()
        readView.callBack = context.coordinator
        readView.pageFactory = TextPageFactory(dataSource: ReadBook.shared)
        readView.onSizeChange = { [weak viewModel] size in
            viewModel?.configureTextLayout(size: size)
        }
        viewModel.configureTextLayout(size: UIScreen.main.bounds.size)
        updatePageDelegate(for: readView, coordinator: context.coordinator)
        return readView
    }
    
    func updateUIView(_ uiView: ReadView, context: Context) {
        let background = UIColor(viewModel.backgroundColor)
        uiView.backgroundColor = background
        for page in [uiView.curPage, uiView.prevPage, uiView.nextPage] {
            (page as? UIView)?.backgroundColor = background
        }
        viewModel.configureTextLayout(size: uiView.bounds.size)
        updatePageDelegate(for: uiView, coordinator: context.coordinator)
        uiView.upContent()
    }
    
    static func dismantleUIView(_ uiView: ReadView, coordinator: Coordinator) {
        uiView.dispose()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updatePageDelegate(for readView: ReadView, coordinator: Coordinator) {
        let animationType = PageAnimationType(rawValue: pageAnimationRaw) ?? .cover
        if coordinator.animationType == animationType, readView.pageDelegate != nil { return }
        coordinator.animationType = animationType
        readView.pageDelegate?.onDestroy()
        
        switch animationType {
        case .cover:
            readView.pageDelegate = CoverPageDelegate(readView: readView)
        case .slide:
            readView.pageDelegate = SlidePageDelegate(readView: readView)
        case .simulation:
            readView.pageDelegate = SimulationPageDelegate(readView: readView)
        case .scroll:
            readView.pageDelegate = ScrollPageDelegate(readView: readView)
        case .none:
            readView.pageDelegate = NoAnimPageDelegate(readView: readView)
        }
        readView.pageDelegate?.setViewSize(width: readView.bounds.width, height: readView.bounds.height)
    }
    
    class Coordinator: NSObject, ReadViewCallBack {
        let parent: ReadViewWrapper
        var animationType: PageAnimationType?
        
        init(_ parent: ReadViewWrapper) {
            self.parent = parent
        }
        
        func showActionMenu() {
            parent.onTap()
        }
        
        func hideActionMenu() {
            parent.onTap()
        }
        
        func addBookmark() {}
        func showTextActionMenu() {}
        func screenOffTimerStart() {}
        func upSystemUiVisibility() {}
        func autoPageStop() {}
        
        func upContent() {}
        func upMenuView() {}
        func upPageAnim() {}
    }
}
