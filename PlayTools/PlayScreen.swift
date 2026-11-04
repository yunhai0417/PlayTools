//
//  ScreenController.swift
//  PlayTools
//
import Foundation
import UIKit

let screen = PlayScreen.shared
let isInvertFixEnabled = PlaySettings.shared.inverseScreenValues && PlaySettings.shared.adaptiveDisplay
let mainScreenWidth =  !isInvertFixEnabled ? PlaySettings.shared.windowSizeWidth : PlaySettings.shared.windowSizeHeight
let mainScreenHeight = !isInvertFixEnabled ? PlaySettings.shared.windowSizeHeight : PlaySettings.shared.windowSizeWidth
let customScaler = PlaySettings.shared.customScaler

extension CGSize {
    func aspectRatio() -> CGFloat {
        if mainScreenWidth > mainScreenHeight {
            return mainScreenWidth / mainScreenHeight
        } else {
            return mainScreenHeight / mainScreenWidth
        }
    }

    func toAspectRatio() -> CGSize {
        if #available(iOS 16.3, *) {
            return CGSize(width: mainScreenWidth, height: mainScreenHeight)
        } else {
            return CGSize(width: mainScreenHeight, height: mainScreenWidth)
        }
    }

    func toAspectRatioInternal() -> CGSize {
        return CGSize(width: mainScreenHeight, height: mainScreenWidth)
    }
    func toAspectRatioDefault() -> CGSize {
        return CGSize(width: mainScreenHeight, height: mainScreenWidth)
    }
    func toAspectRatioInternalDefault() -> CGSize {
        return CGSize(width: mainScreenWidth, height: mainScreenHeight)
    }
}

extension CGRect {
    func aspectRatio() -> CGFloat {
        if mainScreenWidth > mainScreenHeight {
            return mainScreenWidth / mainScreenHeight
        } else {
            return mainScreenHeight / mainScreenWidth
        }
    }

    func toAspectRatio(_ multiplier: CGFloat = 1) -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenWidth * multiplier, height: mainScreenHeight * multiplier)
    }

    func toAspectRatioReversed() -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenHeight, height: mainScreenWidth)
    }
    func toAspectRatioDefault(_ multiplier: CGFloat = 1) -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenWidth * multiplier, height: mainScreenHeight * multiplier)
    }
    func toAspectRatioReversedDefault() -> CGRect {
        return CGRect(x: minX, y: minY, width: mainScreenHeight, height: mainScreenWidth)
    }
}

extension UIScreen {
    static var aspectRatio: CGFloat {
        let count = AKInterface.shared!.screenCount
        if PlaySettings.shared.notch {
            if count == 1 {
                return mainScreenWidth / mainScreenHeight // 1.6 or 1.77777778
            } else {
                if AKInterface.shared!.isMainScreenEqualToFirst {
                    return mainScreenWidth / mainScreenHeight
                }
            }

        }

        let frame = AKInterface.shared!.mainScreenFrame
        return frame.aspectRatio()
    }
}

public class PlayScreen: NSObject {
    @objc public static let shared = PlayScreen()

    func initialize() {
        if phoneWindowed {
            // Phone preset: everything (scene, UIScreen) reports the device's
            // logical screen, and the hosting NSWindow is enlarged afterwards
            // so the logical screen is simply zoomed on the Mac display.
            // (Cambrium does not render UIWindows that carry a transform,
            // so the old transform-based upscale is not usable.)
            NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil,
                queue: .main) { notification in
                if let window = notification.object as? UIWindow {
                    PlayScreen.applyPhoneWindowScale(window)
                }
            }
        }
        if resizable {
            // Remove default size restrictions
            NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil,
                queue: .main) { notification in
                if let window = notification.object as? UIWindow,
                   let windowScene = window.windowScene {
                    windowScene.sizeRestrictions?.minimumSize = CGSize(width: 0, height: 0)
                    windowScene.sizeRestrictions?.maximumSize = CGSize(width: .max, height: .max)
                }
            }
        }
    }

    /// Size of the screen in the device's logical points (852 x 393 for an
    /// iPhone 15 Pro landscape), independent of the enlarged Mac window.
    static var phoneLogicalSize: CGSize {
        let scale = CGFloat(PlaySettings.shared.phoneWindowScale)
        return CGSize(width: mainScreenWidth / scale, height: mainScreenHeight / scale)
    }

    /// Cambrium binds the host window content to ~0.77x the scene size, so
    /// the scene is reported pre-compensated: scene = logical / 0.77, which
    /// makes the host land exactly on the scaled-up phone window.
    static var phoneSceneSize: CGSize {
        let logical = phoneLogicalSize
        let compensation = CGFloat(PlaySettings.shared.phoneWindowScale) / 0.77009
        return CGSize(width: logical.width * compensation, height: logical.height * compensation)
    }

    /// Scene/display geometry for the phone preset: the UIKit scene is sized
    /// pre-compensated so Cambrium derives the enlarged host window.
    @objc public static func framePhone(_ rect: CGRect) -> CGRect {
        let scene = phoneSceneSize
        return CGRect(x: rect.minX, y: rect.minY, width: scene.width, height: scene.height)
    }

    @objc public static func sizePhone(_ size: CGSize) -> CGSize {
        return phoneSceneSize
    }

    /// Content size the host NSWindow should show for the phone preset
    /// (the scaled-up window: windowWidth x windowHeight points).
    @objc public static var phoneHostContentSize: CGSize {
        return CGSize(width: mainScreenWidth, height: mainScreenHeight)
    }

    // Phone preset: the app observes the device's logical screen regardless
    // of how big the (enlarged) window actually is on the Mac display.
    @objc public static func boundsPhone(_ rect: CGRect) -> CGRect {
        let logical = phoneLogicalSize
        return CGRect(x: rect.minX, y: rect.minY, width: logical.width, height: logical.height)
    }

    @objc public static func nativeBoundsPhone(_ rect: CGRect) -> CGRect {
        let logical = phoneLogicalSize
        return CGRect(x: rect.minX, y: rect.minY,
                      width: logical.width * CGFloat(customScaler),
                      height: logical.height * CGFloat(customScaler))
    }

    /// The scene is reported pre-compensated (phoneSceneSize), so Cambrium
    /// itself derives the enlarged host window. The window itself must keep
    /// an identity transform (Cambrium does not render transformed UIWindows),
    /// so the zoom is applied to the ROOT VIEW instead: it is sized to the
    /// device's logical screen (852 x 393) and scaled up by a plain CALayer
    /// transform, which Cambrium renders fine. Apps therefore lay out in the
    /// iPhone logical world while the content visually fills the window.
    @objc static func applyPhoneWindowScale(_ window: UIWindow) {
        guard PlaySettings.shared.phoneWindowScale > 1.0 else { return }
        window.transform = .identity
        guard let root = window.rootViewController?.view else { return }
        let logical = phoneLogicalSize
        guard window.bounds.width > 0, window.bounds.height > 0, logical.width > 0 else { return }
        // Only zoom windows whose aspect matches the preset's logical screen.
        // Old-lifecycle apps never receive the compensated scene size (their
        // window is self-determined with a different aspect), and zooming
        // their root view would break their own layout. Catalyst may report
        // the bounds portrait-swapped at didBecomeKey time, so compare
        // rotation-normalized aspects and derive the ratio from short sides.
        let windowAspect = Swift.max(window.bounds.width, window.bounds.height)
            / min(window.bounds.width, window.bounds.height)
        let logicalAspect = logical.width / logical.height
        guard abs(windowAspect - logicalAspect) < 0.02 else { return }
        let ratio = min(window.bounds.width, window.bounds.height) / min(logical.width, logical.height)
        guard ratio > 1.01 else { return }
        root.transform = .identity
        // Scale about the top-left corner so the zoomed view fills the window.
        root.layer.anchorPoint = CGPoint(x: 0, y: 0)
        root.frame = CGRect(origin: .zero, size: logical)
        root.transform = CGAffineTransform(scaleX: ratio, y: ratio)
    }

    @objc public static func frame(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioReversed()
    }

    @objc public static func bounds(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatio()
    }

    @objc public static func nativeBounds(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatio(CGFloat((customScaler)))
    }

    @objc public static func width(_ size: Int) -> Int {
        return size
    }

    @objc public static func height(_ size: Int) -> Int {
        return Int(size / Int(UIScreen.aspectRatio))
    }

    @objc public static func sizeAspectRatio(_ size: CGSize) -> CGSize {
        return size.toAspectRatio()
    }

    var fullscreen: Bool {
        return AKInterface.shared!.isFullscreen
    }

    var resizable: Bool {
        return PlaySettings.shared.resizableWindow
    }

    var phoneWindowed: Bool {
        return PlaySettings.shared.phoneWindowed
    }

    @objc public var screenRect: CGRect {
        return UIScreen.main.bounds
    }

    var width: CGFloat {
        screenRect.width
    }

    var height: CGFloat {
        screenRect.height
    }

    var max: CGFloat {
        Swift.max(width, height)
    }

    var percent: CGFloat {
        max / 100.0
    }

    var keyWindow: UIWindow? {
        return UIApplication
            .shared
            .connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .first { $0.isKeyWindow }
    }

    var windowScene: UIWindowScene? {
        window?.windowScene
    }

    var window: UIWindow? {
        return UIApplication.shared.connectedScenes
            .filter({$0.activationState == .foregroundActive})
            .compactMap({$0 as? UIWindowScene})
            .first?.windows
            .filter({$0.isKeyWindow}).first
    }

    var nsWindow: NSObject? {
        window?.nsWindow
    }

    func switchDock(_ visible: Bool) {
        AKInterface.shared!.setMenuBarVisible(visible)
    }

    // Default calculation
    @objc public static func frameReversedDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioReversedDefault()
    }
    @objc public static func frameDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioDefault()
    }
    @objc public static func boundsDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioDefault()
    }

    @objc public static func nativeBoundsDefault(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioDefault(CGFloat((customScaler)))
    }

    @objc public static func sizeAspectRatioDefault(_ size: CGSize) -> CGSize {
        return size.toAspectRatioDefault()
    }
    @objc public static func frameInternalDefault(_ rect: CGRect) -> CGRect {
            return rect.toAspectRatioDefault()
    }

    private static weak var cachedWindow: UIWindow?
    @objc public static func boundsResizable(_ rect: CGRect) -> CGRect {
        if cachedWindow == nil {
            cachedWindow = PlayScreen.shared.keyWindow
        }
        return cachedWindow?.bounds ?? rect
    }
}

extension CGFloat {
    var relativeY: CGFloat {
        self / screen.height
    }

    var relativeX: CGFloat {
        self / screen.width
    }

    var relativeSize: CGFloat {
        self / screen.percent
    }

    var absoluteSize: CGFloat {
        self * screen.percent
    }

    var absoluteX: CGFloat {
        self * screen.width
    }

    var absoluteY: CGFloat {
        self * screen.height
    }
}

extension UIWindow {
    var nsWindow: NSObject? {
        guard let nsWindows = NSClassFromString("NSApplication")?
            .value(forKeyPath: "sharedApplication.windows") as? [AnyObject] else { return nil }
        for nsWindow in nsWindows {
            let uiWindows = nsWindow.value(forKeyPath: "uiWindows") as? [UIWindow] ?? []
            if uiWindows.contains(self) {
                return nsWindow as? NSObject
            }
        }
        return nil
    }
}
