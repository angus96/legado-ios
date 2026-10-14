import UIKit

/// 翻页代理基类
/// 一比一移植自 Android Legado PageDelegate.kt (208行)
/// 原版路径: app/src/main/java/io/legado/app/ui/book/read/page/delegate/PageDelegate.kt
@MainActor
class PageDelegate {
    
    weak var readView: ReadViewProtocol?
    
    var viewWidth: CGFloat = 0
    var viewHeight: CGFloat = 0
    
    var isMoved: Bool = false
    var noNext: Bool = true
    var mDirection: PageDirection = .none
    var isCancel: Bool = false
    var isRunning: Bool = false
    var isStarted: Bool = false
    var drawsInLayer: Bool { false }

    func onContentUpdated() {}
    
    private var selectedOnDown: Bool = false
    private var displayLink: CADisplayLink?
    private var scrollerStartX: CGFloat = 0
    private var scrollerStartY: CGFloat = 0
    private var scrollerDx: CGFloat = 0
    private var scrollerDy: CGFloat = 0
    private var scrollerDuration: CGFloat = 0
    private var scrollerStartTime: CFTimeInterval = 0
    private var scrollerVelocityX: CGFloat = 0
    private var scrollerVelocityY: CGFloat = 0
    private var isFling: Bool = false
    private var flingMinX: CGFloat = 0
    private var flingMaxX: CGFloat = 0
    private var flingMinY: CGFloat = 0
    private var flingMaxY: CGFloat = 0
    
    init(readView: ReadViewProtocol) {
        self.readView = readView
        readView.curPage.resetPageOffset()
    }
    
    func setViewSize(width: CGFloat, height: CGFloat) {
        self.viewWidth = width
        self.viewHeight = height
    }
    
    func fling(startX: Int, startY: Int, velocityX: Int, velocityY: Int,
               minX: Int, maxX: Int, minY: Int, maxY: Int) {
        scrollerStartX = CGFloat(startX)
        scrollerStartY = CGFloat(startY)
        scrollerVelocityX = CGFloat(velocityX)
        scrollerVelocityY = CGFloat(velocityY)
        flingMinX = CGFloat(minX)
        flingMaxX = CGFloat(maxX)
        flingMinY = CGFloat(minY)
        flingMaxY = CGFloat(maxY)
        isFling = true
        isRunning = true
        isStarted = true
        scrollerStartTime = CACurrentMediaTime()
        startDisplayLink()
        readView?.invalidate()
    }
    
    func startScroll(startX: Int, startY: Int, dx: Int, dy: Int, animationSpeed: Int) {
        guard viewWidth > 0, viewHeight > 0 else { return }
        let duration: CGFloat
        if dx != 0 {
            duration = CGFloat(animationSpeed * abs(dx)) / viewWidth
        } else {
            duration = CGFloat(animationSpeed * abs(dy)) / viewHeight
        }
        
        scrollerStartX = CGFloat(startX)
        scrollerStartY = CGFloat(startY)
        scrollerDx = CGFloat(dx)
        scrollerDy = CGFloat(dy)
        scrollerDuration = max(0.001, duration / 1000.0)
        scrollerStartTime = CACurrentMediaTime()
        isFling = false
        isRunning = true
        isStarted = true
        startDisplayLink()
        readView?.invalidate()
    }
    
    func stopScroll() {
        isStarted = false
        stopDisplayLink()
        DispatchQueue.main.async { [weak self] in
            self?.isMoved = false
            self?.isRunning = false
            self?.readView?.invalidate()
        }
    }
    
    func computeScroll(at timestamp: CFTimeInterval = CACurrentMediaTime()) {
        if computeScrollOffset(at: timestamp) {
            readView?.setTouchPoint(scrollerCurrX, scrollerCurrY, anim: false)
        } else if isStarted {
            readView?.setTouchPoint(scrollerCurrX, scrollerCurrY, anim: false)
            onAnimStop()
            stopScroll()
        }
    }
    
    private var scrollerCurrX: CGFloat = 0
    private var scrollerCurrY: CGFloat = 0
    
    private func computeScrollOffset(at timestamp: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        let elapsed = max(0, timestamp - scrollerStartTime)
        
        if isFling {
            let deceleration: CGFloat = 5000
            // 最后一帧不能越过停止时刻，否则位移会倒退。
            let tx = min(elapsed, abs(scrollerVelocityX) / deceleration)
            let ty = min(elapsed, abs(scrollerVelocityY) / deceleration)
            let x = scrollerStartX + scrollerVelocityX * tx - 0.5 * (scrollerVelocityX > 0 ? deceleration : -deceleration) * tx * tx
            let y = scrollerStartY + scrollerVelocityY * ty - 0.5 * (scrollerVelocityY > 0 ? deceleration : -deceleration) * ty * ty
            
            scrollerCurrX = min(flingMaxX, max(flingMinX, x))
            scrollerCurrY = min(flingMaxY, max(flingMinY, y))
            
            let velocityX = scrollerVelocityX - (scrollerVelocityX > 0 ? deceleration : -deceleration) * elapsed
            let velocityY = scrollerVelocityY - (scrollerVelocityY > 0 ? deceleration : -deceleration) * elapsed
            
            return (velocityX * scrollerVelocityX > 0) || (velocityY * scrollerVelocityY > 0)
        } else {
            let progress = min(1.0, elapsed / scrollerDuration)
            let t = easeOutQuad(progress)
            
            scrollerCurrX = scrollerStartX + scrollerDx * t
            scrollerCurrY = scrollerStartY + scrollerDy * t
            
            return progress < 1.0
        }
    }
    
    private func easeOutQuad(_ t: CGFloat) -> CGFloat {
        return t * (2 - t)
    }
    
    var isScrollerFinished: Bool {
        return !computeScrollOffset()
    }
    
    func abortScrollerAnimation() {
        stopDisplayLink()
    }
    
    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        let maximumFPS = Float((readView as? UIView)?.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximumFPS),
                                                               maximum: maximumFPS, preferred: maximumFPS)
        displayLink?.add(to: .main, forMode: .common)
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func displayLinkFired() {
        computeScroll(at: displayLink?.targetTimestamp ?? CACurrentMediaTime())
        readView?.invalidate()
    }
    
    func onScroll() {}
    
    func abortAnim() {
        fatalError("Must override abortAnim")
    }
    
    func onAnimStart(animationSpeed: Int) {
        fatalError("Must override onAnimStart")
    }
    
    func onDraw(_ context: CGContext) {
        fatalError("Must override onDraw")
    }
    
    func onAnimStop() {
        fatalError("Must override onAnimStop")
    }
    
    func nextPageByAnim(animationSpeed: Int) {
        fatalError("Must override nextPageByAnim")
    }
    
    func prevPageByAnim(animationSpeed: Int) {
        fatalError("Must override prevPageByAnim")
    }
    
    func keyTurnPage(direction: PageDirection) {
        if isRunning { return }
        switch direction {
        case .next:
            nextPageByAnim(animationSpeed: 100)
        case .prev:
            prevPageByAnim(animationSpeed: 100)
        case .none:
            return
        }
    }
    
    func setDirection(_ direction: PageDirection) {
        mDirection = direction
    }
    
    func onTouch(event: UITouch, view: UIView) {
        fatalError("Must override onTouch")
    }
    
    func onDown() {
        isMoved = false
        noNext = false
        isRunning = false
        isCancel = false
        setDirection(.none)
    }
    
    func hasPrev() -> Bool {
        guard let hasPrev = readView?.pageFactory?.hasPrev() else { return false }
        if !hasPrev {
            Toast.show("已经是第一页了")
        }
        return hasPrev
    }
    
    func hasNext() -> Bool {
        guard let hasNext = readView?.pageFactory?.hasNext() else { return false }
        if !hasNext {
            readView?.callBack?.autoPageStop()
            Toast.show("已经是最后一页了")
        }
        return hasNext
    }
    
    func postInvalidate() {
        if isStarted && isRunning {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isStarted && self.isRunning else { return }
                if self is HorizontalPageDelegate {
                    self.setBitmap()
                }
                self.readView?.invalidate()
            }
        }
    }
    
    func onDestroy() {
        stopDisplayLink()
    }
    
    // MARK: - 访问器
    var startX: CGFloat { readView?.startX ?? 0 }
    var startY: CGFloat { readView?.startY ?? 0 }
    var lastX: CGFloat { readView?.lastX ?? 0 }
    var lastY: CGFloat { readView?.lastY ?? 0 }
    var touchX: CGFloat { readView?.touchX ?? 0 }
    var touchY: CGFloat { readView?.touchY ?? 0 }
    var prevPage: PageViewProtocol { readView?.prevPage ?? EmptyPageView() }
    var curPage: PageViewProtocol { readView?.curPage ?? EmptyPageView() }
    var nextPage: PageViewProtocol { readView?.nextPage ?? EmptyPageView() }
    
    func setBitmap() {}
}

/// 空页面视图实现
private class EmptyPageView: PageViewProtocol {
    var width: CGFloat { 0 }
    var height: CGFloat { 0 }
    var textPage: TextPage? { nil }
    func resetPageOffset() {}
    func scroll(_ offset: Int) {}
    func screenshot() -> UIImage? { nil }
    func onClick(_ x: CGFloat, _ y: CGFloat) -> Bool { false }
    func longPress(_ x: CGFloat, _ y: CGFloat, callback: (TextPos) -> Void) {}
    func cancelSelect(_ clearSearchResult: Bool) {}
    func selectStartMoveIndex(_ pos: TextPos) {}
    func selectEndMoveIndex(_ pos: TextPos) {}
    func selectEndMove(x: CGFloat, y: CGFloat) {}
    func relativePage(_ pos: Int) -> TextPage { .empty }
    func getLine(_ index: Int) -> TextLine { .empty }
}
