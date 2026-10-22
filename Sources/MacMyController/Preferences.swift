import Foundation
import MacMyControllerCore
import Observation
import ServiceManagement

/// User settings and saved per-app choices, stored locally in UserDefaults as one
/// versioned JSON blob. Nothing here leaves the Mac.
@MainActor
@Observable
final class Preferences {
    var settings: ControlSettings {
        didSet { changed() }
    }
    /// Saved per-app handoff choices by bundle ID. Missing means Automatic.
    private(set) var appChoices: [String: HandoffChoice] {
        didSet { changed() }
    }
    /// Display names for apps with saved choices, so the settings list is readable.
    private(set) var appNames: [String: String] {
        didSet { save() }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "preferences.v1"

    private struct Stored: Codable {
        var settings: ControlSettings
        var appChoices: [String: HandoffChoice]
        var appNames: [String: String]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            settings = stored.settings.clamped
            appChoices = stored.appChoices
            appNames = stored.appNames
        } else {
            settings = ControlSettings()
            appChoices = [:]
            appNames = [:]
        }
    }

    /// Saves a choice for an app, or returns it to Automatic when `choice` is nil.
    func setChoice(_ choice: HandoffChoice?, for bundleID: String, name: String) {
        if let choice {
            appNames[bundleID] = name
            appChoices[bundleID] = choice
        } else {
            appChoices[bundleID] = nil
            appNames[bundleID] = nil
        }
    }

    func resetSettings() { settings = ControlSettings() }

    func forgetAllApps() {
        appNames = [:]
        appChoices = [:]
    }

    private func changed() {
        save()
        onChange?()
    }

    private func save() {
        let stored = Stored(settings: settings, appChoices: appChoices, appNames: appNames)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.key) }
    }
}

/// Opt-in launch at login through the system Login Items list. Off unless the user
/// turns it on; removable from the app or from System Settings.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// True when registered, including when macOS is still waiting for approval.
    static var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
