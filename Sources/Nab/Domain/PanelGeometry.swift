import CoreGraphics

nonisolated enum PanelGeometry {
    static let baseHeight: CGFloat = 360

    private static let rowHeight: CGFloat = 126
    private static let rowSpacing: CGFloat = 12
    private static let chromeHeight: CGFloat = 27
    private static let contentVerticalPadding: CGFloat = 24
    private static let screenMargin: CGFloat = 80

    nonisolated static func height(forItemCount count: Int, screenHeight: CGFloat) -> CGFloat {
        let needed: CGFloat = {
            guard count > 0 else { return baseHeight }
            let rows = CGFloat(count) * rowHeight + CGFloat(count - 1) * rowSpacing
            return chromeHeight + contentVerticalPadding + rows
        }()
        let minimumHeight = min(baseHeight, screenHeight)
        let maxAllowed = max(minimumHeight, screenHeight - screenMargin)
        return min(max(minimumHeight, needed), maxAllowed)
    }

    nonisolated static func resizedVisibleFrame(
        for frame: CGRect,
        itemCount: Int,
        in screen: CGRect
    ) -> CGRect {
        let height = height(forItemCount: itemCount, screenHeight: screen.height)
        let proposed = CGRect(
            x: frame.minX,
            y: frame.maxY - height,
            width: frame.width,
            height: height
        )
        return ScreenGeometry.clampedFrame(proposed, to: screen)
    }

    nonisolated static func frameAtNearestHorizontalEdge(
        for frame: CGRect,
        in screens: [CGRect]
    ) -> CGRect {
        guard let screenIndex = ScreenGeometry.bestMatchingIndex(for: frame, in: screens) else {
            return frame
        }

        let screen = screens[screenIndex]
        let leftX = screen.minX
        let rightX = max(screen.minX, screen.maxX - frame.width)
        let x = abs(frame.minX - leftX) < abs(frame.minX - rightX) ? leftX : rightX
        return CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }
}
