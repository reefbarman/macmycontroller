import CoreGraphics

public enum DisplayGeometry {
    /// Keeps the pointer on screen. Displays are in global CoreGraphics coordinates
    /// (top-left origin, other displays may have negative origins). A point inside any
    /// display is allowed, so the pointer can cross between adjacent displays; otherwise
    /// it is clamped to the display it was on.
    public static func clamp(_ point: CGPoint, from previous: CGPoint, displays: [CGRect])
        -> CGPoint
    {
        guard !displays.isEmpty else { return point }
        if displays.contains(where: { contains($0, point) }) { return point }

        let anchor =
            displays.first(where: { contains($0, previous) })
            ?? displays.min(by: { distance($0, previous) < distance($1, previous) })!
        return CGPoint(
            x: min(max(point.x, anchor.minX), anchor.maxX - 1),
            y: min(max(point.y, anchor.minY), anchor.maxY - 1)
        )
    }

    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y < rect.maxY
    }

    static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
