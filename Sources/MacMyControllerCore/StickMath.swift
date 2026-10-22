import Foundation

public enum StickMath {
    /// Radial dead zone that rescales the remaining range back to 0...1, so movement
    /// starts smoothly at the dead-zone edge. Magnitude is clamped to 1, which keeps
    /// diagonals (which can report up to ~1.41 on a square range) the same speed as
    /// cardinal directions.
    public static func applyRadialDeadzone(_ value: Vec2, deadzone: Double) -> Vec2 {
        let length = value.length
        guard length > deadzone, length > 0 else { return .zero }
        let clamped = min(length, 1)
        let scaled = (clamped - deadzone) / (1 - deadzone)
        return Vec2(value.x / length * scaled, value.y / length * scaled)
    }

    /// Converts a dead-zoned stick value into a velocity using a power curve, which
    /// gives fine control near the centre and speed at full deflection.
    public static func velocity(_ value: Vec2, maxSpeed: Double, exponent: Double) -> Vec2 {
        let length = value.length
        guard length > 0 else { return .zero }
        let speed = maxSpeed * pow(min(length, 1), exponent)
        return Vec2(value.x / length * speed, value.y / length * speed)
    }
}
