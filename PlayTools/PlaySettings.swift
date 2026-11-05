import Foundation
import UIKit

let settings = PlaySettings.shared

@objc public final class PlaySettings: NSObject {
    @objc public static let shared = PlaySettings()

    let bundleIdentifier = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String ?? ""
    let settingsUrl: URL
    var settingsData: AppSettingsData

    override init() {
        settingsUrl = URL(fileURLWithPath: "/Users/\(NSUserName())/Library/Containers/io.playcover.PlayCover")
            .appendingPathComponent("App Settings")
            .appendingPathComponent("\(bundleIdentifier).plist")
        do {
            let data = try Data(contentsOf: settingsUrl)
            settingsData = try PropertyListDecoder().decode(AppSettingsData.self, from: data)
        } catch {
            settingsData = AppSettingsData()
            print("[PlayTools] PlaySettings decode failed.\n%@")
        }
    }

    lazy var discordActivity = settingsData.discordActivity

    lazy var keymapping = settingsData.keymapping

    lazy var notch = settingsData.notch

    lazy var sensitivity = settingsData.sensitivity / 100

    @objc lazy var bypass = settingsData.bypass

    @objc lazy var windowSizeHeight = CGFloat(settingsData.windowHeight)

    @objc lazy var windowSizeWidth = CGFloat(settingsData.windowWidth)

    @objc lazy var inverseScreenValues = settingsData.inverseScreenValues

    @objc lazy var adaptiveDisplay = settingsData.resolution == 0 ? false : true

    @objc lazy var resizableWindow = settingsData.resolution == 6 ? true : false

    @objc lazy var deviceModel = settingsData.iosDeviceModel as NSString

    @objc lazy var oemID: NSString = {
        switch settingsData.iosDeviceModel {
        case "iPad6,7":
            return "J98aAP"
        case "iPad8,6":
            return "J320xAP"
        case "iPad13,8":
            return "J522AP"
        case "iPad14,5":
            return "A2436"
        case "iPad16,6":
            return "A2925"
        case "iPhone14,3":
            return "A2645"
        case "iPhone15,3":
            return "A2896"
        case "iPhone16,2":
            return "A2849"
        case "iPhone17,2":
            return "A3084"
        default:
            return "J320xAP"
        }
    }()

    @objc lazy var playChain = settingsData.playChain

    @objc lazy var playChainDebugging = settingsData.playChainDebugging

    @objc lazy var windowFixMethod = settingsData.windowFixMethod

    @objc lazy var customScaler = settingsData.customScaler

    @objc lazy var rootWorkDir = settingsData.rootWorkDir

    @objc lazy var noKMOnInput = settingsData.noKMOnInput

    @objc lazy var enableScrollWheel = settingsData.enableScrollWheel

    @objc lazy var hideTitleBar = settingsData.hideTitleBar

    @objc lazy var floatingWindow = settingsData.floatingWindow

    @objc lazy var displayRotation = settingsData.displayRotation

    @objc lazy var checkMicPermissionSync = settingsData.checkMicPermissionSync

    @objc lazy var limitMotionUpdateFrequency = settingsData.limitMotionUpdateFrequency

    @objc lazy var disableBuiltinMouse = settingsData.disableBuiltinMouse

    @objc lazy var blockSleepSpamming = settingsData.blockSleepSpamming

    @objc lazy var ignoreUnityKeyboardInitializationError = settingsData.ignoreUnityKeyboardInitializationError

    // Phone preset (resolution == 7): window may be scaled up while the app
    // keeps observing the device's logical screen (bounds/nativeBounds).
    // Optional so plists written before this field existed still decode.
    @objc lazy var phoneWindowScale: Double = {
        if settingsData.resolution == 7 {
            return settingsData.phoneWindowScale ?? 1.0
        }
        // Default resolution (mode 0) with an iPhone model: the plist window
        // size is the device logical screen at scale 1.0 when freshly set by
        // PlayCover, but stale plists may carry any size — derive the scale
        // from the short sides so the app always observes the device screen.
        if settingsData.resolution == 0,
           let logical = PlaySettings.phoneDeviceLogicalSize(settingsData.iosDeviceModel) {
            let windowShort = min(Double(settingsData.windowWidth), Double(settingsData.windowHeight))
            let logicalShort = min(Double(logical.width), Double(logical.height))
            if logicalShort > 0, windowShort > 0 {
                return windowShort / logicalShort
            }
        }
        return settingsData.phoneWindowScale ?? 1.0
    }()

    @objc lazy var phoneWindowed = (settingsData.resolution == 7 && phoneWindowScale > 1.0)
        || (settingsData.resolution == 0
            && PlaySettings.phoneDeviceLogicalSize(settingsData.iosDeviceModel) != nil)

    // Apps without a UIApplicationSceneManifest (old lifecycle) have no real
    // scene session: Catalyst syncs their UIWindow directly to the (hooked)
    // FBSSceneSettings size. For those, the window is clamped to the device
    // logical screen instead of zooming views (see PlayScreen).
    @objc lazy var legacyLifecycle = Bundle.main.infoDictionary?["UIApplicationSceneManifest"] == nil

    /// Logical screen size (portrait orientation, in points) of the supported
    /// iPhone models; nil for iPads and unknown identifiers. Apps running in
    /// the phone preset observe exactly this screen regardless of window size.
    static func phoneDeviceLogicalSize(_ model: String) -> CGSize? {
        switch model {
        case "iPhone14,3":
            return CGSize(width: 428, height: 926)
        case "iPhone15,3", "iPhone16,2":
            return CGSize(width: 430, height: 932)
        case "iPhone17,2":
            return CGSize(width: 440, height: 956)
        default:
            return nil
        }
    }
}

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
    var phoneWindowScale: Double?
}
