import AppKit
import BobbyCore

final class ScratchNavigationScrollView: NSScrollView {
    var onNavigate: ((ScratchNavigationDirection) -> Void)?
    private var swipeRecognizer = ScratchSwipeRecognizer()

    override func scrollWheel(with event: NSEvent) {
        guard let onNavigate,
              window?.attachedSheet == nil,
              event.hasPreciseScrollingDeltas,
              event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty else {
            swipeRecognizer.reset()
            super.scrollWheel(with: event)
            return
        }

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
        if let direction = response.navigation { onNavigate(direction) }
        if !response.consumesEvent { super.scrollWheel(with: event) }
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
