import CoreGraphics
import XCTest

@testable import MacMyControllerCore

final class StickMathTests: XCTestCase {
    func testInsideDeadzoneIsZero() {
        XCTAssertEqual(StickMath.applyRadialDeadzone(Vec2(0.1, 0.1), deadzone: 0.15), .zero)
    }

    func testRescalesFromDeadzoneEdge() {
        let full = StickMath.applyRadialDeadzone(Vec2(1, 0), deadzone: 0.15)
        XCTAssertEqual(full.x, 1, accuracy: 1e-9)
        let half = StickMath.applyRadialDeadzone(Vec2(0.575, 0), deadzone: 0.15)
        XCTAssertEqual(half.x, 0.5, accuracy: 1e-9)
    }

    func testDiagonalIsClampedToUnitLength() {
        let diagonal = StickMath.applyRadialDeadzone(Vec2(1, 1), deadzone: 0.15)
        XCTAssertEqual(diagonal.length, 1, accuracy: 1e-9)
    }
}

final class HandoffPolicyTests: XCTestCase {
    private func context(
        permission: Bool = true, controller: Bool = true, session: Bool = true,
        paused: Bool = false, ownApp: Bool = false, frontmost: String? = "com.apple.finder",
        override: SessionOverride? = nil
    ) -> HandoffContext {
        HandoffContext(
            hasPermission: permission, controllerConnected: controller, sessionActive: session,
            manualPause: paused, ownAppFrontmost: ownApp, frontmostBundleID: frontmost,
            sessionOverride: override)
    }

    func testSafetyConditionsComeFirst() {
        XCTAssertEqual(
            HandoffPolicy.mode(for: context(permission: false, paused: true)),
            .blocked(.permissionMissing))
        XCTAssertEqual(
            HandoffPolicy.mode(for: context(controller: false)), .blocked(.noController))
        XCTAssertEqual(
            HandoffPolicy.mode(for: context(session: false)), .blocked(.sessionInactive))
        XCTAssertEqual(
            HandoffPolicy.mode(
                for: context(
                    paused: true,
                    override: SessionOverride(bundleID: "com.apple.finder", choice: .desktop))),
            .paused)
    }

    func testOwnAppSuspendsOutput() {
        XCTAssertEqual(HandoffPolicy.mode(for: context(ownApp: true)), .blocked(.ownAppActive))
    }

    func testUnknownAppsGetDesktopAndGeForceNowIsNative() {
        XCTAssertEqual(HandoffPolicy.mode(for: context()), .desktop)
        XCTAssertEqual(
            HandoffPolicy.mode(for: context(frontmost: "com.nvidia.gfnpc.mall")), .native)
        XCTAssertEqual(
            HandoffPolicy.mode(for: context(frontmost: "com.nvidia.gfnpc.streamer")), .native)
    }

    func testOverrideOnlyAppliesToItsApp() {
        let toDesktop = SessionOverride(bundleID: "com.nvidia.gfnpc.mall", choice: .desktop)
        XCTAssertEqual(
            HandoffPolicy.mode(
                for: context(frontmost: "com.nvidia.gfnpc.mall", override: toDesktop)),
            .desktop)
        XCTAssertEqual(
            HandoffPolicy.mode(
                for: context(frontmost: "com.nvidia.gfnpc.streamer", override: toDesktop)),
            .native)
        let toNative = SessionOverride(bundleID: "com.apple.finder", choice: .native)
        XCTAssertEqual(HandoffPolicy.mode(for: context(override: toNative)), .native)
    }
}

final class SavedChoiceTests: XCTestCase {
    private func mode(
        _ app: String, saved: [String: HandoffChoice], override: SessionOverride? = nil
    )
        -> OutputMode
    {
        HandoffPolicy.mode(
            for: HandoffContext(
                hasPermission: true, controllerConnected: true, sessionActive: true,
                manualPause: false, ownAppFrontmost: false, frontmostBundleID: app,
                sessionOverride: override, savedChoices: saved))
    }

    func testSavedChoiceBeatsBuiltInList() {
        XCTAssertEqual(
            mode("com.nvidia.gfnpc.mall", saved: ["com.nvidia.gfnpc.mall": .desktop]), .desktop)
        XCTAssertEqual(mode("com.example.game", saved: ["com.example.game": .native]), .native)
        XCTAssertEqual(mode("com.example.other", saved: ["com.example.game": .native]), .desktop)
    }

    func testTemporaryOverrideBeatsSavedChoice() {
        XCTAssertEqual(
            mode(
                "com.example.game", saved: ["com.example.game": .native],
                override: SessionOverride(bundleID: "com.example.game", choice: .desktop)),
            .desktop)
    }

    func testAutomaticChoice() {
        XCTAssertEqual(HandoffPolicy.automaticChoice(for: "com.nvidia.gfnpc.streamer"), .native)
        XCTAssertEqual(HandoffPolicy.automaticChoice(for: "com.apple.finder"), .desktop)
    }
}

final class ControlSettingsTests: XCTestCase {
    func testDefaultsLeaveConfigUnchanged() {
        XCTAssertEqual(ControlSettings().applied(), MapperConfig())
    }

    func testSpeedsScaleAndClamp() {
        var settings = ControlSettings()
        settings.pointerSpeed = 2
        settings.scrollSpeed = 50
        settings.overlayScale = .nan
        let config = settings.applied()
        XCTAssertEqual(config.pointerMaxSpeed, MapperConfig().pointerMaxSpeed * 2)
        XCTAssertEqual(config.scrollMaxSpeed, MapperConfig().scrollMaxSpeed * 3)
        XCTAssertEqual(settings.clamped.overlayScale, 1)
    }

    func testRouterPassesConfigToDesktopMapper() {
        let router = InputRouter()
        var settings = ControlSettings()
        settings.pointerSpeed = 0.5
        router.config = settings.applied()
        XCTAssertEqual(router.desktop.config.pointerMaxSpeed, 900)
    }
}

final class DisplayGeometryTests: XCTestCase {
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let left = CGRect(x: -1280, y: 0, width: 1280, height: 1024)

    func testCrossesToAdjacentDisplay() {
        let p = DisplayGeometry.clamp(
            CGPoint(x: -10, y: 500), from: CGPoint(x: 5, y: 500), displays: [main, left])
        XCTAssertEqual(p, CGPoint(x: -10, y: 500))
    }

    func testClampsToCurrentDisplayEdge() {
        let p = DisplayGeometry.clamp(
            CGPoint(x: 2000, y: -20), from: CGPoint(x: 1900, y: 10), displays: [main, left])
        XCTAssertEqual(p, CGPoint(x: 1919, y: 0))
    }
}

final class DesktopMapperTests: XCTestCase {
    private func snap(
        _ buttons: Set<ControllerButton> = [], left: Vec2 = .zero, right: Vec2 = .zero,
        lt: Double = 0
    )
        -> ControllerSnapshot
    {
        ControllerSnapshot(leftStick: left, rightStick: right, leftTrigger: lt, buttons: buttons)
    }

    func testAPressAndReleaseIsOneClick() {
        let m = DesktopMapper()
        XCTAssertEqual(m.update(snap(), at: 0, mode: .desktop), [])
        XCTAssertEqual(
            m.update(snap([.a]), at: 0.01, mode: .desktop), [.mouseButton(.left, down: true)])
        XCTAssertEqual(m.update(snap([.a]), at: 0.02, mode: .desktop), [])
        XCTAssertEqual(
            m.update(snap(), at: 0.03, mode: .desktop), [.mouseButton(.left, down: false)])
    }

    func testRequiresNeutralBeforeArming() {
        let m = DesktopMapper()
        // Button already held when Desktop starts: ignored, including its release.
        XCTAssertEqual(m.update(snap([.a]), at: 0, mode: .desktop), [])
        XCTAssertFalse(m.isArmed)
        XCTAssertEqual(m.update(snap(), at: 0.01, mode: .desktop), [])
        XCTAssertTrue(m.isArmed)
        XCTAssertEqual(
            m.update(snap([.a]), at: 0.02, mode: .desktop), [.mouseButton(.left, down: true)])
    }

    func testLeavingDesktopReleasesHeldInputsAndDisarms() {
        let m = DesktopMapper()
        _ = m.update(snap(), at: 0, mode: .desktop)
        _ = m.update(snap([.a, .dpadUp]), at: 0.01, mode: .desktop)
        XCTAssertEqual(
            m.update(snap([.a, .dpadUp]), at: 0.02, mode: .native),
            [.mouseButton(.left, down: false), .key(.upArrow, down: false, isRepeat: false)])
        XCTAssertEqual(m.update(snap([.b], left: Vec2(1, 0)), at: 0.03, mode: .native), [])
        // Back to Desktop while input is still active: nothing until neutral.
        XCTAssertEqual(m.update(snap([.b], left: Vec2(1, 0)), at: 0.04, mode: .desktop), [])
        XCTAssertEqual(m.update(snap([], left: Vec2(1, 0)), at: 0.05, mode: .desktop), [])
        XCTAssertFalse(m.isArmed)
    }

    func testPointerIsTimeBasedAndDiagonalSpeedMatches() {
        let a = DesktopMapper()
        _ = a.update(snap(), at: 0, mode: .desktop)
        let one = a.update(snap(left: Vec2(1, 0)), at: 0.02, mode: .desktop)
        XCTAssertEqual(one, [.pointerMove(dx: 36, dy: 0)])  // 1800 pt/s * 0.02 s

        let b = DesktopMapper()
        _ = b.update(snap(), at: 0, mode: .desktop)
        var total = 0
        for i in 1...4 {
            for case .pointerMove(let dx, _) in b.update(
                snap(left: Vec2(1, 0)), at: Double(i) * 0.005, mode: .desktop)
            {
                total += dx
            }
        }
        XCTAssertEqual(total, 36)

        let c = DesktopMapper()
        _ = c.update(snap(), at: 0, mode: .desktop)
        guard
            case .pointerMove(let dx, let dy)? = c.update(
                snap(left: Vec2(1, 1)), at: 0.02, mode: .desktop
            ).first
        else { return XCTFail("expected movement") }
        XCTAssertEqual((Double(dx * dx + dy * dy)).squareRoot(), 36, accuracy: 1.5)
        XCTAssertLessThan(dy, 0, "stick up moves the pointer up")
    }

    func testPrecisionTriggerSlowsPointer() {
        let m = DesktopMapper()
        _ = m.update(snap(), at: 0, mode: .desktop)
        XCTAssertEqual(
            m.update(snap(left: Vec2(1, 0), lt: 1), at: 0.02, mode: .desktop),
            [.pointerMove(dx: 10, dy: 0)])  // 36 * 0.3 = 10.8, remainder carried
    }

    func testRightStickScrolls() {
        let m = DesktopMapper()
        _ = m.update(snap(), at: 0, mode: .desktop)
        XCTAssertEqual(
            m.update(snap(right: Vec2(0, 1)), at: 0.02, mode: .desktop),
            [.scroll(vertical: 30, horizontal: 0)])
    }

    func testDpadRepeats() {
        let m = DesktopMapper()
        _ = m.update(snap(), at: 0, mode: .desktop)
        XCTAssertEqual(
            m.update(snap([.dpadDown]), at: 1.0, mode: .desktop),
            [.key(.downArrow, down: true, isRepeat: false)])
        XCTAssertEqual(m.update(snap([.dpadDown]), at: 1.3, mode: .desktop), [])
        XCTAssertEqual(
            m.update(snap([.dpadDown]), at: 1.41, mode: .desktop),
            [.key(.downArrow, down: true, isRepeat: true)])
        XCTAssertEqual(
            m.update(snap(), at: 1.42, mode: .desktop),
            [.key(.downArrow, down: false, isRepeat: false)])
    }

    func testNativeModeProducesNothingAndIgnoresChord() {
        let m = DesktopMapper()
        _ = m.update(snap(), at: 0, mode: .native)
        XCTAssertEqual(
            m.update(snap([.a, .view, .menu], left: Vec2(1, 0)), at: 0.5, mode: .native), [])
        XCTAssertEqual(
            m.update(snap([.a, .view, .menu], left: Vec2(1, 0)), at: 2, mode: .native), [])
    }

    func testNeedsTicksOnlyWhenActive() {
        let m = DesktopMapper()
        XCTAssertFalse(m.needsTicks(snap(left: Vec2(0.05, 0))))
        XCTAssertTrue(m.needsTicks(snap(left: Vec2(0.5, 0))))
        XCTAssertTrue(m.needsTicks(snap([.x])))
    }
}
