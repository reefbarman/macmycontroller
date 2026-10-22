import Foundation

/// Detects View + Menu held together. Fires once per hold; both buttons must be
/// released before it can fire again.
public struct PauseChord: Sendable {
    private var start: TimeInterval?
    private var fired = false

    public init() {}

    public mutating func update(
        _ buttons: Set<ControllerButton>, at time: TimeInterval, duration: TimeInterval
    ) -> Bool {
        guard buttons.contains(.view) && buttons.contains(.menu) else {
            start = nil
            if !buttons.contains(.view) && !buttons.contains(.menu) { fired = false }
            return false
        }
        if start == nil { start = time }
        if !fired, let start, time - start >= duration {
            fired = true
            return true
        }
        return false
    }

    public mutating func reset() { start = nil }
}

/// Decides where controller input goes: desktop mouse controls, the spiral keyboard or
/// the shortcut wheel. Overlays only exist in Desktop mode; any other mode closes them.
///
/// Overlays react to fresh button presses only, so a button already held when an
/// overlay opens never fires inside it. Closing an overlay leaves the desktop mapper
/// disarmed until the controller returns to neutral.
public final class InputRouter {
    public var config: MapperConfig {
        didSet { desktop.config = config }
    }
    public let desktop: DesktopMapper

    public private(set) var keyboard: SpiralKeyboard?
    public private(set) var wheel: ShortcutWheel?
    /// Keeps page and selection between keyboard opens.
    private var savedKeyboard = SpiralKeyboard()
    private var previousButtons: Set<ControllerButton> = []
    private var lastMode: OutputMode?
    private var chord = PauseChord()
    private var nextRepeat: [ControllerButton: TimeInterval] = [:]

    public init(config: MapperConfig = MapperConfig()) {
        self.config = config
        self.desktop = DesktopMapper(config: config)
    }

    public var isOverlayOpen: Bool { keyboard != nil || wheel != nil }

    public func update(_ snapshot: ControllerSnapshot, at time: TimeInterval, mode: OutputMode)
        -> [OutputAction]
    {
        defer { previousButtons = snapshot.buttons }
        var out: [OutputAction] = []

        if mode != lastMode {
            lastMode = mode
            if mode != .desktop { closeOverlays() }
        }

        if mode == .desktop || mode == .paused {
            if chord.update(snapshot.buttons, at: time, duration: config.pauseHoldDuration) {
                closeOverlays()
                out += desktop.disarm()
                out.append(.togglePause)
                return out
            }
        } else {
            chord.reset()
        }

        guard mode == .desktop else {
            return out + desktop.update(snapshot, at: time, mode: mode)
        }

        let pressed = snapshot.buttons.subtracting(previousButtons)
        if wheel != nil { return updateWheel(snapshot, pressed: pressed) }
        if keyboard != nil { return updateKeyboard(snapshot, pressed: pressed, at: time) }

        if desktop.isArmed {
            if pressed.contains(.leftThumbstick) {
                out += desktop.disarm()
                var restored = savedKeyboard
                restored.resetRotation()
                keyboard = restored
                return out
            }
            if pressed.contains(.rightShoulder) {
                out += desktop.disarm()
                wheel = ShortcutWheel()
                return out
            }
        }
        return out + desktop.update(snapshot, at: time, mode: mode)
    }

    /// Releases anything held and closes overlays. Used on quit.
    public func releaseAll() -> [OutputAction] {
        closeOverlays()
        return desktop.releaseAll()
    }

    public func needsTicks(_ snapshot: ControllerSnapshot) -> Bool {
        desktop.needsTicks(snapshot)
    }

    // MARK: - Overlays

    private func closeOverlays() {
        if let keyboard { savedKeyboard = keyboard }
        keyboard = nil
        wheel = nil
        nextRepeat.removeAll()
    }

    private func updateKeyboard(
        _ snapshot: ControllerSnapshot, pressed: Set<ControllerButton>, at time: TimeInterval
    ) -> [OutputAction] {
        guard var kb = keyboard else { return [] }
        if pressed.contains(.leftThumbstick) {
            closeOverlays()
            return []
        }
        if pressed.contains(.rightShoulder) {
            kb.resetRotation()
            keyboard = kb
            wheel = ShortcutWheel()
            nextRepeat.removeAll()
            return []
        }

        var out: [OutputAction] = []
        let buttons = snapshot.buttons
        kb.uppercase = snapshot.leftTrigger >= config.precisionTriggerThreshold
        kb.rotate(snapshot.leftStick)
        if pressed.contains(.dpadUp) { kb.previousPage() }
        if pressed.contains(.dpadDown) { kb.nextPage() }
        if fires(.dpadLeft, buttons, pressed, time) { kb.step(-1) }
        if fires(.dpadRight, buttons, pressed, time) { kb.step(1) }
        if pressed.contains(.a) { out.append(.text(kb.selectedCharacter)) }
        if pressed.contains(.x) { out.append(.keyTap(.space, modifiers: [])) }
        if pressed.contains(.y) { out.append(.keyTap(.returnKey, modifiers: [])) }
        if fires(.b, buttons, pressed, time) { out.append(.keyTap(.delete, modifiers: [])) }
        keyboard = kb
        return out
    }

    private func updateWheel(_ snapshot: ControllerSnapshot, pressed: Set<ControllerButton>)
        -> [OutputAction]
    {
        guard var current = wheel else { return [] }
        // Releasing RB without choosing cancels.
        guard snapshot.buttons.contains(.rightShoulder) else {
            wheel = nil
            return []
        }
        current.aim(snapshot.leftStick)
        if pressed.contains(.a), let shortcut = current.selected {
            // One command per open.
            wheel = nil
            keyboard?.resetRotation()
            return [.keyTap(shortcut.key, modifiers: shortcut.modifiers)]
        }
        wheel = current
        return []
    }

    /// True on a fresh press, then repeatedly while held after the repeat delay.
    private func fires(
        _ button: ControllerButton, _ buttons: Set<ControllerButton>,
        _ pressed: Set<ControllerButton>, _ time: TimeInterval
    ) -> Bool {
        if pressed.contains(button) {
            nextRepeat[button] = time + config.repeatDelay
            return true
        }
        guard buttons.contains(button) else {
            nextRepeat[button] = nil
            return false
        }
        guard let next = nextRepeat[button], time >= next else { return false }
        nextRepeat[button] = max(next + config.overlayRepeatInterval, time)
        return true
    }
}
