import CoreGraphics

enum ScreenGeometry {
    nonisolated static func bestMatchingIndex(for frame: CGRect, in screens: [CGRect]) -> Int? {
        screens.indices.max { lhs, rhs in
            intersectionArea(frame, screens[lhs]) < intersectionArea(frame, screens[rhs])
        }
    }

    nonisolated static func clampedFrame(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let maxX = max(bounds.minX, bounds.maxX - frame.width)
        let maxY = max(bounds.minY, bounds.maxY - frame.height)
        let x = min(max(frame.minX, bounds.minX), maxX)
        let y = min(max(frame.minY, bounds.minY), maxY)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    nonisolated static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }
}
