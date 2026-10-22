import Foundation

public struct Shortcut: Equatable, Sendable {
    public var title: String
    /// SF Symbol name for the overlay.
    public var symbol: String
    public var key: KeyCode
    public var modifiers: KeyModifiers
}

public enum Shortcuts {
    /// Eight fixed choices, clockwise from the top. Deliberately no Quit, Force Quit,
    /// shutdown or scripts. Letter keys use ANSI positions, so non-QWERTY layouts and
    /// customised system shortcuts may differ.
    public static let wheel: [Shortcut] = [
        Shortcut(title: "Spotlight", symbol: "magnifyingglass", key: .space, modifiers: .command),
        Shortcut(title: "Copy", symbol: "doc.on.doc", key: .c, modifiers: .command),
        Shortcut(title: "Paste", symbol: "doc.on.clipboard", key: .v, modifiers: .command),
        Shortcut(title: "Cut", symbol: "scissors", key: .x, modifiers: .command),
        Shortcut(title: "Close Window", symbol: "xmark.square", key: .w, modifiers: .command),
        Shortcut(title: "Undo", symbol: "arrow.uturn.backward", key: .z, modifiers: .command),
        Shortcut(
            title: "Previous App", symbol: "arrow.left.arrow.right", key: .tab, modifiers: .command),
        Shortcut(title: "Select All", symbol: "checkmark.rectangle", key: .a, modifiers: .command),
    ]
}

/// Which wheel choice the left stick is aiming at. Centring the stick clears the
/// highlight, so pressing A with a centred stick does nothing.
public struct ShortcutWheel: Equatable, Sendable {
    public private(set) var highlighted: Int?

    public init() {}

    public var selected: Shortcut? { highlighted.map { Shortcuts.wheel[$0] } }

    public mutating func aim(_ stick: Vec2) {
        let length = stick.length
        if length >= 0.5 {
            highlighted = Self.sector(stick, count: Shortcuts.wheel.count)
        } else if length < 0.25 {
            highlighted = nil
        }
    }

    /// Sector index with 0 centred on straight up, increasing clockwise.
    public static func sector(_ value: Vec2, count: Int) -> Int {
        let width = 2 * Double.pi / Double(count)
        var angle = atan2(value.x, value.y) + width / 2
        if angle < 0 { angle += 2 * .pi }
        return Int(angle / width) % count
    }
}
