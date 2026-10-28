//
//  HookRulePack.swift
//  PlayTools
//
//  Data-driven hook activation rules (OPTIMIZATION.md 5.1). A pack is a
//  versioned list of hook rules whose activation conditions are expressed
//  over named environment facts ("settings.resizableWindow",
//  "engine.unreal", ...) instead of Swift closures, so the matrix can
//  ship as data — bundled now, remotely updatable later. Pure
//  Foundation; dual-compiled into PlayToolsTests.
//

import Foundation

struct HookRulePack: Codable {
    let version: Int
    let rules: [HookRule]
}

struct HookRule: Codable {
    let id: String
    let selector: String
    let replacement: String
    let candidates: [HookRuleCandidate]
    /// `always` survives safe mode; nil means `optional`.
    let policy: HookRule.Policy?
    /// AND-ed activation conditions; nil or empty means unconditional.
    let when: [HookRuleCondition]?

    enum Policy: String, Codable {
        case always
        case optional
    }
}

struct HookRuleCandidate: Codable {
    let className: String
    let kind: HookRuleCandidate.Kind

    enum Kind: String, Codable {
        case instance
        case exchange
        case classMethod
    }
}

struct HookRuleCondition: Codable {
    let fact: String
    let equals: Bool
}

// MARK: - Evaluator

enum HookRuleEvaluator {
    /// A rule is active when every condition matches. Unknown facts fail
    /// closed: installing a hook the pack author did not intend can crash
    /// the game, so an unmatched fact name deactivates the rule.
    static func isActive(_ rule: HookRule, facts: [String: Bool]) -> Bool {
        let conditions = rule.when ?? []
        return conditions.allSatisfy { facts[$0.fact] == $0.equals }
    }

    static func activeRules(from pack: HookRulePack, facts: [String: Bool]) -> [HookRule] {
        pack.rules.filter { isActive($0, facts: facts) }
    }
}

// MARK: - Validation

enum HookRulePackValidator {
    /// Highest pack version this runtime understands.
    static let currentVersion = 1

    /// Returns every problem found; an empty list means the pack is usable.
    static func problems(in pack: HookRulePack) -> [String] {
        var found: [String] = []
        if pack.version > currentVersion {
            found.append("pack version \(pack.version) newer than supported \(currentVersion)")
        }
        if pack.rules.isEmpty {
            found.append("pack has no rules")
        }
        var seenIDs = Set<String>()
        for rule in pack.rules {
            if !seenIDs.insert(rule.id).inserted {
                found.append("duplicate rule id \(rule.id)")
            }
            if rule.selector.isEmpty {
                found.append("rule \(rule.id) has empty selector")
            }
            if rule.replacement.isEmpty {
                found.append("rule \(rule.id) has empty replacement")
            }
            if rule.candidates.isEmpty {
                found.append("rule \(rule.id) has no candidates")
            }
            for candidate in rule.candidates where candidate.className.isEmpty {
                found.append("rule \(rule.id) has a candidate with empty class name")
            }
        }
        return found
    }
}
