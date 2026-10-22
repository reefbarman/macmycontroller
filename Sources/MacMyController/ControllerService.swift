import Foundation
import GameController
import MacMyControllerCore

/// Owns GameController discovery and exposes one active controller as snapshots.
/// Uses background monitoring so input arrives while other apps are frontmost. This
/// only observes the controller; other apps still receive it normally.
@MainActor
final class ControllerService {
    var onConnectionChange: (() -> Void)?
    var onInput: (() -> Void)?

    private(set) var active: GCController?
    private var observers: [NSObjectProtocol] = []

    var isConnected: Bool { active?.extendedGamepad != nil }

    var displayName: String? {
        guard let active else { return nil }
        return active.vendorName ?? active.productCategory
    }

    func start() {
        GCController.shouldMonitorBackgroundEvents = true

        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.selectController() }
                })
        }
        selectController()
    }

    /// Keeps the current controller while it stays connected. Never merges input from
    /// two controllers.
    private func selectController() {
        let candidates = GCController.controllers().filter { $0.extendedGamepad != nil }
        if let active, candidates.contains(active) {
            onConnectionChange?()
            return
        }

        active?.extendedGamepad?.valueChangedHandler = nil
        if let current = GCController.current, candidates.contains(current) {
            active = current
        } else {
            active = candidates.first
        }
        active?.extendedGamepad?.valueChangedHandler = { [weak self] _, _ in
            // Delivered on the main queue (GameController's default handler queue).
            MainActor.assumeIsolated { self?.onInput?() }
        }
        onConnectionChange?()
    }

    var snapshot: ControllerSnapshot {
        guard let pad = active?.extendedGamepad else { return .neutral }
        var buttons = Set<ControllerButton>()
        func add(_ input: GCControllerButtonInput?, _ button: ControllerButton) {
            if input?.isPressed == true { buttons.insert(button) }
        }
        add(pad.buttonA, .a)
        add(pad.buttonB, .b)
        add(pad.buttonX, .x)
        add(pad.buttonY, .y)
        add(pad.leftShoulder, .leftShoulder)
        add(pad.rightShoulder, .rightShoulder)
        add(pad.dpad.up, .dpadUp)
        add(pad.dpad.down, .dpadDown)
        add(pad.dpad.left, .dpadLeft)
        add(pad.dpad.right, .dpadRight)
        add(pad.buttonMenu, .menu)
        add(pad.buttonOptions, .view)
        add(pad.leftThumbstickButton, .leftThumbstick)
        add(pad.rightThumbstickButton, .rightThumbstick)

        return ControllerSnapshot(
            leftStick: Vec2(
                Double(pad.leftThumbstick.xAxis.value), Double(pad.leftThumbstick.yAxis.value)),
            rightStick: Vec2(
                Double(pad.rightThumbstick.xAxis.value), Double(pad.rightThumbstick.yAxis.value)),
            leftTrigger: Double(pad.leftTrigger.value),
            rightTrigger: Double(pad.rightTrigger.value),
            buttons: buttons
        )
    }
}
