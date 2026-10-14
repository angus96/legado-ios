import UIKit

/// 复用前后页面实现连续纵向滚动，跨页时同步阅读进度。
class ScrollPageDelegate: PageDelegate {
    private let pageLayers = CALayer()
    private let previousLayer = CALayer()
    private let currentLayer = CALayer()
    private let nextLayer = CALayer()
    override var drawsInLayer: Bool { true }
    private(set) var offset: CGFloat = 0
    private var previousTouchY: CGFloat = 0
    private var previousTime: TimeInterval = 0
    private var velocity: CGFloat = 0
    private var currentImage: UIImage?
    private var previousImage: UIImage?
    private var nextImage: UIImage?
    private struct Snapshot {
        let page: TextPage
        let image: UIImage
    }
    private struct Appearance: Equatable {
        let size: CGSize
        let font: UIFont
        let titleFont: UIFont
        let color: UIColor
        let background: UIColor
        let letterSpacing: CGFloat
    }
    private var snapshots: [ObjectIdentifier: Snapshot] = [:]
    private var appearance: Appearance?

    override init(readView: ReadViewProtocol) {
        super.init(readView: readView)
        pageLayers.addSublayer(previousLayer)
        pageLayers.addSublayer(currentLayer)
        pageLayers.addSublayer(nextLayer)
        (readView as? UIView)?.layer.addSublayer(pageLayers)
    }

    override func onContentUpdated() { setBitmap() }

    func invalidateImages() {
        currentImage = nil
        previousImage = nil
        nextImage = nil
        snapshots.removeAll()
    }

    override func setViewSize(width: CGFloat, height: CGFloat) {
        let changed = width != viewWidth || height != viewHeight
        if changed {
            abortAnim()
            offset = 0
            invalidateImages()
        }
        super.setViewSize(width: width, height: height)
        if changed { setBitmap() }
    }

    override func setBitmap() {
        guard viewWidth > 0, viewHeight > 0 else { return }
        let provider = ChapterProvider.shared
        let updated = Appearance(size: CGSize(width: viewWidth, height: viewHeight),
                                 font: provider.contentFont, titleFont: provider.titleFont,
                                 color: provider.textColor,
                                 background: (curPage as? UIView)?.backgroundColor ?? .white,
                                 letterSpacing: provider.letterSpacing)
        if appearance != updated {
            invalidateImages()
            appearance = updated
        }
        // 跨页后复用已有页面，只绘制新进入的相邻页。
        currentImage = image(for: curPage)
        previousImage = image(for: prevPage)
        nextImage = image(for: nextPage)
        let visible = Set([curPage, prevPage, nextPage].compactMap { $0.textPage }.map(ObjectIdentifier.init))
        snapshots = snapshots.filter { visible.contains($0.key) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previousLayer.frame = CGRect(x: 0, y: -viewHeight, width: viewWidth, height: viewHeight)
        currentLayer.frame = CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight)
        nextLayer.frame = CGRect(x: 0, y: viewHeight, width: viewWidth, height: viewHeight)
        previousLayer.contents = previousImage?.cgImage
        currentLayer.contents = currentImage?.cgImage
        nextLayer.contents = nextImage?.cgImage
        pageLayers.transform = CATransform3DMakeTranslation(0, offset, 0)
        CATransaction.commit()
    }

    private func image(for view: PageViewProtocol) -> UIImage? {
        guard let page = view.textPage else { return nil }
        let key = ObjectIdentifier(page)
        if let cached = snapshots[key] { return cached.image }
        guard let image = view.screenshot() else { return nil }
        snapshots[key] = Snapshot(page: page, image: image)
        return image
    }

    override func onDown() {
        super.onDown()
        isRunning = offset != 0
    }

    override func onTouch(event: UITouch, view: UIView) {
        let y = event.location(in: view).y
        let now = event.timestamp
        switch event.phase {
        case .began:
            abortAnim()
            previousTouchY = y
            previousTime = now
            velocity = 0
            setBitmap()
        case .moved:
            // ReadView 越过点击容差后才转发移动。以此刻为拖动起点，
            // 避免把被忽略的前 10 点位移一次性补到正文上。
            guard isMoved else {
                isMoved = true
                previousTouchY = y
                previousTime = now
                velocity = 0
                return
            }
            let delta = y - previousTouchY
            if now > previousTime { velocity = max(-2500, min(2500, delta / (now - previousTime))) }
            previousTouchY = y
            previousTime = now
            scroll(by: delta)
        case .ended:
            // 手指已经停住时不能沿用最后一次移动的速度再次滑动。
            if now - previousTime > 0.1 { velocity = 0 }
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
        // 每帧只移动已绘制图层，不再把两张整屏图片重新画进 UIView。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageLayers.transform = CATransform3DMakeTranslation(0, offset, 0)
        CATransaction.commit()
    }

    override func onDraw(_ context: CGContext) {
        // 滚动页面由 CALayer 合成，无需在 draw(_:) 中重绘。
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
        velocity = 0
        isMoved = false
        isRunning = offset != 0
        readView?.invalidate()
    }

    override func abortAnim() {
        let wasScrolling = isStarted
        stopScroll()
        readView?.onScrollAnimStop()
        readView?.isAbortAnim = wasScrolling
    }

    override func onDestroy() {
        super.onDestroy()
        readView?.onScrollAnimStop()
        pageLayers.removeFromSuperlayer()
        invalidateImages()
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
