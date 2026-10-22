import Foundation

public enum MouseButton: Sendable, Hashable, CaseIterable {
    case left, right
}

/// macOS virtual key codes (ANSI positions) used by the fixed controls and shortcuts.
public enum KeyCode: UInt16, Sendable, Hashable, CaseIterable {
    case a = 0
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case w = 13
    case returnKey = 36
    case tab = 48
    case space = 49
    case delete = 51
    case escape = 53
    case leftArrow = 123
    case rightArrow = 124
    case downArrow = 125
    case upArrow = 126

    public var isArrow: Bool {
        switch self {
        case .leftArrow, .rightArrow, .downArrow, .upArrow: return true
        default: return false
        }
    }
}

public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

public enum OutputAction: Equatable, Sendable {
    /// Pointer movement in screen points (y grows downwards).
    case pointerMove(dx: Int, dy: Int)
    case mouseButton(MouseButton, down: Bool)
    /// Scroll-wheel pixels: positive vertical scrolls up, positive horizontal scrolls left.
    case scroll(vertical: Int, horizontal: Int)
    case key(KeyCode, down: Bool, isRepeat: Bool)
    /// A complete press and release, with modifiers held around it.
    case keyTap(KeyCode, modifiers: KeyModifiers)
    /// Literal text typed into the focused app.
    case text(String)
    /// The pause chord completed. Not an OS event; the app toggles manual pause.
    case togglePause

    /// Releases are always allowed through, even when output is otherwise suspended.
    public var isRelease: Bool {
        switch self {
        case .mouseButton(_, down: false), .key(_, down: false, _): return true
        default: return false
        }
    }
}

public struct MapperConfig: Equatable, Sendable {
    public var deadzone = 0.15
    public var pointerMaxSpeed = 1800.0  // points per second at full deflection
    public var pointerExponent = 2.0
    public var precisionFactor = 0.3  // speed multiplier while LT is held
    public var precisionTriggerThreshold = 0.5
    public var scrollMaxSpeed = 1500.0  // pixels per second
    public var scrollExponent = 2.0
    public var repeatDelay = 0.4
    public var repeatInterval = 0.06
    /// Repeat rate for keyboard-overlay backspace and character stepping.
    public var overlayRepeatInterval = 0.1
    public var pauseHoldDuration = 1.0
    /// Upper bound for one step, so a late tick can never fling the pointer.
    public var maxStep = 1.0 / 30.0

    public init() {}
}

/// Turns controller snapshots into desktop mouse/keyboard actions.
///
/// Pure and deterministic: the caller supplies time and the current output mode, and
/// posts the returned actions. The mapper owns which synthetic buttons/keys are held,
/// releases them when leaving Desktop, and refuses new actions until the controller has
/// returned to neutral after any mode change.
public final class DesktopMapper {
    enum Binding: Equatable {
        case mouse(MouseButton)
        case key(KeyCode, repeats: Bool)
    }

    static let bindings: [ControllerButton: Binding] = [
        .a: .mouse(.left),
        .b: .mouse(.right),
        .x: .key(.escape, repeats: false),
        .y: .key(.returnKey, repeats: false),
        .dpadUp: .key(.upArrow, repeats: true),
        .dpadDown: .key(.downArrow, repeats: true),
        .dpadLeft: .key(.leftArrow, repeats: true),
        .dpadRight: .key(.rightArrow, repeats: true),
    ]

    /// Can change while running (settings); takes effect on the next update.
    public var config: MapperConfig

    public private(set) var isArmed = false
    private var lastTime: TimeInterval?
    private var lastMode: OutputMode?
    private var previousButtons: Set<ControllerButton> = []
    private var heldMouse: Set<MouseButton> = []
    private struct HeldKey {
        /// Nil when the key does not repeat.
        var nextRepeat: TimeInterval?
    }
    private var heldKeys: [KeyCode: HeldKey] = [:]
    private var pointerRemainder = Vec2.zero
    private var scrollRemainder = Vec2.zero

    public init(config: MapperConfig = MapperConfig()) {
        self.config = config
    }

    public func update(_ snapshot: ControllerSnapshot, at time: TimeInterval, mode: OutputMode)
        -> [OutputAction]
    {
        var out: [OutputAction] = []
        let dt = lastTime.map { min(max(time - $0, 0), config.maxStep) } ?? 0
        lastTime = time

        if mode != lastMode {
            out += releaseAll()
            isArmed = false
            pointerRemainder = .zero
            scrollRemainder = .zero
            lastMode = mode
        }

        guard mode == .desktop else {
            previousButtons = snapshot.buttons
            return out
        }

        if !isArmed {
            guard isNeutral(snapshot) else {
                previousButtons = snapshot.buttons
                return out
            }
            isArmed = true
            previousButtons = []
        }

        out += buttonEdges(snapshot.buttons, at: time)
        out += keyRepeats(at: time)
        out += pointer(snapshot, dt: dt)
        out += scroll(snapshot, dt: dt)
        previousButtons = snapshot.buttons
        return out
    }

    /// Releases every synthetic button and key this mapper holds, in a stable order.
    public func releaseAll() -> [OutputAction] {
        var out: [OutputAction] = []
        for button in MouseButton.allCases where heldMouse.contains(button) {
            out.append(.mouseButton(button, down: false))
        }
        for key in KeyCode.allCases where heldKeys[key] != nil {
            out.append(.key(key, down: false, isRepeat: false))
        }
        heldMouse.removeAll()
        heldKeys.removeAll()
        return out
    }

    /// Releases everything and stops producing actions until the controller next
    /// returns to neutral. Used when an overlay takes over the controller.
    public func disarm() -> [OutputAction] {
        let out = releaseAll()
        isArmed = false
        pointerRemainder = .zero
        scrollRemainder = .zero
        return out
    }

    /// Whether the caller should keep calling `update` on a timer. False when the
    /// controller is idle, so the app does no work at rest.
    public func needsTicks(_ snapshot: ControllerSnapshot) -> Bool {
        !snapshot.buttons.isEmpty
            || StickMath.applyRadialDeadzone(snapshot.leftStick, deadzone: config.deadzone) != .zero
            || StickMath.applyRadialDeadzone(snapshot.rightStick, deadzone: config.deadzone)
                != .zero
    }

    // MARK: - Internals

    private func isNeutral(_ snapshot: ControllerSnapshot) -> Bool {
        snapshot.buttons.isEmpty
            && snapshot.leftStick.length <= config.deadzone
            && snapshot.rightStick.length <= config.deadzone
    }

    private func buttonEdges(_ buttons: Set<ControllerButton>, at time: TimeInterval)
        -> [OutputAction]
    {
        var out: [OutputAction] = []
        for button in ControllerButton.allCases {
            guard let binding = Self.bindings[button] else { continue }
            let isDown = buttons.contains(button)
            let wasDown = previousButtons.contains(button)
            if isDown && !wasDown {
                switch binding {
                case .mouse(let mouse) where !heldMouse.contains(mouse):
                    heldMouse.insert(mouse)
                    out.append(.mouseButton(mouse, down: true))
                case .key(let key, let repeats) where heldKeys[key] == nil:
                    heldKeys[key] = HeldKey(nextRepeat: repeats ? time + config.repeatDelay : nil)
                    out.append(.key(key, down: true, isRepeat: false))
                default:
                    break
                }
            } else if !isDown && wasDown {
                switch binding {
                case .mouse(let mouse) where heldMouse.contains(mouse):
                    heldMouse.remove(mouse)
                    out.append(.mouseButton(mouse, down: false))
                case .key(let key, _) where heldKeys[key] != nil:
                    heldKeys[key] = nil
                    out.append(.key(key, down: false, isRepeat: false))
                default:
                    break
                }
            }
        }
        return out
    }

    private func keyRepeats(at time: TimeInterval) -> [OutputAction] {
        var out: [OutputAction] = []
        for key in KeyCode.allCases {
            guard let next = heldKeys[key]?.nextRepeat, time >= next else { continue }
            out.append(.key(key, down: true, isRepeat: true))
            heldKeys[key]?.nextRepeat = max(next + config.repeatInterval, time)
        }
        return out
    }

    private func pointer(_ snapshot: ControllerSnapshot, dt: Double) -> [OutputAction] {
        let stick = StickMath.applyRadialDeadzone(snapshot.leftStick, deadzone: config.deadzone)
        guard stick != .zero, dt > 0 else {
            pointerRemainder = .zero
            return []
        }
        var speed = config.pointerMaxSpeed
        if snapshot.leftTrigger >= config.precisionTriggerThreshold {
            speed *= config.precisionFactor
        }
        let velocity = StickMath.velocity(stick, maxSpeed: speed, exponent: config.pointerExponent)
        // Stick up is +y; screen y grows downwards.
        pointerRemainder.x += velocity.x * dt
        pointerRemainder.y += -velocity.y * dt
        let dx = Int(pointerRemainder.x.rounded(.towardZero))
        let dy = Int(pointerRemainder.y.rounded(.towardZero))
        guard dx != 0 || dy != 0 else { return [] }
        pointerRemainder.x -= Double(dx)
        pointerRemainder.y -= Double(dy)
        return [.pointerMove(dx: dx, dy: dy)]
    }

    private func scroll(_ snapshot: ControllerSnapshot, dt: Double) -> [OutputAction] {
        let stick = StickMath.applyRadialDeadzone(snapshot.rightStick, deadzone: config.deadzone)
        guard stick != .zero, dt > 0 else {
            scrollRemainder = .zero
            return []
        }
        let velocity = StickMath.velocity(
            stick, maxSpeed: config.scrollMaxSpeed, exponent: config.scrollExponent)
        // Stick up scrolls up (positive wheel). Stick right reveals content to the
        // right, which is a negative horizontal wheel value.
        scrollRemainder.y += velocity.y * dt
        scrollRemainder.x += -velocity.x * dt
        let vertical = Int(scrollRemainder.y.rounded(.towardZero))
        let horizontal = Int(scrollRemainder.x.rounded(.towardZero))
        guard vertical != 0 || horizontal != 0 else { return [] }
        scrollRemainder.y -= Double(vertical)
        scrollRemainder.x -= Double(horizontal)
        return [.scroll(vertical: vertical, horizontal: horizontal)]
    }
}
