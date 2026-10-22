import AppKit
import MacMyControllerCore
import QuartzCore
import SwiftUI

/// Wires controller input, foreground-app policy and event output together. All state
/// lives on the main actor, so a mode change and the next posted event can never race.
@MainActor
final class AppCoordinator: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let controllers = ControllerService()
    private let context = AppContextMonitor()
    private let emitter = EventEmitter()
    private let router = InputRouter()
    private let overlay = OverlayController()
    let status = StatusModel()
    let preferences = Preferences()

    private var manualPause = false
    private var sessionOverride: SessionOverride?
    private var hasPermission = Permissions.canPostEvents
    private(set) var mode: OutputMode = .blocked(.noController)

    private var statusItem: NSStatusItem?
    private var tickTimer: Timer?
    private var permissionTimer: Timer?
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    /// The app the menu was opened for, so menu actions apply to what the user saw.
    private var menuApp: AppContextMonitor.FrontApp?

    func start() {
        applyPreferences()
        preferences.onChange = { [weak self] in self?.applyPreferences() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        controllers.onConnectionChange = { [weak self] in self?.refreshMode() }
        controllers.onInput = { [weak self] in self?.step() }
        context.onChange = { [weak self] externalAppChanged in
            if externalAppChanged { self?.sessionOverride = nil }
            self?.refreshMode()
        }

        controllers.start()
        context.start()

        if !hasPermission { Permissions.request() }
        // Cheap check that also notices the permission being revoked while running.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer

        refreshMode()

        let shownKey = "hasShownWelcome"
        if !UserDefaults.standard.bool(forKey: shownKey) || !hasPermission {
            UserDefaults.standard.set(true, forKey: shownKey)
            showWindow()
        }
    }

    /// Releases any synthetic input we still hold. Called on quit.
    func shutdown() {
        for action in router.releaseAll() { emitter.perform(action) }
        overlay.hide()
        stopTicks()
    }

    // MARK: - State

    private func applyPreferences() {
        router.config = preferences.settings.applied()
        overlay.scale = preferences.settings.clamped.overlayScale
        refreshMode()
    }

    private func checkPermission() {
        let now = Permissions.canPostEvents
        guard now != hasPermission else { return }
        hasPermission = now
        refreshMode()
    }

    private func refreshMode() {
        let newMode = HandoffPolicy.mode(
            for: HandoffContext(
                hasPermission: hasPermission,
                controllerConnected: controllers.isConnected,
                sessionActive: context.isUsable,
                manualPause: manualPause,
                ownAppFrontmost: context.ownAppFrontmost,
                frontmostBundleID: context.frontmost?.bundleID,
                sessionOverride: sessionOverride,
                savedChoices: preferences.appChoices))
        if newMode != mode {
            mode = newMode
            step()
        }
        updateStatus()
    }

    private func togglePause() {
        manualPause.toggle()
        refreshMode()
    }

    /// Feeds the current controller state through the mapper and posts the result.
    private func step() {
        let snapshot = controllers.snapshot
        let actions = router.update(snapshot, at: CACurrentMediaTime(), mode: mode)

        var shouldTogglePause = false
        for action in actions {
            if action == .togglePause {
                shouldTogglePause = true
            } else if mode == .desktop || action.isRelease {
                emitter.perform(action)
            }
        }

        overlay.update(keyboard: router.keyboard, wheel: router.wheel)

        let wantsTicks = (mode == .desktop || mode == .paused) && router.needsTicks(snapshot)
        if wantsTicks { startTicks() } else { stopTicks() }

        if window?.isVisible == true {
            status.snapshot = snapshot
            status.isArmed = router.desktop.isArmed
        }
        if shouldTogglePause { togglePause() }
    }

    private func startTicks() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicks() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Presentation

    private func updateStatus() {
        let presentation = ModePresentation(mode: mode, appName: context.frontmost?.name)
        status.modeTitle = presentation.title
        status.modeDetail = presentation.detail
        status.controllerName = controllers.displayName
        status.hasPermission = hasPermission
        status.frontmostName = context.frontmost?.name
        status.frontmostBundleID = context.frontmost?.bundleID
        status.isPaused = manualPause

        if let button = statusItem?.button {
            let image = NSImage(
                systemSymbolName: presentation.symbol, accessibilityDescription: presentation.title)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MacMyController: \(presentation.title)"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let presentation = ModePresentation(mode: mode, appName: context.frontmost?.name)

        menu.addItem(disabled(presentation.title))
        menu.addItem(
            disabled(
                controllers.displayName.map { "Controller: \($0)" } ?? "No controller connected"))
        menu.addItem(.separator())

        if !hasPermission {
            menu.addItem(item("Grant Permission…", #selector(grantPermission)))
        }

        menu.addItem(
            item(
                manualPause ? "Resume Controller Mouse" : "Pause Controller Mouse",
                #selector(menuTogglePause)))

        menuApp = context.lastExternal
        if let app = menuApp, let bundleID = app.bundleID {
            menu.addItem(.separator())
            menu.addItem(disabled("In \(app.name)"))

            let saved = preferences.appChoices[bundleID]
            let automatic =
                HandoffPolicy.automaticChoice(for: bundleID) == .native
                ? "controller goes to the app" : "desktop controls"
            let choices: [(String, Selector, Bool)] = [
                ("Automatic (\(automatic))", #selector(saveAutomatic), saved == nil),
                ("Always Use Desktop Controls", #selector(saveDesktop), saved == .desktop),
                ("Always Hand Controller to \(app.name)", #selector(saveNative), saved == .native),
            ]
            for (title, action, isOn) in choices {
                let menuItem = item(title, action)
                menuItem.state = isOn ? .on : .off
                menu.addItem(menuItem)
            }

            if !manualPause {
                if let override = sessionOverride, override.bundleID == bundleID {
                    menu.addItem(item("End Temporary Choice", #selector(clearOverride)))
                } else if mode == .native {
                    menu.addItem(item("Use Desktop Controls for Now", #selector(overrideDesktop)))
                } else if mode == .desktop {
                    menu.addItem(item("Hand Controller to App for Now", #selector(overrideNative)))
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Status and Controls…", #selector(openWindow)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit MacMyController", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    @objc private func grantPermission() {
        Permissions.request()
        Permissions.openSettings()
    }

    @objc private func menuTogglePause() { togglePause() }

    @objc private func overrideDesktop() { setOverride(.desktop) }
    @objc private func overrideNative() { setOverride(.native) }

    @objc private func clearOverride() {
        sessionOverride = nil
        refreshMode()
    }

    private func setOverride(_ choice: HandoffChoice) {
        guard let bundleID = menuApp?.bundleID else { return }
        sessionOverride = SessionOverride(bundleID: bundleID, choice: choice)
        refreshMode()
    }

    @objc private func saveAutomatic() { saveChoice(nil) }
    @objc private func saveDesktop() { saveChoice(.desktop) }
    @objc private func saveNative() { saveChoice(.native) }

    /// A saved choice replaces any temporary one for the same app, so the result is
    /// visible straight away.
    private func saveChoice(_ choice: HandoffChoice?) {
        guard let app = menuApp, let bundleID = app.bundleID else { return }
        if sessionOverride?.bundleID == bundleID { sessionOverride = nil }
        preferences.setChoice(choice, for: bundleID, name: app.name)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(preferences: preferences))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "MacMyController Settings"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            settingsWindow = newWindow
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openWindow() { showWindow() }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: StatusView(
                    model: status,
                    grantPermission: { [weak self] in self?.grantPermission() }))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "MacMyController"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
        }
        status.snapshot = controllers.snapshot
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ModePresentation {
    let title: String
    let detail: String
    let symbol: String

    init(mode: OutputMode, appName: String?) {
        let app = appName ?? "this app"
        switch mode {
        case .desktop:
            title = "Desktop controls"
            detail = "The controller moves the mouse in \(app)."
            symbol = "cursorarrow.motionlines"
        case .native:
            title = "Native controller"
            detail = "\(app) handles the controller itself. MacMyController sends nothing."
            symbol = "gamecontroller.fill"
        case .paused:
            title = "Paused"
            detail = "Hold View + Menu for 1 second, or use the menu bar, to resume."
            symbol = "pause.circle"
        case .blocked(.permissionMissing):
            title = "Permission required"
            detail =
                "Allow MacMyController under Privacy & Security → Accessibility (Device Control and Data Access on macOS 27)."
            symbol = "exclamationmark.triangle"
        case .blocked(.noController):
            title = "Controller disconnected"
            detail = "Pair or turn on an Xbox controller to start."
            symbol = "gamecontroller"
        case .blocked(.sessionInactive):
            title = "Waiting for your session"
            detail = "Controls resume when the Mac is awake and your session is active."
            symbol = "moon.zzz"
        case .blocked(.ownAppActive):
            title = "Suspended while this window is focused"
            detail = "Switch to another app to use desktop controls."
            symbol = "cursorarrow.slash"
        }
    }
}
