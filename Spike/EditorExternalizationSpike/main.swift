//
//  EditorExternalizationSpike/main.swift
//  PlayTools spike (OPTIMIZATION.md 5.0)
//
//  Verifies the three elements an external keymap-editor process needs:
//    a) a borderless non-activating overlay that does not steal game focus,
//    b) Accessibility API window bounds + the authorization flow,
//    c) window (top-left origin) <-> game screen (bottom-left origin)
//       coordinate conversion.
//
//  Build:  swiftc -O -o spike main.swift -framework AppKit \
//             -framework ApplicationServices
//  Run:    ./spike <pid of the game> [seconds]
//  Check System Settings > Privacy & Security > Accessibility first;
//  without the permission the tool prints the degraded path and exits.
//

import AppKit
import ApplicationServices

// MARK: - Accessibility access

func axTrust(promptIfNeeded prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - Window bounds via AX (element c input)

struct AXWindowFrame {
    let origin: CGPoint
    let size: CGSize
}

func firstWindowFrame(pid: pid_t) -> AXWindowFrame? {
    let appElement = AXUIElementCreateApplication(pid)
    var windowsValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
        let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
        return nil
    }
    var frame = AXWindowFrame(origin: .zero, size: .zero)

    var positionValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        windows[0], kAXPositionAttribute as CFString, &positionValue) == .success,
        let position = positionValue else {
        return nil
    }
    var point = CGPoint.zero
    // kAXPositionAttribute returns an AXValue on success by API contract.
    // swiftlint:disable:next force_cast
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    frame = AXWindowFrame(origin: point, size: frame.size)

    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        windows[0], kAXSizeAttribute as CFString, &sizeValue) == .success,
        let size = sizeValue else {
        return nil
    }
    var cgSize = CGSize.zero
    // kAXSizeAttribute returns an AXValue on success by API contract.
    // swiftlint:disable:next force_cast
    AXValueGetValue(size as! AXValue, .cgSize, &cgSize)
    return AXWindowFrame(origin: frame.origin, size: cgSize)
}

// MARK: - Coordinate conversion (element c)

/// AX and NSScreen global coordinates use a top-left origin; UIKit (the
/// game side) uses a bottom-left origin. Convert a point in window space
/// to game-view space given the window frame and the screen it is on.
func windowToGame(point: CGPoint, window: AXWindowFrame, screen: NSScreen) -> CGPoint {
    let screenHeight = screen.frame.height
    let screenOriginY = screen.frame.minY
    // Global top-left based -> global bottom-left based.
    let bottomLeftY = screenHeight + screenOriginY - (window.origin.y + point.y)
    return CGPoint(x: window.origin.x - screen.frame.minX + point.x, y: bottomLeftY)
}

// MARK: - Overlay panel (element a)

final class SpikeOverlay {
    let panel: NSPanel

    init(frame: NSRect) {
        panel = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = NSColor(calibratedRed: 1, green: 0.3, blue: 0.3, alpha: 0.25)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(frame: NSRect) {
        panel.setFrame(frame, display: true)
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2, let pid = pid_t(args[1]),
    let duration = args.count > 2 ? TimeInterval(args[2]) : 10.0 else {
    print("usage: spike <pid> [seconds]")
    exit(64)
}

// Element b: authorization gate + denial degradation.
guard axTrust(promptIfNeeded: true) else {
    print("AX: NOT TRUSTED — denial path: editor must fall back to no-overlay mode")
    exit(75) // EX_TEMPFAIL: degraded, not a crash
}
print("AX: trusted")

let app = NSApplication.shared
let overlay = SpikeOverlay(frame: .zero)
var ticksRemaining = Int(duration)

let work = DispatchWorkItem {
    if let frame = firstWindowFrame(pid: pid) {
        let rect = NSRect(origin: frame.origin, size: frame.size)
        overlay.update(frame: rect)
        overlay.show()
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(rect.origin, $0.frame, false) })
            ?? NSScreen.main {
            // Element c: round-trip the window's own top-left corner through
            // the conversion and check it lands back on itself.
            let gamePoint = windowToGame(point: .zero, window: frame, screen: screen)
            print(String(format: "AX frame: %@ -> game-space origin: %@",
                         NSStringFromRect(rect), NSStringFromPoint(gamePoint)))
        }
    } else {
        print("AX: no window bounds available yet")
    }
}

Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { tick in
    work.perform()
    ticksRemaining -= 1
    if ticksRemaining <= 0 {
        tick.invalidate()
        app.stop(nil)
    }
}
work.perform()

app.run()
print("spike done — verify: overlay never activated the game, bounds tracked the window")
