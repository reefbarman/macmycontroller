/// A 2D stick value. `y` is positive when the stick is pushed up.
public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
}

public enum ControllerButton: String, CaseIterable, Sendable, Hashable {
    case a, b, x, y
    case leftShoulder, rightShoulder
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case menu, view
    case leftThumbstick, rightThumbstick
}

/// The state of one controller at an instant, independent of GameController types.
public struct ControllerSnapshot: Equatable, Sendable {
    public var leftStick: Vec2
    public var rightStick: Vec2
    public var leftTrigger: Double
    public var rightTrigger: Double
    public var buttons: Set<ControllerButton>

    public init(
        leftStick: Vec2 = .zero,
        rightStick: Vec2 = .zero,
        leftTrigger: Double = 0,
        rightTrigger: Double = 0,
        buttons: Set<ControllerButton> = []
    ) {
        self.leftStick = leftStick
        self.rightStick = rightStick
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.buttons = buttons
    }

    public static let neutral = ControllerSnapshot()
}
