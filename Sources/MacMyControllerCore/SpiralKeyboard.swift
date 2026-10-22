import Foundation

/// The character-selection model behind the spiral keyboard. No drawing and no access
/// to other apps: it only decides which character is selected.
///
/// Rotating the left stick moves along the current page, 12 characters per full turn.
/// The first deflection only sets a starting angle, and returning the stick to the
/// centre keeps the selection and forgets the angle, so regripping never skips letters.
public struct SpiralKeyboard: Equatable, Sendable {
    public enum Page: Int, CaseIterable, Sendable {
        case letters, numbers, symbols

        public var title: String {
            switch self {
            case .letters: return "Letters"
            case .numbers: return "Numbers"
            case .symbols: return "Symbols"
            }
        }

        public var characters: [String] {
            switch self {
            case .letters: return "abcdefghijklmnopqrstuvwxyz".map(String.init)
            case .numbers: return "1234567890".map(String.init)
            case .symbols:
                return [
                    ".", ",", "?", "!", "'", "\"", "-", "_", "@", "#", "/", ":", ";", "(", ")",
                    "&", "+", "=", "*", "%", "$", "~",
                ]
            }
        }
    }

    public static let stepsPerRevolution = 12
    /// The stick must pass this radius to start pointing...
    static let trackRadius = 0.5
    /// ...and drop below this one to stop. The gap avoids flicker near the edge.
    static let releaseRadius = 0.3
    /// Extra angle, in steps, needed past the halfway line before the selection moves
    /// to a neighbour, so a stick resting on a boundary doesn't flicker.
    static let hysteresis = 0.2

    public private(set) var page: Page = .letters
    /// Position along an endless coil, per page. Character = position mod page length,
    /// on-screen direction = position × 30°. Never wraps, so drawing stays continuous.
    private var positions = [Int](repeating: 0, count: Page.allCases.count)
    /// Uppercases letters only, while held. Never sticky.
    public var uppercase = false
    private var pointing = false

    public init() {}

    public var position: Int { positions[page.rawValue] }

    public var selectedIndex: Int { Self.mod(position, page.characters.count) }

    public var characters: [String] {
        guard page == .letters, uppercase else { return page.characters }
        return page.characters.map { $0.uppercased() }
    }

    public var selectedCharacter: String { characters[selectedIndex] }

    public func character(at position: Int) -> String {
        characters[Self.mod(position, characters.count)]
    }

    /// The stick points at a character: the one in that direction on the lap of the
    /// coil you are currently on. Winding past a full turn carries on to the next lap.
    public mutating func rotate(_ stick: Vec2) {
        let length = stick.length
        if length < Self.releaseRadius {
            pointing = false
            return
        }
        guard pointing || length >= Self.trackRadius else { return }
        pointing = true

        let steps = Double(Self.stepsPerRevolution)
        // 0 when pushed up, increasing clockwise, in character steps.
        let angle = atan2(stick.x, stick.y) / (2 * .pi) * steps
        let current = Double(position)
        var offset = (angle - current).truncatingRemainder(dividingBy: steps)
        if offset > steps / 2 { offset -= steps } else if offset < -steps / 2 { offset += steps }
        guard abs(offset) > 0.5 + Self.hysteresis else { return }
        positions[page.rawValue] = Int((current + offset).rounded())
    }

    /// Moves the selection one way or the other. The coil is endless, so this wraps.
    public mutating func step(_ delta: Int) {
        positions[page.rawValue] += delta
    }

    static func mod(_ value: Int, _ count: Int) -> Int { ((value % count) + count) % count }

    public mutating func nextPage() {
        page = Page(rawValue: (page.rawValue + 1) % Page.allCases.count)!
        resetRotation()
    }

    public mutating func previousPage() {
        let count = Page.allCases.count
        page = Page(rawValue: (page.rawValue + count - 1) % count)!
        resetRotation()
    }

    /// Stops pointing until the stick is pushed out again.
    public mutating func resetRotation() {
        pointing = false
    }
}
