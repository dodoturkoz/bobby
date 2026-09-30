import AppKit
import BobbyCore
import QuartzCore

struct ScratchPagePreview: Equatable {
    let id: UUID
    let text: String
    let results: [DisplayResult]
}

/// Keeps one editable text view, with a clipped snapshot overlay while paging.
/// The incoming image remains until SwiftUI has loaded the destination editor.
final class ScratchPagerView: NSView {
    let scrollView = ScratchNavigationScrollView()
    var onNavigate: ((ScratchNavigationDirection) -> UUID?)?
    var selectedScratchID: (() -> UUID?)?
    var onPreviewResults: ((String) -> [DisplayResult])?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var currentID: UUID?
    private var currentText = ""
    private var previous: ScratchPagePreview?
    private var next: ScratchPagePreview?
    private var overlay: ScratchPageOverlay?
    private var originID: UUID?
    private var destinationID: UUID?
    private var pendingEditorID: UUID?
    private var isSettling = false
    private var generation = 0
    private var pageOffset: CGFloat = 0
    private var previousImage: CGImage?
    private var nextImage: CGImage?
    private var windowObservers: [NSObjectProtocol] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var isAwaitingEditor: Bool { pendingEditorID != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
        scrollView.onSwipe = { [weak self] response in self?.handleSwipe(response) }
        scrollView.onGestureReset = { [weak self] in
            guard let self, !self.isSettling, !self.isAwaitingEditor else { return }
            self.cancelTransition()
        }
        scrollView.isPagingLocked = { [weak self] in self?.isSettling == true || self?.isAwaitingEditor == true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }

    func updatePages(currentID: UUID?, text: String, previous: ScratchPagePreview?, next: ScratchPagePreview?) {
        let selectedID = selectedScratchID.map { $0() } ?? pendingEditorID
        if pendingEditorID != nil, currentID == selectedID {
            // Called after string, result layout, and scratch identity synchronize.
            pendingEditorID = nil
            cancelTransition(resetGesture: false)
            restoreEditorFocus()
        } else if overlay != nil, (currentID != originID || text != currentText) {
            cancelTransition()
        }
        self.currentID = currentID
        currentText = text
        self.previous = previous
        self.next = next
        scrollView.pagingEnabled = onNavigate != nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { cancelTransition() }
        super.setFrameSize(newSize)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        cancelTransition()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] _ in
                self?.cancelTransition()
            })
        }
    }

    /// Editing or clicking cancels a pending drag, but never edits an outgoing
    /// document during the short model-to-editor handoff after navigation.
    func prepareForInteraction() -> Bool {
        guard !isAwaitingEditor else { return false }
        if overlay != nil { cancelTransition() }
        return true
    }

    func cancelTransition(resetGesture: Bool = true) {
        generation += 1
        overlay?.layer?.removeAllAnimations()
        overlay?.current.removeAllAnimations()
        overlay?.neighbor.removeAllAnimations()
        overlay?.removeFromSuperview()
        overlay = nil
        originID = nil
        destinationID = nil
        isSettling = false
        pageOffset = 0
        previousImage = nil
        nextImage = nil
        if resetGesture { scrollView.resetSwipe() }
        // Visual cancellation must not unlock an outgoing editor after the model
        // has selected another scratch. updatePages releases that identity lock.
    }

    func handleSwipe(_ response: ScratchSwipeResponse) {
        guard !isSettling, !isAwaitingEditor, onNavigate != nil else { return }
        guard let motion = response.dragOffset else { return }
        if reduceMotion() {
            if overlay != nil { cancelTransition(resetGesture: false) }
            if response.gestureEnded, !response.cancelled, let direction = response.navigation,
               let target = page(for: direction) { navigate(direction: direction, target: target) }
            return
        }
        guard bounds.width > 1, bounds.height > 1, currentID != nil,
              window?.attachedSheet == nil else { cancelTransition(); return }
        if overlay == nil { beginTransition() }
        guard let overlay else { return }
        let direction: ScratchNavigationDirection = motion < 0 ? .next : .previous
        let neighbor = page(for: direction)
        pageOffset = CGFloat(ScratchPagingGeometry.dragOffset(motion, viewportWidth: Double(bounds.width), hasNeighbor: neighbor != nil))
        overlay.neighbor.contents = image(for: direction)
        setOffsets(pageOffset, direction: direction)
        guard response.gestureEnded else { return }
        let commit = !response.cancelled && response.navigation == direction && neighbor != nil
        settle(direction: direction, target: commit ? neighbor : nil)
    }

    private func beginTransition() {
        guard let image = snapshot(scrollView, rect: scrollView.bounds) else { return }
        originID = currentID
        let overlay = ScratchPageOverlay(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.onInteraction = { [weak self] in self?.prepareForInteraction() ?? false }
        overlay.current.contents = image
        overlay.current.contentsScale = window?.backingScaleFactor ?? 2
        overlay.neighbor.contentsScale = window?.backingScaleFactor ?? 2
        addSubview(overlay, positioned: .above, relativeTo: scrollView)
        self.overlay = overlay
    }

    private func setOffsets(_ offset: CGFloat, direction: ScratchNavigationDirection) {
        guard let overlay else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overlay.current.transform = CATransform3DMakeTranslation(offset, 0, 0)
        let neighborOffset = ScratchPagingGeometry.neighborOffset(pageOffset: Double(offset), viewportWidth: Double(bounds.width), direction: direction)
        overlay.neighbor.transform = CATransform3DMakeTranslation(CGFloat(neighborOffset), 0, 0)
        CATransaction.commit()
    }

    private func settle(direction: ScratchNavigationDirection, target: ScratchPagePreview?) {
        guard let overlay else { return }
        isSettling = true
        destinationID = target?.id
        generation += 1
        let token = generation
        let finalOffset: CGFloat = target == nil ? 0 : (direction == .next ? -bounds.width : bounds.width)
        let finalNeighbor = CGFloat(ScratchPagingGeometry.neighborOffset(pageOffset: Double(finalOffset), viewportWidth: Double(bounds.width), direction: direction))
        let initialNeighbor = CGFloat(ScratchPagingGeometry.neighborOffset(pageOffset: Double(pageOffset), viewportWidth: Double(bounds.width), direction: direction))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == token else { return }
            self.finishNavigation(direction: direction, target: target)
        }
        for (layer, from, to) in [(overlay.current, pageOffset, finalOffset), (overlay.neighbor, initialNeighbor, finalNeighbor)] {
            layer.transform = CATransform3DMakeTranslation(to, 0, 0)
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = from
            animation.toValue = to
            animation.duration = 0.24
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            layer.add(animation, forKey: "settle")
        }
        CATransaction.commit()
    }

    func finishNavigation(direction: ScratchNavigationDirection, target: ScratchPagePreview?) {
        guard isSettling else { return }
        guard let target else { cancelTransition(resetGesture: false); return }
        guard destinationID == target.id, currentID == originID, page(for: direction)?.id == target.id,
              window?.attachedSheet == nil else { cancelTransition(); return }
        isSettling = false
        navigate(direction: direction, target: target)
    }

    private func navigate(direction: ScratchNavigationDirection, target: ScratchPagePreview) {
        pendingEditorID = target.id
        window?.makeFirstResponder(self)
        let selectedID = onNavigate?(direction)
        // The callback may synchronize the editor immediately. Otherwise keep
        // the outgoing editor locked until its actual selected identity loads.
        guard pendingEditorID != nil else { return }
        guard let selectedID, selectedID != currentID else {
            pendingEditorID = nil
            cancelTransition(resetGesture: false)
            restoreEditorFocus()
            return
        }
        pendingEditorID = selectedID
    }

    private func restoreEditorFocus() {
        if window?.isKeyWindow == true, window?.attachedSheet == nil {
            window?.makeFirstResponder(scrollView.documentView)
        }
    }

    private func page(for direction: ScratchNavigationDirection) -> ScratchPagePreview? {
        direction == .next ? next : previous
    }

    private func image(for direction: ScratchNavigationDirection) -> CGImage? {
        if direction == .next, let nextImage { return nextImage }
        if direction == .previous, let previousImage { return previousImage }
        guard let page = page(for: direction) else { return nil }
        let editor = ResultTextView(frame: NSRect(origin: .zero, size: bounds.size))
        editor.configureScratchAppearance()
        editor.appearance = effectiveAppearance
        editor.isEditable = false
        editor.isSelectable = false
        editor.string = page.text
        editor.displayResults = onPreviewResults?(page.text) ?? page.results
        editor.layoutResults()
        let image = snapshot(editor, rect: NSRect(origin: .zero, size: bounds.size))
        if direction == .next { nextImage = image }
        else { previousImage = image }
        return image
    }

    private func snapshot(_ view: NSView, rect: NSRect) -> CGImage? {
        let scale = window?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                           pixelsWide: max(1, Int(rect.width * scale)), pixelsHigh: max(1, Int(rect.height * scale)),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = rect.size
        view.cacheDisplay(in: rect, to: bitmap)
        return bitmap.cgImage
    }
}

private final class ScratchPageOverlay: NSView {
    let current = CALayer()
    let neighbor = CALayer()
    var onInteraction: (() -> Bool)?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.masksToBounds = true
        for image in [neighbor, current] {
            image.frame = bounds
            image.contentsGravity = .resize
            layer?.addSublayer(image)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        forwardInteraction(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        forwardInteraction(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        forwardInteraction(event)
    }

    private func forwardInteraction(_ event: NSEvent) {
        let parent = superview
        if onInteraction?() == true { parent?.window?.sendEvent(event) }
    }

    override func scrollWheel(with event: NSEvent) {
        (superview as? ScratchPagerView)?.scrollView.scrollWheel(with: event)
    }
}
