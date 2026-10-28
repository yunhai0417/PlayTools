//
//  HookRuleResolver.swift
//  PlayTools
//
//  Three-tier hook spec resolution (OPTIMIZATION.md 5.1):
//    1. an externally delivered, signature-verified pack (future remote
//       updates; verification happens in the caller),
//    2. the bundled default pack (trusted by construction),
//    3. the code matrix as ultimate fallback.
//  Pure Foundation; dual-compiled into PlayToolsTests.
//

import Foundation

enum HookRuleResolver {
    enum Source {
        case external
        case bundled
        case codeMatrix
    }

    /// `externalPack` must already be signature-verified by the caller;
    /// passing nil skips that tier. The code-matrix tier keeps its
    /// condition closures (conditions evaluated at install time),
    /// preserving legacy behavior exactly when both packs are absent.
    static func specs(facts: HookFactsInput,
                      externalPack: HookRulePack?,
                      bundledPack: HookRulePack?) -> (specs: [HookSpec], source: Source) {
        let namedFacts = HookRuleFacts.dict(from: facts)
        if let externalPack = externalPack {
            return (HookRuleAdapter.specs(from: externalPack, facts: namedFacts), .external)
        }
        if let bundledPack = bundledPack {
            return (HookRuleAdapter.specs(from: bundledPack, facts: namedFacts), .bundled)
        }
        return (HookSpecMatrix.allSpecs(facts: facts), .codeMatrix)
    }
}
