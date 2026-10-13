import SwiftUI
import UIKit

struct ReadViewWrapper: UIViewRepresentable {
    @ObservedObject var viewModel: ReaderViewModel
    let onTap: () -> Void
    
    func makeUIView(context: Context) -> ReadView {
        let readView = ReadView()
        readView.callBack = context.coordinator
        readView.pageFactory = TextPageFactory(dataSource: ReadBook.shared)
        updatePageDelegate(for: readView, coordinator: context.coordinator)
        return readView
    }
    
    func updateUIView(_ uiView: ReadView, context: Context) {
        updatePageDelegate(for: uiView, coordinator: context.coordinator)
        uiView.upContent()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func updatePageDelegate(for readView: ReadView, coordinator: Coordinator) {
        let pageAnimValue = viewModel.currentBook?.pageAnim ?? 0
        let animationType = PageAnimationType(rawValue: pageAnimValue) ?? .cover
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
