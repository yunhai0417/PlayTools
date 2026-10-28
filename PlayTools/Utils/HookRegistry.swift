//
//  HookRegistry.swift
//  PlayTools
//
//  Declarative hook registry + introspection-first installer (OPTIMIZATION.md P1).
//  Replaces the imperative version-gated matrix in PTSwizzleLoader +load.
//  Behavioral equivalence: same hooks installed for the same settings matrix.
//

import Foundation
import UIKit

// Spec model types (HookSpec / HookCandidate / HookInstallKind) live in
// HookSpecModel.swift so they can be dual-compiled for tests.

// MARK: - Registry

@objcMembers
public final class HookRegistry: NSObject {

    static public func installFromLoad() {
        let registry = HookRegistry()
        registry.run()
    }

    private func run() {
        let settings = PlaySettings.shared
        let safeMode = settings.safeMode

        // Environment snapshot, computed once (OPTIMIZATION.md 5.1). Probing
        // is still the primary selector: the 16.3 gate only preserves the
        // original matrix where older systems installed strictly fewer hooks.
        var facts = HookFactsInput()
        if #available(iOS 16.3, *) { facts.is163OrNewer = true }
        facts.resizableWindow = settings.resizableWindow
        facts.adaptiveDisplay = settings.adaptiveDisplay
        facts.inverseScreenValues = settings.inverseScreenValues
        facts.windowFixMethod1 = settings.windowFixMethod == 1
        facts.engineUnreal = PlayInfo.isUnrealEngine
        facts.systemEncodingChinese = Self.isSystemEncodingChinese()
        facts.micPermissionSync = settings.checkMicPermissionSync
        facts.limitMotionFrequency = settings.limitMotionUpdateFrequency
        facts.disableBuiltinMouse = settings.disableBuiltinMouse
        facts.unityKeyboardInit = settings.ignoreUnityKeyboardInitializationError

        // Original matrix side effect: persist default window size before the
        // default-display hooks read it back (NSObject+Swizzle +load, else branch)
        if facts.is163OrNewer && !facts.resizableWindow
            && !facts.adaptiveDisplay && !facts.windowFixMethod1 {
            let width = CGFloat(settingsDataWindowWidth())
            settings.setValue(NSNumber(value: Float(width)), forKey: "windowSizeWidth")
            let height = CGFloat(settingsDataWindowHeight())
            settings.setValue(NSNumber(value: Float(height)), forKey: "windowSizeHeight")
        }

        let specs = HookSpecMatrix.allSpecs(facts: facts)
        install(specs: specs, safeMode: safeMode)
    }

    /// kCFStringEncodingMacChineseSimp (0x0628) / MacChineseTrad (0x0629):
    /// the named constants are not exposed to Swift, values from CFString.h.
    private static func isSystemEncodingChinese() -> Bool {
        let encoding = CFStringGetSystemEncoding()
        return encoding == 0x0628 || encoding == 0x0629
    }

    /// Window size defaults mirroring the original `get_default_width/height`
    /// helpers in NSObject+Swizzle.m (they read UIScreen through eventual hooks).
    private func settingsDataWindowWidth() -> Double {
        UIScreen.main.bounds.size.width
    }

    private func settingsDataWindowHeight() -> Double {
        UIScreen.main.bounds.size.height
    }

    // MARK: - Installer

    private func install(specs: [HookSpec], safeMode: Bool) {
        var appliedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for spec in specs {
            if safeMode && spec.policy == .optional {
                skippedCount += 1
                record(spec: spec, className: "-", result: "skipped", detail: "safe mode")
                continue
            }
            if !spec.condition() {
                skippedCount += 1
                record(spec: spec, className: "-", result: "skipped", detail: "condition not met")
                continue
            }

            // Unity KeyboardDelegate needs its framework loaded first: the
            // original code delayed this hook by one runloop tick.
            if spec.id == "fix.unityKeyboardInit" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    _ = self.installOnCandidates(spec)
                }
                continue
            }

            if installOnCandidates(spec) {
                appliedCount += 1
            } else {
                failedCount += 1
            }
        }

        if safeMode {
            PCLog.loader.info("safeMode ON: \(skippedCount) optional hooks skipped by registry")
        }
        PCLog.loader.info("HookRegistry: \(appliedCount) applied, \(skippedCount) skipped, \(failedCount) failed")
    }

    /// Probes candidates in order; first one whose class exists AND responds to
    /// the selector wins. Version checks are only a fallback encoded in the
    /// candidate order (newer class first).
    private func installOnCandidates(_ spec: HookSpec) -> Bool {
        for candidate in spec.candidates {
            guard let cls = NSClassFromString(candidate.className) else {
                continue
            }
            let selector = NSSelectorFromString(spec.selector)
            let responds: Bool
            switch candidate.kind {
            case .classMethod:
                responds = classGetMethod(cls: cls, selector: selector) != nil
            case .instance, .exchange:
                responds = class_getInstanceMethod(cls, selector) != nil
            }
            guard responds else { continue }

            let replacement = NSSelectorFromString(spec.replacement)
            let installed = PTSwizzleOnClassNamed(candidate.className,
                                                  kindFor(candidate.kind),
                                                  selector,
                                                  replacement)
            if installed {
                record(spec: spec, className: candidate.className, result: "applied", detail: nil)
                return true
            }
            record(spec: spec, className: candidate.className, result: "failed", detail: "install returned false")
            return false
        }
        record(spec: spec, className: "-", result: "classNotFound",
               detail: "no candidate holds \(spec.selector)")
        return false
    }

    private func classGetMethod(cls: AnyClass, selector: Selector) -> Method? {
        class_getClassMethod(cls, selector)
    }

    private func kindFor(_ kind: HookInstallKind) -> PTSwizzleKind {
        switch kind {
        case .instance: return .instance
        case .exchange: return .exchange
        case .classMethod: return .classMethod
        }
    }

    private func record(spec: HookSpec, className: String, result: String, detail: String?) {
        HookStatusRegistry.shared.record(target: "spec:\(spec.id)",
                                         selector: spec.selector,
                                         replacement: "\(spec.replacement) @ \(className)",
                                         result: result,
                                         detail: detail)
    }
}
