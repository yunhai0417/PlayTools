//
//  ScreenController.swift
//  PlayTools
//
import Foundation
import UIKit

let screen = PlayScreen.shared

/// Geometry snapshot built once from PlaySettings (lazy global, mirroring the
/// former top-level mainScreenWidth/mainScreenHeight/customScaler lets).
/// Inverse mode (inverseScreenValues && adaptiveDisplay) feeds the configured
/// size pre-swapped, exactly like the old ternaries did.
private func buildScreenGeometry() -> ScreenGeometry {
    let settings = PlaySettings.shared
    let inverse = settings.inverseScreenValues && settings.adaptiveDisplay
    return ScreenGeometry(
        width: inverse ? settings.windowSizeHeight : settings.windowSizeWidth,
        height: inverse ? settings.windowSizeWidth : settings.windowSizeHeight,
        scaler: settings.customScaler)
}

let screenGeometry = buildScreenGeometry()

extension CGSize {
    func aspectRatio() -> CGFloat {
        screenGeometry.aspectRatio
    }

    func toAspectRatio() -> CGSize {
        if #available(iOS 16.3, *) {
            return screenGeometry.size
        } else {
            return screenGeometry.sizeReversed
        }
    }

    func toAspectRatioInternal() -> CGSize {
        return screenGeometry.sizeReversed
    }
    func toAspectRatioDefault() -> CGSize {
        return screenGeometry.sizeReversed
    }
    func toAspectRatioInternalDefault() -> CGSize {
        return screenGeometry.size
    }
}

extension CGRect {
    func aspectRatio() -> CGFloat {
        screenGeometry.aspectRatio
    }

    func toAspectRatio(_ multiplier: CGFloat = 1) -> CGRect {
        return screenGeometry.rect(self, multiplier: multiplier)
    }

    func toAspectRatioReversed() -> CGRect {
        return screenGeometry.rectReversed(self)
    }
    func toAspectRatioDefault(_ multiplier: CGFloat = 1) -> CGRect {
        return screenGeometry.rect(self, multiplier: multiplier)
    }
    func toAspectRatioReversedDefault() -> CGRect {
        return screenGeometry.rectReversed(self)
    }
}

extension UIScreen {
    static var aspectRatio: CGFloat {
        let count = AKInterface.shared!.screenCount
        if PlaySettings.shared.notch {
            if count == 1 {
                return screenGeometry.aspectRatio // 1.6 or 1.77777778
            } else {
                if AKInterface.shared!.isMainScreenEqualToFirst {
                    return screenGeometry.aspectRatio
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

    @objc public static func frame(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatioReversed()
    }

    @objc public static func bounds(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatio()
    }

    @objc public static func nativeBounds(_ rect: CGRect) -> CGRect {
        return rect.toAspectRatio(screenGeometry.scaler)
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
        return rect.toAspectRatioDefault(screenGeometry.scaler)
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
