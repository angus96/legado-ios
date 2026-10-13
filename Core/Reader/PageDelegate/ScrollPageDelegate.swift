import UIKit

/// 复用前后页面实现连续纵向滚动，跨页时同步阅读进度。
class ScrollPageDelegate: PageDelegate {
    private(set) var offset: CGFloat = 0
    private var previousTouchY: CGFloat = 0
    private var previousTime: TimeInterval = 0
    private var velocity: CGFloat = 0
    private var currentImage: UIImage?
    private var previousImage: UIImage?
    private var nextImage: UIImage?
    private weak var renderedPage: TextPage?

    override func setBitmap() {
        currentImage = curPage.screenshot()
        previousImage = prevPage.screenshot()
        nextImage = nextPage.screenshot()
        renderedPage = curPage.textPage
    }

    override func onDown() {
        super.onDown()
        isRunning = offset != 0
    }

    override func onTouch(event: UITouch, view: UIView) {
        let y = event.location(in: view).y
        let now = CACurrentMediaTime()
        switch event.phase {
        case .began:
            abortAnim()
            previousTouchY = y
            previousTime = now
            velocity = 0
            setBitmap()
        case .moved:
            let delta = y - previousTouchY
            if now > previousTime { velocity = max(-2500, min(2500, delta / (now - previousTime))) }
            previousTouchY = y
            previousTime = now
            isMoved = true
            scroll(by: delta)
        case .ended:
            readView?.setStartPoint(0, 0, anim: false)
            onAnimStart(animationSpeed: readView?.defaultAnimationSpeed ?? 300)
        case .cancelled:
            abortAnim()
        default: break
        }
    }

    func scroll(by delta: CGFloat) {
        guard viewHeight > 0, delta.isFinite else { return }
        offset += delta
        while offset <= -viewHeight {
            guard readView?.pageFactory?.hasNext() == true else { offset = 0; break }
            let before = curPage.textPage
            readView?.fillPage(.next)
            guard curPage.textPage !== before else { offset = 0; break }
            offset += viewHeight
            setBitmap()
        }
        while offset > 0 {
            guard readView?.pageFactory?.hasPrev() == true else { offset = 0; break }
            let before = curPage.textPage
            readView?.fillPage(.prev)
            guard curPage.textPage !== before else { offset = 0; break }
            offset -= viewHeight
            setBitmap()
        }
        if readView?.pageFactory?.hasNext() != true { offset = 0 }
        isRunning = offset != 0 || isStarted
        readView?.invalidate()
    }

    override func onDraw(_ context: CGContext) {
        if renderedPage !== curPage.textPage { setBitmap() }
        if currentImage == nil { setBitmap() }
        currentImage?.draw(in: CGRect(x: 0, y: offset, width: viewWidth, height: viewHeight))
        nextImage?.draw(in: CGRect(x: 0, y: offset + viewHeight, width: viewWidth, height: viewHeight))
        previousImage?.draw(in: CGRect(x: 0, y: offset - viewHeight, width: viewWidth, height: viewHeight))
    }

    override func onScroll() { scroll(by: touchY - lastY) }

    override func onAnimStart(animationSpeed: Int) {
        guard viewHeight > 0, abs(velocity) > 20 else { return }
        readView?.onScrollAnimStart()
        fling(startX: 0, startY: 0, velocityX: 0, velocityY: Int(velocity),
              minX: 0, maxX: 0, minY: -Int(viewHeight * 4), maxY: Int(viewHeight * 4))
    }

    override func onAnimStop() { readView?.onScrollAnimStop() }

    override func stopScroll() {
        isStarted = false
        abortScrollerAnimation()
        isMoved = false
        isRunning = offset != 0
        readView?.invalidate()
    }

    override func abortAnim() {
        stopScroll()
        readView?.onScrollAnimStop()
        readView?.isAbortAnim = false
    }

    override func nextPageByAnim(animationSpeed: Int) {
        guard hasNext(), viewHeight > 0 else { return }
        abortAnim()
        setBitmap()
        readView?.setStartPoint(0, 0, anim: false)
        startScroll(startX: 0, startY: 0, dx: 0, dy: -Int(viewHeight), animationSpeed: animationSpeed)
    }

    override func prevPageByAnim(animationSpeed: Int) {
        guard hasPrev(), viewHeight > 0 else { return }
        abortAnim()
        setBitmap()
        readView?.setStartPoint(0, 0, anim: false)
        startScroll(startX: 0, startY: 0, dx: 0, dy: Int(viewHeight), animationSpeed: animationSpeed)
    }
}
