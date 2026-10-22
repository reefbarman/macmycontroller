public enum BlockReason: Equatable, Sendable {
    case permissionMissing
    case noController
    case sessionInactive
    /// One of this app's own windows is focused. Output is suspended so the
    /// controller cannot click or type into our own settings.
    case ownAppActive
}

public enum OutputMode: Equatable, Sendable {
    /// The controller drives the mouse and keyboard.
    case desktop
    /// The frontmost app handles the controller itself; we generate nothing.
    case native
    /// The user paused desktop control.
    case paused
    case blocked(BlockReason)
}

public enum HandoffChoice: String, Equatable, Sendable, Codable, CaseIterable {
    case desktop
    case native
}

/// A temporary, explicit choice for one app. The caller clears it when a different
/// external app comes to the front or the app restarts.
public struct SessionOverride: Equatable, Sendable {
    public var bundleID: String
    public var choice: HandoffChoice

    public init(bundleID: String, choice: HandoffChoice) {
        self.bundleID = bundleID
        self.choice = choice
    }
}

public struct HandoffContext: Equatable, Sendable {
    public var hasPermission: Bool
    public var controllerConnected: Bool
    public var sessionActive: Bool
    public var manualPause: Bool
    public var ownAppFrontmost: Bool
    public var frontmostBundleID: String?
    public var sessionOverride: SessionOverride?
    /// Choices the user saved per app ("always use desktop controls in X").
    public var savedChoices: [String: HandoffChoice]
    public var nativeBundleIDs: Set<String>

    public init(
        hasPermission: Bool,
        controllerConnected: Bool,
        sessionActive: Bool,
        manualPause: Bool,
        ownAppFrontmost: Bool,
        frontmostBundleID: String?,
        sessionOverride: SessionOverride?,
        savedChoices: [String: HandoffChoice] = [:],
        nativeBundleIDs: Set<String> = KnownApps.nativeControllerBundleIDs
    ) {
        self.savedChoices = savedChoices
        self.hasPermission = hasPermission
        self.controllerConnected = controllerConnected
        self.sessionActive = sessionActive
        self.manualPause = manualPause
        self.ownAppFrontmost = ownAppFrontmost
        self.frontmostBundleID = frontmostBundleID
        self.sessionOverride = sessionOverride
        self.nativeBundleIDs = nativeBundleIDs
    }
}

public enum HandoffPolicy {
    /// Safety conditions first, then manual pause, then per-app choices: a temporary
    /// override beats a saved choice, which beats the built-in list. Unknown apps get
    /// desktop controls: we never guess controller support from fullscreen state.
    public static func mode(for context: HandoffContext) -> OutputMode {
        if !context.hasPermission { return .blocked(.permissionMissing) }
        if !context.controllerConnected { return .blocked(.noController) }
        if !context.sessionActive { return .blocked(.sessionInactive) }
        if context.manualPause { return .paused }
        if context.ownAppFrontmost { return .blocked(.ownAppActive) }

        guard let bundleID = context.frontmostBundleID else { return .desktop }
        if let override = context.sessionOverride, override.bundleID == bundleID {
            return override.choice == .native ? .native : .desktop
        }
        if let saved = context.savedChoices[bundleID] {
            return saved == .native ? .native : .desktop
        }
        return automaticChoice(for: bundleID, nativeBundleIDs: context.nativeBundleIDs) == .native
            ? .native : .desktop
    }

    /// What Automatic means for an app, without user choices.
    public static func automaticChoice(
        for bundleID: String,
        nativeBundleIDs: Set<String> = KnownApps.nativeControllerBundleIDs
    ) -> HandoffChoice {
        nativeBundleIDs.contains(bundleID) ? .native : .desktop
    }
}

public enum KnownApps {
    /// Only apps verified to handle a controller themselves.
    /// GeForce NOW: the main app (library, with gamepad navigation since 2.0.73) and its
    /// separate streamer app, which can be frontmost during a stream. IDs read from
    /// GeForceNOW.app on the Mac mini (macOS 27.0.1), October 2026.
    public static let nativeControllerBundleIDs: Set<String> = [
        "com.nvidia.gfnpc.mall",
        "com.nvidia.gfnpc.streamer",
    ]
}
