//
//  HookRegistrySpecs.swift
//  PlayTools
//
//  Spec matrix mirroring the original PTSwizzleLoader +load matrix group
//  by group (OPTIMIZATION.md P1). Pure Foundation over a HookFactsInput
//  snapshot; dual-compiled into PlayToolsTests where the equivalent
//  data pack (HookRulePackDefaults) is diffed against it. Keep in sync
//  with the ObjC hook_* replacement methods in NSObject+Swizzle.m.
//

import Foundation

/// Code representation of the hook matrix. HookRegistry.run() installs
/// these; the signed data pack (OPTIMIZATION.md 5.1) mirrors them.
/// Replacement-method bundle for a display variant.
private struct DisplayVariant {
    let frame: String
    let bounds: String
    let size: String
    let nativeBounds: String

    static let adaptive = DisplayVariant(frame: "hook_frame",
                                         bounds: "hook_bounds",
                                         size: "hook_size",
                                         nativeBounds: "hook_nativeBounds")

    static let adaptiveInverse = DisplayVariant(frame: "hook_frameDefault",
                                                bounds: "hook_boundsDefault",
                                                size: "hook_sizeDelfault",
                                                nativeBounds: "hook_nativeBoundsDefault")
}

enum HookSpecMatrix {

    /// Pure: every activation input arrives via the snapshot, so the code
    /// matrix and the data rule pack stay comparable in tests.
    static func allSpecs(facts: HookFactsInput) -> [HookSpec] {
        let is163OrNewer = facts.is163OrNewer
        let resizable = facts.resizableWindow
        let adaptive = facts.adaptiveDisplay
        let inverse = facts.inverseScreenValues
        let fixedWindow = facts.windowFixMethod1

        let sceneCandidates = [
            HookCandidate(className: "FBSSceneSettingsCore", kind: .exchange),
            HookCandidate(className: "FBSSceneSettings", kind: .instance)
        ]

        var specs: [HookSpec] = []

        // A. resizable window
        if is163OrNewer && resizable {
            specs += resizableSpecs()
        }

        // B/C. adaptive display on iOS 16.3+. `!resizable` mirrors the original
        // else-if chain: resolution == 6 also makes `adaptiveDisplay` true, but
        // the resizable branch won.
        if is163OrNewer && !resizable && adaptive {
            specs += displaySpecs(prefix: inverse ? "adaptiveInverse" : "adaptive",
                                  variant: inverse ? .adaptiveInverse : .adaptive,
                                  sceneCandidates: sceneCandidates)
        }

        // C-pre16.3: adaptive display on older runtimes installed ONLY the
        // frame/bounds/size trio with the plain variant, regardless of inverse
        // (the original pre-16.3 branch had no split and no UIScreen hooks).
        if !is163OrNewer && adaptive {
            specs += legacyAdaptiveSpecs(sceneCandidates: sceneCandidates)
        }

        // D. default window sizing
        if is163OrNewer && !resizable && !adaptive && !fixedWindow {
            specs += defaultSpecs(inverse: inverse, sceneCandidates: sceneCandidates)
        }

        // E. always-on hooks
        specs += alwaysSpecs()

        // F. conditional app-specific fixes
        specs += conditionalSpecs(facts: facts)

        return specs
    }

    private static func resizableSpecs() -> [HookSpec] {
        [
            HookSpec(id: "resizable.requiresFullScreen",
                     selector: "requiresFullScreen",
                     replacement: "hook_requiresFullScreen",
                     candidates: [HookCandidate(className: "_UIApplicationInfoParser", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "resizable.bounds",
                     selector: "bounds",
                     replacement: "hook_boundsResizable",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "resizable.nativeScale",
                     selector: "nativeScale",
                     replacement: "hook_nativeScale",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "resizable.scale",
                     selector: "scale",
                     replacement: "hook_scale",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true })
        ]
    }

    private static func displaySpecs(prefix: String,
                                     variant: DisplayVariant,
                                     sceneCandidates: [HookCandidate]) -> [HookSpec] {
        [
            HookSpec(id: "\(prefix).frame",
                     selector: "frame",
                     replacement: variant.frame,
                     candidates: sceneCandidates,
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "\(prefix).bounds",
                     selector: "bounds",
                     replacement: variant.bounds,
                     candidates: [HookCandidate(className: "FBSSceneSettings", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "\(prefix).size",
                     selector: "size",
                     replacement: variant.size,
                     candidates: [HookCandidate(className: "FBSDisplayMode", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "\(prefix).orientation",
                     selector: "orientation",
                     replacement: "hook_orientation",
                     candidates: [HookCandidate(className: "UIDevice", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "\(prefix).nativeBounds",
                     selector: "nativeBounds",
                     replacement: variant.nativeBounds,
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "\(prefix).nativeScale",
                     selector: "nativeScale",
                     replacement: "hook_nativeScale",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "\(prefix).scale",
                     selector: "scale",
                     replacement: "hook_scale",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true })
        ]
    }

    private static func legacyAdaptiveSpecs(sceneCandidates: [HookCandidate]) -> [HookSpec] {
        [
            HookSpec(id: "adaptiveLegacy.frame",
                     selector: "frame",
                     replacement: "hook_frame",
                     candidates: sceneCandidates,
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "adaptiveLegacy.bounds",
                     selector: "bounds",
                     replacement: "hook_bounds",
                     candidates: [HookCandidate(className: "FBSSceneSettings", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "adaptiveLegacy.size",
                     selector: "size",
                     replacement: "hook_size",
                     candidates: [HookCandidate(className: "FBSDisplayMode", kind: .instance)],
                     policy: .optional,
                     condition: { true })
        ]
    }

    private static func defaultSpecs(inverse: Bool,
                                     sceneCandidates: [HookCandidate]) -> [HookSpec] {
        var specs: [HookSpec] = []
        if !inverse {
            specs += [
                HookSpec(id: "default.frame",
                         selector: "frame",
                         replacement: "hook_frameDefault",
                         candidates: sceneCandidates,
                         policy: .optional,
                         condition: { true }),
                HookSpec(id: "default.bounds",
                         selector: "bounds",
                         replacement: "hook_boundsDefault",
                         candidates: [HookCandidate(className: "FBSSceneSettings", kind: .instance)],
                         policy: .optional,
                         condition: { true }),
                HookSpec(id: "default.size",
                         selector: "size",
                         replacement: "hook_sizeDelfault",
                         candidates: [HookCandidate(className: "FBSDisplayMode", kind: .instance)],
                         policy: .optional,
                         condition: { true })
            ]
        }
        specs += [
            HookSpec(id: "default.orientation",
                     selector: "orientation",
                     replacement: "hook_orientation",
                     candidates: [HookCandidate(className: "UIDevice", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "default.nativeBounds",
                     selector: "nativeBounds",
                     replacement: "hook_nativeBoundsDefault",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "default.nativeScale",
                     selector: "nativeScale",
                     replacement: "hook_nativeScale",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "default.scale",
                     selector: "scale",
                     replacement: "hook_scale",
                     candidates: [HookCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     condition: { true })
        ]
        return specs
    }

    private static func alwaysSpecs() -> [HookSpec] {
        [
            HookSpec(id: "menu.initWithRootMenu",
                     selector: "initWithRootMenu:",
                     replacement: "initWithRootMenuHook:",
                     candidates: [HookCandidate(className: "_UIMenuBuilder", kind: .instance)],
                     policy: .always,
                     condition: { true }),
            HookSpec(id: "always.prefersPointerLocked",
                     selector: "prefersPointerLocked",
                     replacement: "hook_prefersPointerLocked",
                     candidates: [HookCandidate(className: "IOSViewController", kind: .instance)],
                     policy: .optional,
                     condition: { true }),
            HookSpec(id: "always.setCurrentSubscription",
                     selector: "setCurrentSubscription:",
                     replacement: "hook_setCurrentSubscription:",
                     candidates: [HookCandidate(className: "VSSubscriptionRegistrationCenter", kind: .instance)],
                     policy: .optional,
                     condition: { true })
        ]
    }

    private static func conditionalSpecs(facts: HookFactsInput) -> [HookSpec] {
        let ueRegexSelector = "_stringByReplacingOccurrencesOfRegularExpressionPattern:"
            + "withTemplate:options:range:"
        let ueRegexReplacement = "hook_stringByReplacingOccurrencesOfRegularExpressionPattern:"
            + "withTemplate:options:range:"
        return [
            HookSpec(id: "ue.regexChineseFix",
                     selector: ueRegexSelector,
                     replacement: ueRegexReplacement,
                     candidates: [HookCandidate(className: "NSString", kind: .instance)],
                     policy: .optional,
                     condition: { facts.engineUnreal && facts.systemEncodingChinese }),
            HookSpec(id: "fix.micPermissionSync",
                     selector: "requestRecordPermission:",
                     replacement: "hook_requestRecordPermission:",
                     candidates: [HookCandidate(className: "AVAudioSession", kind: .instance)],
                     policy: .optional,
                     condition: { facts.micPermissionSync }),
            HookSpec(id: "fix.limitMotionFrequency",
                     selector: "init",
                     replacement: "hook_CMMotionManager_init",
                     candidates: [HookCandidate(className: "CMMotionManager", kind: .instance)],
                     policy: .optional,
                     condition: { facts.limitMotionFrequency }),
            HookSpec(id: "fix.disableBuiltinMouse.current",
                     selector: "current",
                     replacement: "hook_GCMouse_current",
                     candidates: [HookCandidate(className: "GCMouse", kind: .classMethod)],
                     policy: .optional,
                     condition: { facts.disableBuiltinMouse }),
            HookSpec(id: "fix.disableBuiltinMouse.mice",
                     selector: "mice",
                     replacement: "hook_GCMouse_mice",
                     candidates: [HookCandidate(className: "GCMouse", kind: .classMethod)],
                     policy: .optional,
                     condition: { facts.disableBuiltinMouse }),
            HookSpec(id: "fix.unityKeyboardInit",
                     selector: "Initialize",
                     replacement: "hook_Unity_KeyboardDelegate_Initialize",
                     candidates: [HookCandidate(className: "KeyboardDelegate", kind: .classMethod)],
                     policy: .optional,
                     condition: { facts.unityKeyboardInit })
        ]
    }
}
