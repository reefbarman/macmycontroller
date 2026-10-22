import AppKit
import MacMyControllerCore
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayModel {
    var keyboard: SpiralKeyboard?
    var wheel: ShortcutWheel?
    var scale = 1.0
}

/// Never becomes key or main, so the app you are typing into keeps focus.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the spiral keyboard or shortcut wheel in a floating, click-through,
/// nonactivating panel on the screen that has the pointer.
@MainActor
final class OverlayController {
    static let size = NSSize(width: 600, height: 680)

    private let model = OverlayModel()
    private var panel: OverlayPanel?

    private struct KeyboardDisplay: Equatable {
        var page: SpiralKeyboard.Page
        var position: Int
        var uppercase: Bool
    }
    private var shownKeyboard: KeyboardDisplay?
    private var shownWheel: ShortcutWheel?
    private var isVisible = false

    /// Overlay size multiplier from settings. Applied the next time it opens.
    var scale: Double {
        get { model.scale }
        set { if newValue != model.scale { model.scale = newValue } }
    }

    private var scaledSize: NSSize {
        NSSize(width: Self.size.width * scale, height: Self.size.height * scale)
    }

    /// Called after every input step. Only touches SwiftUI when something visible changed.
    func update(keyboard: SpiralKeyboard?, wheel: ShortcutWheel?) {
        let display = keyboard.map {
            KeyboardDisplay(page: $0.page, position: $0.position, uppercase: $0.uppercase)
        }
        if display != shownKeyboard {
            shownKeyboard = display
            model.keyboard = keyboard
        }
        if wheel != shownWheel {
            shownWheel = wheel
            model.wheel = wheel
        }

        let visible = keyboard != nil || wheel != nil
        guard visible != isVisible else { return }
        isVisible = visible
        if visible { show() } else { panel?.orderOut(nil) }
    }

    func hide() { update(keyboard: nil, wheel: nil) }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = scaledSize
            let origin = NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + max((frame.height - size.height) * 0.25, 0))
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> OverlayPanel {
        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
        ]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        return panel
    }
}

// MARK: - Views

private let highlight = Color(red: 1, green: 0.8, blue: 0.2)

struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        Group {
            if let wheel = model.wheel {
                WheelView(wheel: wheel)
            } else if let keyboard = model.keyboard {
                SpiralView(keyboard: keyboard)
            }
        }
        .frame(width: OverlayController.size.width, height: OverlayController.size.height)
        .scaleEffect(model.scale)
        .frame(
            width: OverlayController.size.width * model.scale,
            height: OverlayController.size.height * model.scale)
    }
}

/// An endless coil seen from above, drawn around the current position. The lap you are
/// on always sits on the bright middle ring; characters ahead wind outwards and those
/// behind wind inwards, shrinking and fading with distance. Because the coil never
/// restarts, z leads straight on to a with no jump.
struct SpiralView: View {
    let keyboard: SpiralKeyboard

    static let ringRadius = 178.0
    /// How far the coil moves outwards per character.
    static let pitch = 7.5

    var body: some View {
        let count = keyboard.characters.count
        // Show at most one copy of each character.
        let reach = min(12, (count - 1) / 2)
        let current = keyboard.position
        VStack(spacing: 14) {
            ZStack {
                ForEach(-reach...reach, id: \.self) { distance in
                    let fade = Double(abs(distance))
                    SpiralSegment(center: Double(current), distance: Double(distance))
                        .stroke(
                            .white.opacity(max(0.03, 0.16 * (1 - fade * 0.075))),
                            style: StrokeStyle(
                                lineWidth: 50 * max(0.45, 1 - fade * 0.05), lineCap: .butt))
                }
                ForEach(Array((current - reach)...(current + reach)), id: \.self) { position in
                    let distance = position - current
                    let isSelected = distance == 0
                    let fade = Double(abs(distance))
                    Text(keyboard.character(at: position))
                        .font(
                            .system(
                                size: isSelected ? 34 : 24, weight: isSelected ? .heavy : .semibold,
                                design: .rounded)
                        )
                        .foregroundStyle(isSelected ? Color.black : .white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(isSelected ? highlight : .clear))
                        .scaleEffect(isSelected ? 1.15 : max(0.45, 1 - fade * 0.05))
                        .opacity(isSelected ? 1 : max(0.12, 1 - fade * 0.075))
                        .offset(Self.offset(position, distance: distance))
                        .zIndex(isSelected ? 1 : -fade)
                }
                VStack(spacing: 2) {
                    Text(keyboard.selectedCharacter)
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .foregroundStyle(highlight)
                    Text(keyboard.page.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 560, height: 540)
            .animation(.spring(duration: 0.18), value: current)
            Legend(items: [
                ("A", "Type"), ("B", "Delete"), ("X", "Space"), ("Y", "Return"),
                ("LT", "Caps"), ("D-pad ↑↓", "Page"), ("D-pad ←→", "Nudge"),
                ("L-stick", "Close"), ("RB", "Shortcuts"),
            ])
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 32).fill(.black.opacity(0.85)))
    }

    static func point(position: Double, distance: Double, around center: CGPoint) -> CGPoint {
        let step = 2 * Double.pi / Double(SpiralKeyboard.stepsPerRevolution)
        let angle = position * step
        let radius = ringRadius + distance * pitch
        return CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    /// Direction matches the stick: position × 30°, clockwise from the top. Distance
    /// from the current position sets how far in or out along the coil it sits.
    static func offset(_ position: Int, distance: Int) -> CGSize {
        let step = 2 * Double.pi / Double(SpiralKeyboard.stepsPerRevolution)
        let angle = Double(position) * step
        let radius = ringRadius + Double(distance) * pitch
        return CGSize(width: radius * sin(angle), height: -radius * cos(angle))
    }
}

/// One character's worth of the coil band behind the letters. Its centre animates with
/// the selection, so the band glides along with the letters instead of jumping.
struct SpiralSegment: Shape {
    var center: Double
    let distance: Double

    var animatableData: Double {
        get { center }
        set { center = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        let samples = 10
        var path = Path()
        for sample in 0...samples {
            let d = distance - 0.5 + Double(sample) / Double(samples)
            let point = SpiralView.point(position: center + d, distance: d, around: middle)
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

struct WheelView: View {
    let wheel: ShortcutWheel

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(Shortcuts.wheel.indices, id: \.self) { index in
                    let shortcut = Shortcuts.wheel[index]
                    let isSelected = wheel.highlighted == index
                    let angle = Double(index) * Double.pi / 4
                    VStack(spacing: 6) {
                        Image(systemName: shortcut.symbol).font(
                            .system(size: 28, weight: .semibold))
                        Text(shortcut.title).font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Color.black : .white)
                    .frame(width: 120, height: 84)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected ? highlight : .white.opacity(0.08))
                    )
                    .offset(x: 190 * sin(angle), y: -190 * cos(angle))
                }
                VStack(spacing: 4) {
                    Text(wheel.selected?.title ?? "Aim with the left stick")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(wheel.selected == nil ? .white.opacity(0.6) : highlight)
                }
            }
            .frame(width: 560, height: 540)
            Legend(items: [("A", "Run"), ("Release RB", "Cancel")])
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 32).fill(.black.opacity(0.85)))
    }
}

struct Legend: View {
    let items: [(String, String)]

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 5).map {
            Array(items[$0..<min($0 + 5, items.count)])
        }
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(rows[row].indices, id: \.self) { index in
                        HStack(spacing: 5) {
                            Text(rows[row][index].0)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.85)))
                            Text(rows[row][index].1)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
            }
        }
    }
}
