/// The few user-adjustable settings. Speeds are multipliers on the tuned defaults, so
/// 1.0 always means "as shipped".
public struct ControlSettings: Equatable, Codable, Sendable {
    public var pointerSpeed = 1.0
    public var scrollSpeed = 1.0
    public var overlayScale = 1.0

    public static let speedRange = 0.25...3.0
    public static let scaleRange = 0.75...1.6

    public init() {}

    /// Values clamped to the supported ranges, so a hand-edited preference can't break
    /// the controls.
    public var clamped: ControlSettings {
        var copy = self
        copy.pointerSpeed = Self.clamp(pointerSpeed, Self.speedRange)
        copy.scrollSpeed = Self.clamp(scrollSpeed, Self.speedRange)
        copy.overlayScale = Self.clamp(overlayScale, Self.scaleRange)
        return copy
    }

    public func applied(to base: MapperConfig = MapperConfig()) -> MapperConfig {
        let settings = clamped
        var config = base
        config.pointerMaxSpeed = base.pointerMaxSpeed * settings.pointerSpeed
        config.scrollMaxSpeed = base.scrollMaxSpeed * settings.scrollSpeed
        return config
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : 1
    }
}
