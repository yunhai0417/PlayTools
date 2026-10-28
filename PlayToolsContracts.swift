//
//  PlayToolsContracts.swift
//  PlayTools / AKInterface
//
//  Single source of truth for the App Settings plist schema, shared by the
//  PlayTools runtime and the AKInterface plugin bundle (OPTIMIZATION.md 3.1).
//  Pure Foundation; compiled into both targets (and PlayToolsTests).
//  Replace the former private AKAppSettingsData copy in AKPlugin.swift.
//

import Foundation

struct AppSettingsData: Codable {
    var keymapping = true
    var sensitivity: Float = 50

    var disableTimeout = false
    var iosDeviceModel = "iPad13,8"
    var windowWidth = 1920
    var windowHeight = 1080
    var customScaler = 2.0
    var resolution = 2
    var aspectRatio = 1
    var displayRotation = 0
    var notch = false
    var bypass = false
    var discordActivity = DiscordActivity()
    var version = "2.0.0"
    var playChain = false
    var playChainDebugging = false
    var inverseScreenValues = false
    var windowFixMethod = 0
    var rootWorkDir = true
    var noKMOnInput = false
    var enableScrollWheel = true
    var hideTitleBar = false
    var floatingWindow = false
    var checkMicPermissionSync = false
    var limitMotionUpdateFrequency = false
    var disableBuiltinMouse = false
    var resizableAspectRatioType = 0
    var resizableAspectRatioWidth = 0
    var resizableAspectRatioHeight = 0
    var blockSleepSpamming = false
    var ignoreUnityKeyboardInitializationError = false
    // Diagnostic switch: keeps only platform spoofing, skips all optional hooks,
    // PlayChain, UE path fixes, sleep throttling and user plugins. Default off.
    var safeMode = false

    // init(from:) below suppresses the synthesized default initializer.
    init() {}

    // Decode compatibility rule (OPTIMIZATION.md 3.2): older hosts write fewer
    // keys. Every key may be missing; present values win, absent ones keep
    // their defaults, so a partial plist never resets the whole settings set.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keymapping = try container.decodeIfPresent(Bool.self, forKey: .keymapping) ?? true
        sensitivity = try container.decodeIfPresent(Float.self, forKey: .sensitivity) ?? 50
        disableTimeout = try container.decodeIfPresent(Bool.self, forKey: .disableTimeout) ?? false
        iosDeviceModel = try container.decodeIfPresent(String.self, forKey: .iosDeviceModel) ?? "iPad13,8"
        windowWidth = try container.decodeIfPresent(Int.self, forKey: .windowWidth) ?? 1920
        windowHeight = try container.decodeIfPresent(Int.self, forKey: .windowHeight) ?? 1080
        customScaler = try container.decodeIfPresent(Double.self, forKey: .customScaler) ?? 2.0
        resolution = try container.decodeIfPresent(Int.self, forKey: .resolution) ?? 2
        aspectRatio = try container.decodeIfPresent(Int.self, forKey: .aspectRatio) ?? 1
        displayRotation = try container.decodeIfPresent(Int.self, forKey: .displayRotation) ?? 0
        notch = try container.decodeIfPresent(Bool.self, forKey: .notch) ?? false
        bypass = try container.decodeIfPresent(Bool.self, forKey: .bypass) ?? false
        discordActivity = (try? container.decodeIfPresent(DiscordActivity.self, forKey: .discordActivity))
            ?? DiscordActivity()
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "2.0.0"
        playChain = try container.decodeIfPresent(Bool.self, forKey: .playChain) ?? false
        playChainDebugging = try container.decodeIfPresent(Bool.self, forKey: .playChainDebugging) ?? false
        inverseScreenValues = try container.decodeIfPresent(Bool.self, forKey: .inverseScreenValues) ?? false
        windowFixMethod = try container.decodeIfPresent(Int.self, forKey: .windowFixMethod) ?? 0
        rootWorkDir = try container.decodeIfPresent(Bool.self, forKey: .rootWorkDir) ?? true
        noKMOnInput = try container.decodeIfPresent(Bool.self, forKey: .noKMOnInput) ?? false
        enableScrollWheel = try container.decodeIfPresent(Bool.self, forKey: .enableScrollWheel) ?? true
        hideTitleBar = try container.decodeIfPresent(Bool.self, forKey: .hideTitleBar) ?? false
        floatingWindow = try container.decodeIfPresent(Bool.self, forKey: .floatingWindow) ?? false
        checkMicPermissionSync = try container.decodeIfPresent(Bool.self, forKey: .checkMicPermissionSync) ?? false
        limitMotionUpdateFrequency = try container
            .decodeIfPresent(Bool.self, forKey: .limitMotionUpdateFrequency) ?? false
        disableBuiltinMouse = try container.decodeIfPresent(Bool.self, forKey: .disableBuiltinMouse) ?? false
        resizableAspectRatioType = try container
            .decodeIfPresent(Int.self, forKey: .resizableAspectRatioType) ?? 0
        resizableAspectRatioWidth = try container
            .decodeIfPresent(Int.self, forKey: .resizableAspectRatioWidth) ?? 0
        resizableAspectRatioHeight = try container
            .decodeIfPresent(Int.self, forKey: .resizableAspectRatioHeight) ?? 0
        blockSleepSpamming = try container.decodeIfPresent(Bool.self, forKey: .blockSleepSpamming) ?? false
        ignoreUnityKeyboardInitializationError = try container
            .decodeIfPresent(Bool.self, forKey: .ignoreUnityKeyboardInitializationError) ?? false
        safeMode = try container.decodeIfPresent(Bool.self, forKey: .safeMode) ?? false
    }
}
