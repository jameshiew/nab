import CoreGraphics

enum PanelGeometry {
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
