import AppKit

/// Tracks the frontmost app and whether the user session is usable.
@MainActor
final class AppContextMonitor {
    struct FrontApp: Equatable {
        var bundleID: String?
        var name: String
        var pid: pid_t
    }

    /// Called after any change. `externalAppChanged` is true when a different app
    /// (not this one) came to the front, which expires temporary per-app choices.
    var onChange: ((_ externalAppChanged: Bool) -> Void)?

    private(set) var frontmost: FrontApp?
    private(set) var lastExternal: FrontApp?
    private(set) var sessionActive = true
    private(set) var asleep = false

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var observers: [NSObjectProtocol] = []

    var ownAppFrontmost: Bool { frontmost?.pid == ownPID }
    var isUsable: Bool { sessionActive && !asleep }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.setFrontmost(app)
        }
        observe(center, NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in
            self?.sessionActive = false
            self?.onChange?(false)
        }
        observe(center, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in
            self?.sessionActive = true
            self?.onChange?(false)
        }
        observe(center, NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.asleep = true
            self?.onChange?(false)
        }
        observe(center, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.asleep = false
            self?.onChange?(false)
        }
        setFrontmost(NSWorkspace.shared.frontmostApplication)
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name,
        _ handler: @escaping @MainActor (Notification) -> Void
    ) {
        observers.append(
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            })
    }

    private func setFrontmost(_ app: NSRunningApplication?) {
        guard let app else {
            frontmost = nil
            onChange?(false)
            return
        }
        let front = FrontApp(
            bundleID: app.bundleIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown app",
            pid: app.processIdentifier)
        frontmost = front

        var externalChanged = false
        if front.pid != ownPID {
            externalChanged = lastExternal?.pid != front.pid
            lastExternal = front
        }
        onChange?(externalChanged)
    }
}
