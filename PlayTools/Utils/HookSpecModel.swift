//
//  HookSpecModel.swift
//  PlayTools
//
//  Pure model types for the declarative hook registry (OPTIMIZATION.md
//  P1/5.1). Split out of HookRegistry.swift so the spec matrix and the
//  data-pack adapter share them without pulling in UIKit or the
//  installer. Dual-compiled into PlayToolsTests.
//

import Foundation

enum HookInstallKind {
    case instance
    case exchange
    case classMethod
}

struct HookCandidate {
    let className: String
    let kind: HookInstallKind
}

struct HookSpec {
    /// `always` survives safe mode (menu injection); `optional` is skipped.
    enum Policy {
        case always
        case optional
    }

    let id: String
    let selector: String
    let replacement: String
    let candidates: [HookCandidate]
    let policy: HookSpec.Policy
    let condition: () -> Bool
}
