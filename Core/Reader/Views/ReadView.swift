import UIKit

/// 阅读视图回调协议
/// 一比一移植自 Android Legado ReadView.CallBack
@MainActor
protocol ReadViewCallBack: ReadBookCallBack {
    func showActionMenu()
    func hideActionMenu()
    func addBookmark()
    func showTextActionMenu()
    func screenOffTimerStart()
    func upSystemUiVisibility()
    func autoPageStop()
}

/// 阅读视图
/// 一比一移植自 Android Legado ReadView.kt (758行)
/// 原版路径: app/src/main/java/io/legado/app/ui/book/read/page/ReadView.kt
class ReadView: UIView, ReadViewProtocol {
    
    weak var callBack: ReadViewCallBack?
    var pageFactory: TextPageFactory?
    var pageDelegate: PageDelegate?
    var onSizeChange: ((CGSize) -> Void)?
    
    var isScroll: Bool = false
    
    lazy var prevPage: PageViewProtocol = PageView()
    lazy var curPage: PageViewProtocol = PageView()
    lazy var nextPage: PageViewProtocol = PageView()
    
    let defaultAnimationSpeed = 300
    var width: CGFloat { bounds.width }
    var height: CGFloat { bounds.height }
    
    private var pressDown = false
    private var isMove = false
    
    var startX: CGFloat = 0
    var startY: CGFloat = 0
    var lastX: CGFloat = 0
    var lastY: CGFloat = 0
    var touchX: CGFloat = 0
    var touchY: CGFloat = 0
    
    var isAbortAnim = false
    
    private var longPressed = false
    private let longPressTimeout: TimeInterval = 0.6
    private var longPressTimer: Timer?
    
    var isTextSelected = false
    private var pressOnTextSelected = false
    
    private var slopSquare: CGFloat = 10
    var pageSlopSquare2: Int = 100
    
    private var tlRect = CGRect.zero
    private var tcRect = CGRect.zero
    private var trRect = CGRect.zero
    private var mlRect = CGRect.zero
    private var mcRect = CGRect.zero
    private var mrRect = CGRect.zero
    private var blRect = CGRect.zero
    private var bcRect = CGRect.zero
    private var brRect = CGRect.zero
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        guard let nextView = nextPage as? UIView,
              let curView = curPage as? UIView,
              let prevView = prevPage as? UIView else { return }
        
        addSubview(nextView)
        addSubview(curView)
        addSubview(prevView)
        
        // 翻页由父视图绘制同一份页面快照，子视图只保存页面数据和尺寸。
        prevView.isHidden = true
        curView.isHidden = true
        nextView.isHidden = true
        
        backgroundColor = .white
        isUserInteractionEnabled = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        setRect9x()
        (prevPage as? UIView)?.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width, height: bounds.height)
        (curPage as? UIView)?.frame = bounds
        (nextPage as? UIView)?.frame = bounds
        pageDelegate?.setViewSize(width: bounds.width, height: bounds.height)
        onSizeChange?(bounds.size)
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if let delegate = pageDelegate, delegate.isRunning, !(delegate is NoAnimPageDelegate) {
            delegate.onDraw(context)
        } else {
            (curPage as? PageView)?.draw(bounds)
        }
    }
    
    private func setRect9x() {
        let w = bounds.width
        let h = bounds.height
        
        tlRect = CGRect(x: 0, y: 0, width: w * 0.33, height: h * 0.33)
        tcRect = CGRect(x: w * 0.33, y: 0, width: w * 0.33, height: h * 0.33)
        trRect = CGRect(x: w * 0.36, y: 0, width: w * 0.64, height: h * 0.33)
        mlRect = CGRect(x: 0, y: h * 0.33, width: w * 0.33, height: h * 0.33)
        mcRect = CGRect(x: w * 0.33, y: h * 0.33, width: w * 0.33, height: h * 0.33)
        mrRect = CGRect(x: w * 0.66, y: h * 0.33, width: w * 0.34, height: h * 0.33)
        blRect = CGRect(x: 0, y: h * 0.66, width: w * 0.33, height: h * 0.34)
        bcRect = CGRect(x: w * 0.33, y: h * 0.66, width: w * 0.33, height: h * 0.34)
        brRect = CGRect(x: w * 0.66, y: h * 0.66, width: w * 0.34, height: h * 0.34)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        callBack?.screenOffTimerStart()
        
        if isTextSelected {
            curPage.cancelSelect(false)
            isTextSelected = false
            pressOnTextSelected = true
        } else {
            pressOnTextSelected = false
        }
        
        longPressed = false
        startLongPressTimer()
        
        pressDown = true
        isMove = false
        
        pageDelegate?.onTouch(event: touch, view: self)
        pageDelegate?.onDown()
        setStartPoint(point.x, point.y, anim: false)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let touch = touches.first, pressDown else { return }
        let point = touch.location(in: self)
        
        let absX = abs(startX - point.x)
        let absY = abs(startY - point.y)
        
        if !isMove {
            isMove = absX > slopSquare || absY > slopSquare
        }
        
        if isMove {
            longPressed = false
            cancelLongPressTimer()
            
            if isTextSelected {
                selectText(x: point.x, y: point.y)
            } else {
                pageDelegate?.onTouch(event: touch, view: self)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        guard let touch = touches.first else { return }
        
        callBack?.screenOffTimerStart()
        cancelLongPressTimer()
        
        if !pressDown { return }
        pressDown = false
        
        if pageDelegate?.isMoved == false && !isMove {
            if !longPressed && !pressOnTextSelected {
                if !curPage.onClick(startX, startY) {
                    onSingleTapUp()
                }
                return
            }
        }
        
        if isTextSelected {
            callBack?.showTextActionMenu()
        } else if pageDelegate?.isMoved == true {
            pageDelegate?.onTouch(event: touch, view: self)
        }
        
        pressOnTextSelected = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        cancelLongPressTimer()
        
        if !pressDown { return }
        pressDown = false
        
        if isTextSelected {
            callBack?.showTextActionMenu()
        } else if pageDelegate?.isMoved == true {
            if let touch = touches.first {
                pageDelegate?.onTouch(event: touch, view: self)
            }
        }
        
        pressOnTextSelected = false
    }
    
    private func startLongPressTimer() {
        cancelLongPressTimer()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressTimeout, repeats: false) { [weak self] _ in
            self?.longPressed = true
            self?.onLongPress()
        }
    }
    
    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    private func onLongPress() {
        curPage.longPress(startX, startY) { textPos in
            isTextSelected = true
            pressOnTextSelected = true
            
            let page = curPage.relativePage(textPos.relativePagePos)
            let textLine = page.getLine(textPos.lineIndex)
            
            var startPos = textPos
            var endPos = textPos
            
            startPos.lineIndex = textPos.lineIndex
            startPos.columnIndex = 0
            endPos.lineIndex = textPos.lineIndex
            endPos.columnIndex = max(0, textLine.columns.count - 1)
            
            curPage.selectStartMoveIndex(startPos)
            curPage.selectEndMoveIndex(endPos)
        }
    }
    
    private func onSingleTapUp() {
        if isTextSelected { return }
        
        if mcRect.contains(CGPoint(x: startX, y: startY)) {
            if !isAbortAnim {
                click(action: AppConfig.clickActionMC)
            }
        } else if bcRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionBC)
        } else if blRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionBL)
        } else if brRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionBR)
        } else if mlRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionML)
        } else if mrRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionMR)
        } else if tlRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionTL)
        } else if tcRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionTC)
        } else if trRect.contains(CGPoint(x: startX, y: startY)) {
            click(action: AppConfig.clickActionTR)
        }
    }
    
    private func click(action: Int) {
        switch action {
        case 0:
            callBack?.showActionMenu()
        case 1:
            pageDelegate?.nextPageByAnim(animationSpeed: defaultAnimationSpeed)
        case 2:
            pageDelegate?.prevPageByAnim(animationSpeed: defaultAnimationSpeed)
        case 3:
            ReadBook.shared.moveToNextChapter(true, false)
        case 4:
            ReadBook.shared.moveToPrevChapter(true, upContentInPlace: false)
        case 5:
            break
        case 6:
            break
        case 7:
            callBack?.addBookmark()
        default:
            break
        }
    }
    
    private func selectText(x: CGFloat, y: CGFloat) {
        curPage.selectEndMove(x: x, y: y)
    }
    
    func cancelSelect(clearSearchResult: Bool = false) {
        if isTextSelected {
            curPage.cancelSelect(clearSearchResult)
            isTextSelected = false
        }
    }
    
    func setStartPoint(_ x: CGFloat, _ y: CGFloat, anim: Bool) {
        startX = x
        startY = y
        lastX = x
        lastY = y
        touchX = x
        touchY = y
        
        if anim {
            setNeedsDisplay()
        }
    }
    
    func setTouchPoint(_ x: CGFloat, _ y: CGFloat, anim: Bool) {
        lastX = touchX
        lastY = touchY
        touchX = x
        touchY = y
        
        if anim {
            setNeedsDisplay()
        }
        
        pageDelegate?.onScroll()
        setNeedsDisplay()
        
        let offset = touchY - lastY
        touchY -= offset - offset.rounded()
    }
    
    func invalidate() {
        setNeedsDisplay()
    }
    
    func fillPage(_ direction: PageDirection) {
        switch direction {
        case .prev:
            if pageFactory?.hasPrev() == true {
                pageFactory?.moveToPrev(upContent: true)
                upContent()
            }
        case .next:
            if pageFactory?.hasNext() == true {
                pageFactory?.moveToNext(upContent: true)
                upContent()
            }
        case .none:
            break
        }
    }
    
    func upContent() {
        (curPage as? ContentTextView)?.setPage(pageFactory?.curPage)
        (prevPage as? ContentTextView)?.setPage(pageFactory?.prevPage)
        (nextPage as? ContentTextView)?.setPage(pageFactory?.nextPage)
        (curPage as? UIView)?.setNeedsDisplay()
        (prevPage as? UIView)?.setNeedsDisplay()
        (nextPage as? UIView)?.setNeedsDisplay()
        (pageDelegate as? ScrollPageDelegate)?.invalidateImages()
        accessibilityLabel = curPage.textPage?.text
        isAccessibilityElement = true
        setNeedsDisplay()
    }
    
    func dispose() {
        cancelLongPressTimer()
        pageDelegate?.onDestroy()
        pageDelegate = nil
        onSizeChange = nil
    }

    func onScrollAnimStart() {
        isScroll = true
    }
    
    func onScrollAnimStop() {
        isScroll = false
    }
    
    func getCurVisiblePage() -> TextPage {
        return curPage.textPage ?? TextPage.empty
    }
    
    func isLongScreenShot() -> Bool {
        return false
    }
    
    func upPageAnim() {
        let anim = ReadBook.shared.pageAnim()
        
        switch anim {
        case 0:
            pageDelegate = CoverPageDelegate(readView: self)
        case 1:
            pageDelegate = SlidePageDelegate(readView: self)
        case 2:
            pageDelegate = SimulationPageDelegate(readView: self)
        case 3:
            pageDelegate = ScrollPageDelegate(readView: self)
        case 4:
            pageDelegate = NoAnimPageDelegate(readView: self)
        default:
            pageDelegate = CoverPageDelegate(readView: self)
        }
    }
}

/// 页面视图
/// 一比一移植自 Android Legado PageView
class PageView: ContentTextView, PageViewProtocol {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    var width: CGFloat { bounds.width }
    var height: CGFloat { bounds.height }
    
    func resetPageOffset() {
    }
    
    func scroll(_ offset: Int) {
    }
    
    func screenshot() -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            (backgroundColor ?? .white).setFill()
            context.fill(bounds)
            // 上一页和下一页处于隐藏状态，不能依赖隐藏 CALayer 的 render。
            draw(bounds)
        }
    }
    
    func onClick(_ x: CGFloat, _ y: CGFloat) -> Bool {
        return false
    }
    
    func longPress(_ x: CGFloat, _ y: CGFloat, callback: (TextPos) -> Void) {
    }
    
    func cancelSelect(_ clearSearchResult: Bool = false) {
    }
    
    func selectStartMoveIndex(_ pos: TextPos) {
    }
    
    func selectEndMoveIndex(_ pos: TextPos) {
    }
    
    func selectEndMove(x: CGFloat, y: CGFloat) {
    }
    
    func relativePage(_ pos: Int) -> TextPage {
        return textPage ?? TextPage.empty
    }
    
    func getLine(_ index: Int) -> TextLine {
        guard let lines = textPage?.lines, lines.indices.contains(index) else { return TextLine.empty }
        return lines[index]
    }
}
