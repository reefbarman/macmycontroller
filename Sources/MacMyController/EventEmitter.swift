import AppKit
import CoreGraphics
import MacMyControllerCore

/// The only place that posts synthetic mouse and keyboard events.
@MainActor
final class EventEmitter {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var heldMouse: Set<MouseButton> = []
    private var lastDown: (button: MouseButton, time: TimeInterval, location: CGPoint)?
    private var clickCount: Int64 = 1

    func perform(_ action: OutputAction) {
        switch action {
        case .pointerMove(let dx, let dy):
            move(dx: CGFloat(dx), dy: CGFloat(dy))
        case .mouseButton(let button, let down):
            mouse(button, down: down)
        case .scroll(let vertical, let horizontal):
            CGEvent(
                scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0
            )?.post(tap: .cghidEventTap)
        case .key(let key, let down, let isRepeat):
            self.key(key, down: down, isRepeat: isRepeat)
        case .keyTap(let key, let modifiers):
            tap(key, modifiers: modifiers)
        case .text(let text):
            type(text)
        case .togglePause:
            break
        }
    }

    /// Types literal text as Unicode keyboard events, independent of the keyboard
    /// layout. No clipboard involved.
    private func type(_ text: String) {
        let units = Array(text.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            else { continue }
            event.flags = []
            units.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(
                    stringLength: units.count, unicodeString: $0.baseAddress)
            }
            event.post(tap: .cghidEventTap)
        }
    }

    private static let modifierKeys: [(KeyModifiers, CGKeyCode, CGEventFlags)] = [
        (.command, 55, .maskCommand),
        (.shift, 56, .maskShift),
        (.option, 58, .maskAlternate),
        (.control, 59, .maskControl),
    ]

    /// Presses real modifier keys around the key, the way a hardware keyboard does, so
    /// system shortcuts such as Command-Tab and Command-Space are recognised.
    private func tap(_ key: KeyCode, modifiers: KeyModifiers) {
        let held = Self.modifierKeys.filter { modifiers.contains($0.0) }
        var flags: CGEventFlags = []
        for (_, code, flag) in held {
            flags.insert(flag)
            post(code, down: true, flags: flags)
        }
        var keyFlags = flags
        if key.isArrow { keyFlags.formUnion([.maskNumericPad, .maskSecondaryFn]) }
        post(key.rawValue, down: true, flags: keyFlags)
        post(key.rawValue, down: false, flags: keyFlags)
        for (_, code, flag) in held.reversed() {
            flags.remove(flag)
            post(code, down: false, flags: flags)
        }
    }

    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private var currentLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func move(dx: CGFloat, dy: CGFloat) {
        let current = currentLocation
        let target = DisplayGeometry.clamp(
            CGPoint(x: current.x + dx, y: current.y + dy), from: current,
            displays: Self.activeDisplayBounds())

        let type: CGEventType
        let button: CGMouseButton
        if heldMouse.contains(.left) {
            (type, button) = (.leftMouseDragged, .left)
        } else if heldMouse.contains(.right) {
            (type, button) = (.rightMouseDragged, .right)
        } else {
            (type, button) = (.mouseMoved, .left)
        }
        guard
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: target,
                mouseButton: button)
        else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(target.x - current.x))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(target.y - current.y))
        event.post(tap: .cghidEventTap)
    }

    private func mouse(_ button: MouseButton, down: Bool) {
        let location = currentLocation
        if down {
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastDown, last.button == button,
                now - last.time <= NSEvent.doubleClickInterval,
                hypot(last.location.x - location.x, last.location.y - location.y) <= 4
            {
                clickCount += 1
            } else {
                clickCount = 1
            }
            lastDown = (button, now, location)
            heldMouse.insert(button)
        } else {
            heldMouse.remove(button)
        }

        let type: CGEventType
        let cgButton: CGMouseButton
        switch (button, down) {
        case (.left, true): (type, cgButton) = (.leftMouseDown, .left)
        case (.left, false): (type, cgButton) = (.leftMouseUp, .left)
        case (.right, true): (type, cgButton) = (.rightMouseDown, .right)
        case (.right, false): (type, cgButton) = (.rightMouseUp, .right)
        }
        guard
            let event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: location,
                mouseButton: cgButton)
        else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.post(tap: .cghidEventTap)
    }

    private func key(_ key: KeyCode, down: Bool, isRepeat: Bool) {
        guard
            let event = CGEvent(
                keyboardEventSource: source, virtualKey: key.rawValue, keyDown: down)
        else { return }
        // Explicit flags so a stray modifier never leaks into our keys. Arrow keys carry
        // the same flags a hardware keyboard sends.
        event.flags = key.isArrow ? [.maskNumericPad, .maskSecondaryFn] : []
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}

enum Permissions {
    /// Posting synthetic events requires the app to be allowed under
    /// Privacy & Security → Accessibility (macOS 27: Device Control and Data Access).
    /// `CGPreflightPostEventAccess` caches its first answer for the process lifetime, so
    /// a grant made while running is only seen through the live Accessibility check.
    static var canPostEvents: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    static func request() { _ = CGRequestPostEventAccess() }

    static func openSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
