import Foundation

/// Geometry for a scratch page that follows a horizontal trackpad gesture.
public enum ScratchPagingGeometry {
    public static func commitThreshold(viewportWidth: Double) -> Double {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return 80 }
        return min(220, max(120, viewportWidth * 0.18))
    }

    public static func dragOffset(_ motion: Double, viewportWidth: Double,
                                  hasNeighbor: Bool) -> Double {
        guard motion.isFinite, viewportWidth.isFinite, viewportWidth > 0 else { return 0 }
        if hasNeighbor { return min(viewportWidth, max(-viewportWidth, motion)) }

        // Equivalent to motion * 0.24 / (1 + abs(motion) / (width * 0.18)).
        // This form stays finite even when the input-to-width ratio overflows.
        let magnitude = abs(motion)
        let resistanceScale = viewportWidth * 0.18
        guard magnitude > 0, resistanceScale > 0 else { return 0 }
        let resisted = magnitude <= resistanceScale
            ? magnitude * 0.24 / (1 + magnitude / resistanceScale)
            : resistanceScale * 0.24 / (1 + resistanceScale / magnitude)
        return motion < 0 ? -resisted : resisted
    }

    public static func neighborOffset(pageOffset: Double, viewportWidth: Double,
                                      direction: ScratchNavigationDirection) -> Double {
        guard pageOffset.isFinite, viewportWidth.isFinite, viewportWidth > 0 else { return 0 }
        let offset = pageOffset + (direction == .next ? viewportWidth : -viewportWidth)
        return offset.isFinite ? offset : 0
    }
}
