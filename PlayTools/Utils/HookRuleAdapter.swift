//
//  HookRuleAdapter.swift
//  PlayTools
//
//  Maps active data-pack rules onto the HookSpec installer model
//  (OPTIMIZATION.md 5.1). Conditions were already evaluated against the
//  launch facts snapshot, so adapted specs install unconditionally.
//  Pure Foundation; dual-compiled into PlayToolsTests.
//

import Foundation

enum HookRuleAdapter {
    static func specs(from pack: HookRulePack, facts: [String: Bool]) -> [HookSpec] {
        HookRuleEvaluator.activeRules(from: pack, facts: facts).map { rule in
            HookSpec(id: rule.id,
                     selector: rule.selector,
                     replacement: rule.replacement,
                     candidates: rule.candidates.map {
                         HookCandidate(className: $0.className, kind: kind(from: $0.kind))
                     },
                     policy: rule.policy == .always ? .always : .optional,
                     condition: { true })
        }
    }

    private static func kind(from candidateKind: HookRuleCandidate.Kind) -> HookInstallKind {
        switch candidateKind {
        case .instance: return .instance
        case .exchange: return .exchange
        case .classMethod: return .classMethod
        }
    }
}
