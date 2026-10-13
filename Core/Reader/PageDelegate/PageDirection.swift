import UIKit

/// 页面方向枚举
/// 一比一移植自 Android Legado PageDirection
enum PageDirection: Int {
    case none = 0
    case next = 1
    case prev = 2
}

/// 页面视图协议
/// 一比一移植自 Android Legado PageView 功能
protocol PageViewProtocol: AnyObject {
    var width: CGFloat { get }
    var height: CGFloat { get }
    var textPage: TextPage? { get }
    func resetPageOffset()
    func scroll(_ offset: Int)
    func screenshot() -> UIImage?
    func onClick(_ x: CGFloat, _ y: CGFloat) -> Bool
    func longPress(_ x: CGFloat, _ y: CGFloat, callback: (TextPos) -> Void)
    func cancelSelect(_ clearSearchResult: Bool)
    func selectStartMoveIndex(_ pos: TextPos)
    func selectEndMoveIndex(_ pos: TextPos)
    func selectEndMove(x: CGFloat, y: CGFloat)
    func relativePage(_ pos: Int) -> TextPage
    func getLine(_ index: Int) -> TextLine
}

/// 阅读视图协议
/// 一比一移植自 Android Legado ReadView 功能
@MainActor
protocol ReadViewProtocol: AnyObject {
    var width: CGFloat { get }
    var height: CGFloat { get }
    var startX: CGFloat { get set }
    var startY: CGFloat { get set }
    var lastX: CGFloat { get set }
    var lastY: CGFloat { get set }
    var touchX: CGFloat { get set }
    var touchY: CGFloat { get set }
    var defaultAnimationSpeed: Int { get }
    var pageSlopSquare2: Int { get }
    var isAbortAnim: Bool { get set }
    var pageFactory: TextPageFactory? { get }
    
    var prevPage: PageViewProtocol { get }
    var curPage: PageViewProtocol { get }
    var nextPage: PageViewProtocol { get }
    
    func invalidate()
    func setTouchPoint(_ x: CGFloat, _ y: CGFloat, anim: Bool)
    func setStartPoint(_ x: CGFloat, _ y: CGFloat, anim: Bool)
    func fillPage(_ direction: PageDirection)
    func onScrollAnimStart()
    func onScrollAnimStop()
    func getCurVisiblePage() -> TextPage
    func isLongScreenShot() -> Bool
    
    var callBack: ReadViewCallBack? { get }
}

/// Canvas 记录器协议
/// 一比一移植自 Android Legado CanvasRecorder
protocol CanvasRecorderProtocol {
    var width: CGFloat { get }
    var height: CGFloat { get }
    func draw(_ context: CGContext)
    func recycle()
}
