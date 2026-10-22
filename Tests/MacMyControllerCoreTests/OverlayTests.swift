import XCTest

@testable import MacMyControllerCore

/// Stick vector at an angle in degrees, 0 = up, clockwise.
private func stick(_ degrees: Double, _ length: Double = 1) -> Vec2 {
    let r = degrees * .pi / 180
    return Vec2(sin(r) * length, cos(r) * length)
}

final class SpiralKeyboardTests: XCTestCase {
    private func turn(_ kb: inout SpiralKeyboard, from: Double, to: Double) {
        let step: Double = to >= from ? 5 : -5
        for degrees in stride(from: from, through: to, by: step) { kb.rotate(stick(degrees)) }
    }

    func testStickPointsAtCharacters() {
        var kb = SpiralKeyboard()
        kb.rotate(stick(90))
        XCTAssertEqual(kb.selectedCharacter, "d", "right is 3 steps clockwise")
        kb.rotate(.zero)
        kb.rotate(stick(-40))
        XCTAssertEqual(kb.position, -1, "just left of up is z, before a on the same lap")
        XCTAssertEqual(kb.selectedCharacter, "z")
    }

    func testHysteresisOnBoundaries() {
        var kb = SpiralKeyboard()
        kb.rotate(stick(20))
        XCTAssertEqual(kb.selectedCharacter, "a", "just past halfway is not enough")
        kb.rotate(stick(25))
        XCTAssertEqual(kb.selectedCharacter, "b")
        kb.rotate(stick(10))
        XCTAssertEqual(kb.selectedCharacter, "b", "coming back needs the same margin")
    }

    func testPointingStaysOnCurrentLap() {
        var kb = SpiralKeyboard()
        kb.step(13)
        XCTAssertEqual(kb.selectedCharacter, "n")
        kb.rotate(stick(0))
        XCTAssertEqual(kb.position, 12)
        XCTAssertEqual(kb.selectedCharacter, "m", "up on the second lap is m, not a")
    }

    func testTwelveStepsPerRevolution() {
        var kb = SpiralKeyboard()
        turn(&kb, from: 0, to: 95)
        XCTAssertEqual(kb.selectedCharacter, "d")
        turn(&kb, from: 95, to: 365)
        XCTAssertEqual(kb.selectedIndex, 12)
        turn(&kb, from: 365, to: 290)
        XCTAssertEqual(kb.selectedIndex, 10)
    }

    func testWindingCarriesOntoTheNextLapAndWraps() {
        var kb = SpiralKeyboard()
        turn(&kb, from: 0, to: 360 * 2 + 30)
        XCTAssertEqual(kb.position, 25)
        XCTAssertEqual(kb.selectedCharacter, "z")
        turn(&kb, from: 750, to: 780)
        XCTAssertEqual(kb.position, 26)
        XCTAssertEqual(kb.selectedCharacter, "a", "z continues straight on to a")
    }

    func testSmallDeflectionIsIgnored() {
        var kb = SpiralKeyboard()
        for degrees in stride(from: 0.0, through: 180, by: 5) { kb.rotate(stick(degrees, 0.4)) }
        XCTAssertEqual(kb.selectedIndex, 0)
    }

    func testWrapsAroundBothEnds() {
        var kb = SpiralKeyboard()
        turn(&kb, from: 0, to: -35)
        XCTAssertEqual(kb.selectedCharacter, "z", "anticlockwise from a wraps to z")
        turn(&kb, from: -35, to: 0)
        XCTAssertEqual(kb.selectedCharacter, "a", "and clockwise from z wraps back")
        kb.step(-1)
        XCTAssertEqual(kb.selectedCharacter, "z")
        kb.nextPage()
        kb.step(-1)
        XCTAssertEqual(kb.selectedCharacter, "0", "every page wraps")
    }

    func testPagesAndUppercase() {
        var kb = SpiralKeyboard()
        kb.step(2)
        kb.uppercase = true
        XCTAssertEqual(kb.selectedCharacter, "C")
        kb.nextPage()
        XCTAssertEqual(kb.page, .numbers)
        XCTAssertEqual(kb.selectedCharacter, "1", "uppercase only affects letters")
        kb.previousPage()
        kb.previousPage()
        XCTAssertEqual(kb.page, .symbols)
        kb.nextPage()
        kb.uppercase = false
        XCTAssertEqual(kb.selectedCharacter, "c", "each page keeps its own selection")
    }
}

final class ShortcutWheelTests: XCTestCase {
    func testSectors() {
        XCTAssertEqual(ShortcutWheel.sector(Vec2(0, 1), count: 8), 0)
        XCTAssertEqual(ShortcutWheel.sector(Vec2(1, 0), count: 8), 2)
        XCTAssertEqual(ShortcutWheel.sector(Vec2(0, -1), count: 8), 4)
        XCTAssertEqual(ShortcutWheel.sector(Vec2(-1, 0), count: 8), 6)
        XCTAssertEqual(ShortcutWheel.sector(stick(-20), count: 8), 0)
        XCTAssertEqual(ShortcutWheel.sector(stick(30), count: 8), 1)
    }

    func testCentringClearsHighlight() {
        var wheel = ShortcutWheel()
        wheel.aim(Vec2(1, 0))
        XCTAssertEqual(wheel.selected?.title, "Paste")
        wheel.aim(Vec2(0.4, 0))
        XCTAssertEqual(wheel.highlighted, 2, "hysteresis keeps it between radii")
        wheel.aim(Vec2(0.1, 0))
        XCTAssertNil(wheel.highlighted)
    }
}

final class InputRouterTests: XCTestCase {
    private func snap(
        _ buttons: Set<ControllerButton> = [], left: Vec2 = .zero, lt: Double = 0
    ) -> ControllerSnapshot {
        ControllerSnapshot(leftStick: left, leftTrigger: lt, buttons: buttons)
    }

    private func armed() -> InputRouter {
        let r = InputRouter()
        _ = r.update(snap(), at: 0, mode: .desktop)
        return r
    }

    func testStickClickOpensKeyboardAndReleasesHeldClick() {
        let r = armed()
        XCTAssertEqual(
            r.update(snap([.a]), at: 0.1, mode: .desktop), [.mouseButton(.left, down: true)])
        XCTAssertEqual(
            r.update(snap([.a, .leftThumbstick]), at: 0.2, mode: .desktop),
            [.mouseButton(.left, down: false)])
        XCTAssertNotNil(r.keyboard)
        // A was already held when the keyboard opened: releasing it types nothing.
        XCTAssertEqual(r.update(snap([.leftThumbstick]), at: 0.3, mode: .desktop), [])
        XCTAssertEqual(r.update(snap(), at: 0.4, mode: .desktop), [])
    }

    func testTypingInTheKeyboard() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.1, mode: .desktop)
        _ = r.update(snap(), at: 0.2, mode: .desktop)
        var t = 0.2
        for degrees in stride(from: 0.0, through: 65, by: 5) {
            t += 0.01
            XCTAssertEqual(r.update(snap(left: stick(degrees)), at: t, mode: .desktop), [])
        }
        XCTAssertEqual(r.update(snap([.a]), at: 1, mode: .desktop), [.text("c")])
        XCTAssertEqual(r.update(snap([.a]), at: 2, mode: .desktop), [], "holding A does not repeat")
        _ = r.update(snap(), at: 2.1, mode: .desktop)
        XCTAssertEqual(r.update(snap([.a], lt: 1), at: 2.2, mode: .desktop), [.text("C")])
        XCTAssertEqual(
            r.update(snap([.x]), at: 2.3, mode: .desktop), [.keyTap(.space, modifiers: [])])
        XCTAssertEqual(
            r.update(snap([.y]), at: 2.4, mode: .desktop), [.keyTap(.returnKey, modifiers: [])])
        _ = r.update(snap([.dpadDown]), at: 2.5, mode: .desktop)
        XCTAssertEqual(r.keyboard?.page, .numbers)
    }

    func testBackspaceRepeatsWhileHeld() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.1, mode: .desktop)
        _ = r.update(snap(), at: 0.2, mode: .desktop)
        let backspace = OutputAction.keyTap(.delete, modifiers: [])
        XCTAssertEqual(r.update(snap([.b]), at: 1.0, mode: .desktop), [backspace])
        XCTAssertEqual(r.update(snap([.b]), at: 1.3, mode: .desktop), [])
        XCTAssertEqual(r.update(snap([.b]), at: 1.41, mode: .desktop), [backspace])
        XCTAssertEqual(r.update(snap([.b]), at: 1.45, mode: .desktop), [])
        XCTAssertEqual(r.update(snap([.b]), at: 1.52, mode: .desktop), [backspace])
        XCTAssertEqual(r.update(snap(), at: 1.6, mode: .desktop), [])
    }

    func testClosingKeyboardNeedsNeutralBeforeDesktop() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.1, mode: .desktop)
        _ = r.update(snap(), at: 0.2, mode: .desktop)
        _ = r.update(snap([.leftThumbstick]), at: 0.3, mode: .desktop)
        XCTAssertNil(r.keyboard)
        XCTAssertEqual(r.update(snap([.leftThumbstick, .a]), at: 0.4, mode: .desktop), [])
        _ = r.update(snap(), at: 0.5, mode: .desktop)
        XCTAssertEqual(
            r.update(snap([.a]), at: 0.6, mode: .desktop), [.mouseButton(.left, down: true)])
    }

    func testKeyboardRemembersSelectionBetweenOpens() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.1, mode: .desktop)
        _ = r.update(snap([.dpadRight]), at: 0.2, mode: .desktop)
        _ = r.update(snap([.leftThumbstick]), at: 0.3, mode: .desktop)
        _ = r.update(snap(), at: 0.4, mode: .desktop)
        _ = r.update(snap([.leftThumbstick]), at: 0.5, mode: .desktop)
        XCTAssertEqual(r.keyboard?.selectedCharacter, "b")
    }

    func testWheelRunsOneShortcutPerOpen() {
        let r = armed()
        XCTAssertEqual(r.update(snap([.rightShoulder]), at: 0.1, mode: .desktop), [])
        XCTAssertNotNil(r.wheel)
        _ = r.update(snap([.rightShoulder], left: Vec2(1, 0)), at: 0.2, mode: .desktop)
        XCTAssertEqual(
            r.update(snap([.rightShoulder, .a], left: Vec2(1, 0)), at: 0.3, mode: .desktop),
            [.keyTap(.v, modifiers: .command)])
        XCTAssertNil(r.wheel)
        _ = r.update(snap([.rightShoulder], left: Vec2(1, 0)), at: 0.4, mode: .desktop)
        XCTAssertEqual(
            r.update(snap([.rightShoulder, .a], left: Vec2(1, 0)), at: 0.5, mode: .desktop), [])
    }

    func testReleasingRBCancelsAndCentredStickRunsNothing() {
        let r = armed()
        _ = r.update(snap([.rightShoulder]), at: 0.1, mode: .desktop)
        XCTAssertEqual(r.update(snap([.rightShoulder, .a]), at: 0.2, mode: .desktop), [])
        _ = r.update(snap([.rightShoulder], left: Vec2(0, 1)), at: 0.3, mode: .desktop)
        XCTAssertEqual(r.update(snap(left: Vec2(0, 1)), at: 0.4, mode: .desktop), [])
        XCTAssertNil(r.wheel)
    }

    func testWheelOverKeyboardReturnsToKeyboard() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.1, mode: .desktop)
        _ = r.update(snap(), at: 0.2, mode: .desktop)
        _ = r.update(snap([.rightShoulder]), at: 0.3, mode: .desktop)
        XCTAssertNotNil(r.wheel)
        _ = r.update(snap(), at: 0.4, mode: .desktop)
        XCTAssertNil(r.wheel)
        XCTAssertNotNil(r.keyboard)
        XCTAssertEqual(r.update(snap([.a]), at: 0.5, mode: .desktop), [.text("a")])
    }

    func testLeavingDesktopClosesOverlays() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.1, mode: .desktop)
        XCTAssertEqual(r.update(snap([.a]), at: 0.2, mode: .native), [])
        XCTAssertNil(r.keyboard)
        _ = r.update(snap(), at: 0.3, mode: .desktop)
        XCTAssertNil(r.keyboard, "returning to Desktop does not reopen it")
    }

    func testPauseChordFiresOnceClosesKeyboardAndWorksWhilePaused() {
        let r = armed()
        _ = r.update(snap([.leftThumbstick]), at: 0.05, mode: .desktop)
        _ = r.update(snap(), at: 0.08, mode: .desktop)
        XCTAssertEqual(r.update(snap([.view, .menu]), at: 0.1, mode: .desktop), [])
        XCTAssertEqual(r.update(snap([.view, .menu]), at: 0.9, mode: .desktop), [])
        XCTAssertEqual(r.update(snap([.view, .menu]), at: 1.1, mode: .desktop), [.togglePause])
        XCTAssertNil(r.keyboard)
        XCTAssertEqual(r.update(snap([.view, .menu]), at: 2.5, mode: .paused), [])
        _ = r.update(snap(), at: 2.6, mode: .paused)
        _ = r.update(snap([.view, .menu]), at: 3.0, mode: .paused)
        XCTAssertEqual(r.update(snap([.view, .menu]), at: 4.0, mode: .paused), [.togglePause])
    }
}
