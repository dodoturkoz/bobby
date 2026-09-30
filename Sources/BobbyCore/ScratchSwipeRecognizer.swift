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

    public init(consumesEvent: Bool = false, navigation: ScratchNavigationDirection? = nil) {
        self.consumesEvent = consumesEvent
        self.navigation = navigation
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
    private let navigationThreshold = 80.0
    private let horizontalDominance = 1.6

    public init() {}

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
            reset()
            return ScratchSwipeResponse()
        }

        if isMomentum {
            // Momentum can finish a swipe, but cannot initiate another navigation.
            return ScratchSwipeResponse(consumesEvent: consumesMomentum)
        }

        if phase == .mayBegin {
            reset()
            return ScratchSwipeResponse()
        }
        if phase == .began {
            reset()
            tracking = true
        }
        if phase == .cancelled {
            let consumed = tracking && intent == .horizontal
            tracking = false
            consumesMomentum = consumed
            return ScratchSwipeResponse(consumesEvent: consumed)
        }
        guard tracking, phase != .none else { return ScratchSwipeResponse() }

        horizontalMotion += horizontal
        verticalTravel += abs(vertical)
        if intent == .undecided {
            let distance = abs(horizontalMotion)
            if verticalTravel >= intentThreshold && verticalTravel >= distance {
                intent = .vertical
            } else if distance >= intentThreshold && distance >= verticalTravel * horizontalDominance {
                intent = .horizontal
            }
        }

        let consumed = intent == .horizontal
        guard phase == .ended else { return ScratchSwipeResponse(consumesEvent: consumed) }

        tracking = false
        consumesMomentum = consumed
        guard consumed,
              abs(horizontalMotion) >= navigationThreshold,
              abs(horizontalMotion) >= verticalTravel * horizontalDominance else {
            return ScratchSwipeResponse(consumesEvent: consumed)
        }
        return ScratchSwipeResponse(consumesEvent: true,
                                    navigation: horizontalMotion < 0 ? .next : .previous)
    }
}
