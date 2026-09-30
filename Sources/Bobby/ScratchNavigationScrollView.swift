import AppKit
import BobbyCore

final class ScratchNavigationScrollView: NSScrollView {
    var pagingEnabled = false
    var onSwipe: ((ScratchSwipeResponse) -> Void)?
    var onGestureReset: (() -> Void)?
    var isPagingLocked: (() -> Bool)?
    private var swipeRecognizer = ScratchSwipeRecognizer()
    private var suppressGestureTail = false

    override func scrollWheel(with event: NSEvent) {
        guard pagingEnabled,
              window?.attachedSheet == nil,
              event.hasPreciseScrollingDeltas,
              event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty else {
            swipeRecognizer.reset()
            onGestureReset?()
            super.scrollWheel(with: event)
            return
        }

        if isPagingLocked?() == true { return }
        if event.momentumPhase.isEmpty, event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            onGestureReset?()
            suppressGestureTail = false
            swipeRecognizer = ScratchSwipeRecognizer(navigationThreshold: ScratchPagingGeometry.commitThreshold(viewportWidth: Double(bounds.width)))
        }
        if suppressGestureTail { return }

        let response = swipeRecognizer.handle(
            horizontal: ScratchSwipeRecognizer.physicalMotion(
                scrollingDelta: Double(event.scrollingDeltaX),
                invertedFromDevice: event.isDirectionInvertedFromDevice),
            vertical: ScratchSwipeRecognizer.physicalMotion(
                scrollingDelta: Double(event.scrollingDeltaY),
                invertedFromDevice: event.isDirectionInvertedFromDevice),
            phase: swipePhase(event.phase),
            isMomentum: !event.momentumPhase.isEmpty
        )
        onSwipe?(response)
        if !response.consumesEvent { super.scrollWheel(with: event) }
    }

    func resetSwipe() {
        swipeRecognizer.reset()
        suppressGestureTail = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        swipeRecognizer.reset()
        super.viewWillMove(toWindow: newWindow)
    }

    private func swipePhase(_ phase: NSEvent.Phase) -> ScratchSwipePhase {
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) || phase.contains(.stationary) { return .changed }
        if phase.contains(.mayBegin) { return .mayBegin }
        return .none
    }
}
