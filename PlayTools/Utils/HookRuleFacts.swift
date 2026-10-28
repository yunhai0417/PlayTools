//
//  HookRuleFacts.swift
//  PlayTools
//
//  Environment facts hook rules are predicated on (OPTIMIZATION.md 5.1).
//  One snapshot taken at launch feeds both the code spec matrix and the
//  data rule pack evaluation, keeping the two representations
//  comparable in tests. Pure Foundation; dual-compiled into
//  PlayToolsTests.
//

import Foundation

/// Launch-time environment snapshot. Field names double as rule inputs.
struct HookFactsInput {
    var is163OrNewer = false
    var resizableWindow = false
    var adaptiveDisplay = false
    var inverseScreenValues = false
    var windowFixMethod1 = false
    var engineUnreal = false
    var systemEncodingChinese = false
    var micPermissionSync = false
    var limitMotionFrequency = false
    var disableBuiltinMouse = false
    var unityKeyboardInit = false
}

enum HookRuleFacts {
    /// Map a snapshot to the named facts referenced by pack `when`
    /// conditions. Names are protocol: keep in sync with pack JSON.
    static func dict(from input: HookFactsInput) -> [String: Bool] {
        [
            "runtime.ios163OrNewer": input.is163OrNewer,
            "settings.resizableWindow": input.resizableWindow,
            "settings.adaptiveDisplay": input.adaptiveDisplay,
            "settings.inverseScreenValues": input.inverseScreenValues,
            "settings.windowFixMethod1": input.windowFixMethod1,
            "engine.unreal": input.engineUnreal,
            "systemEncoding.chinese": input.systemEncodingChinese,
            "settings.checkMicPermissionSync": input.micPermissionSync,
            "settings.limitMotionUpdateFrequency": input.limitMotionFrequency,
            "settings.disableBuiltinMouse": input.disableBuiltinMouse,
            "settings.ignoreUnityKeyboardInitializationError": input.unityKeyboardInit
        ]
    }
}
