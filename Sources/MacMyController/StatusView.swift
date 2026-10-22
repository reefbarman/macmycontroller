import MacMyControllerCore
import Observation
import SwiftUI

@MainActor
@Observable
final class StatusModel {
    var modeTitle = ""
    var modeDetail = ""
    var controllerName: String?
    var hasPermission = false
    var frontmostName: String?
    var frontmostBundleID: String?
    var isPaused = false
    var isArmed = false
    var snapshot = ControllerSnapshot.neutral
}

/// Status, the fixed controls and live diagnostics. Shows controller state and the
/// frontmost app only; never anything typed.
struct StatusView: View {
    let model: StatusModel
    let grantPermission: () -> Void

    private let controls: [(String, String)] = [
        ("Left stick", "Move the pointer"),
        ("Left trigger (hold)", "Precise, slower pointer"),
        ("Right stick", "Scroll"),
        ("A", "Left click (hold to drag)"),
        ("B", "Right click"),
        ("X", "Escape"),
        ("Y", "Return"),
        ("D-pad", "Arrow keys"),
        ("Left stick click", "Spiral keyboard (point the stick, A to type)"),
        ("RB (hold)", "Shortcut wheel (aim, A to run)"),
        ("View + Menu (hold 1 s)", "Pause or resume"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.modeTitle).font(.title2.bold())
                Text(model.modeDetail).foregroundStyle(.secondary)
            }

            if !model.hasPermission {
                HStack {
                    Text("MacMyController needs permission to control the mouse and keyboard.")
                    Spacer()
                    Button("Open Settings", action: grantPermission)
                }
                .padding(10)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

            GroupBox("Controls") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(controls, id: \.0) { control in
                        GridRow {
                            Text(control.0).bold()
                            Text(control.1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                Text(
                    "GeForce NOW gets the controller automatically. Use the menu bar icon to choose for the app in front."
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            GroupBox("Diagnostics") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    row("Controller", model.controllerName ?? "None")
                    row("Front app", model.frontmostName ?? "None")
                    row("Bundle ID", model.frontmostBundleID ?? "–")
                    row("Left stick", format(model.snapshot.leftStick))
                    row("Right stick", format(model.snapshot.rightStick))
                    row(
                        "Triggers",
                        String(
                            format: "LT %.2f  RT %.2f", model.snapshot.leftTrigger,
                            model.snapshot.rightTrigger))
                    row(
                        "Buttons",
                        model.snapshot.buttons.isEmpty
                            ? "–"
                            : model.snapshot.buttons.map(\.rawValue).sorted().joined(
                                separator: ", "))
                }
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                Text(
                    "Input from this window is ignored while it is focused, so the diagnostics stay live without clicking anything here."
                )
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func format(_ value: Vec2) -> String {
        String(format: "x %+.2f  y %+.2f", value.x, value.y)
    }
}
