import Foundation

public enum ScratchNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

public enum ScratchSwipePhase: Equatable, Sendable {
    case none
    case mayBegin
    case began
    case changed
    case ended
    case cancelled
}

public struct ScratchSwipeResponse: Equatable, Sendable {
    public let consumesEvent: Bool
    public let navigation: ScratchNavigationDirection?
    /// Physical finger motion accumulated after the gesture becomes horizontal.
    /// Nil means this event should not change the visible page position.
    public let dragOffset: Double?
    public let gestureEnded: Bool
    public let cancelled: Bool

    public init(consumesEvent: Bool = false, navigation: ScratchNavigationDirection? = nil,
                dragOffset: Double? = nil, gestureEnded: Bool = false, cancelled: Bool = false) {
        self.consumesEvent = consumesEvent
        self.navigation = navigation
        self.dragOffset = dragOffset
        self.gestureEnded = gestureEnded
        self.cancelled = cancelled
    }
}

/// Recognizes intentional horizontal trackpad gestures independently of AppKit.
/// Motion uses physical finger direction: negative x is left, positive x is right.
public struct ScratchSwipeRecognizer: Sendable {
    private enum Intent: Sendable { case undecided, horizontal, vertical }

    private var intent = Intent.undecided
    private var tracking = false
    private var consumesMomentum = false
    private var horizontalMotion = 0.0
    private var verticalTravel = 0.0
    private let intentThreshold = 10.0
    private let navigationThreshold: Double
    private let horizontalDominance = 1.6

    public init(navigationThreshold: Double = 80) {
        self.navigationThreshold = navigationThreshold.isFinite && navigationThreshold > 0
            ? navigationThreshold : 80
    }

    /// AppKit applies the user's natural-scrolling inversion to wheel deltas.
    /// Convert that value to physical finger motion without inspecting preferences.
    public static func physicalMotion(scrollingDelta: Double, invertedFromDevice: Bool) -> Double {
        invertedFromDevice ? scrollingDelta : -scrollingDelta
    }

    public mutating func reset() {
        intent = .undecided
        tracking = false
        consumesMomentum = false
        horizontalMotion = 0
        verticalTravel = 0
    }

    public mutating func handle(horizontal: Double, vertical: Double,
                                phase: ScratchSwipePhase, isMomentum: Bool = false) -> ScratchSwipeResponse {
        guard horizontal.isFinite, vertical.isFinite else {
            let response = cancellationResponse()
            reset()
            return response
        }

        if isMomentum {
            // Momentum can finish a swipe, but cannot initiate another navigation.
            return ScratchSwipeResponse(consumesEvent: consumesMomentum)
        }

        if phase == .mayBegin {
            let response = cancellationResponse(consumesEvent: false)
            reset()
            return response
        }
        if phase == .began {
            reset()
            tracking = true
        }
        if phase == .cancelled {
            let consumed = tracking && intent == .horizontal
            let response = cancellationResponse()
            tracking = false
            consumesMomentum = consumed
            return response
        }
        guard tracking, phase != .none else { return ScratchSwipeResponse() }

        let nextHorizontalMotion = horizontalMotion + horizontal
        let nextVerticalTravel = verticalTravel + abs(vertical)
        guard nextHorizontalMotion.isFinite, nextVerticalTravel.isFinite else {
            let response = cancellationResponse()
            reset()
            return response
        }
        horizontalMotion = nextHorizontalMotion
        verticalTravel = nextVerticalTravel
        if intent == .undecided {
            let distance = abs(horizontalMotion)
            if verticalTravel >= intentThreshold && verticalTravel >= distance {
                intent = .vertical
            } else if distance >= intentThreshold && distance >= verticalTravel * horizontalDominance {
                intent = .horizontal
            }
        }

        let consumed = intent == .horizontal
        let dragOffset = consumed ? horizontalMotion : nil
        guard phase == .ended else {
            return ScratchSwipeResponse(consumesEvent: consumed, dragOffset: dragOffset)
        }

        tracking = false
        consumesMomentum = consumed
        guard consumed,
              abs(horizontalMotion) >= navigationThreshold,
              abs(horizontalMotion) >= verticalTravel * horizontalDominance else {
            return ScratchSwipeResponse(consumesEvent: consumed, dragOffset: dragOffset,
                                        gestureEnded: consumed)
        }
        return ScratchSwipeResponse(consumesEvent: true,
                                    navigation: horizontalMotion < 0 ? .next : .previous,
                                    dragOffset: horizontalMotion, gestureEnded: true)
    }

    private func cancellationResponse(consumesEvent: Bool = true) -> ScratchSwipeResponse {
        guard tracking, intent == .horizontal else { return ScratchSwipeResponse() }
        return ScratchSwipeResponse(consumesEvent: consumesEvent, dragOffset: horizontalMotion,
                                    gestureEnded: true, cancelled: true)
    }
}
