//
//  HookRuleResolverTests.swift
//  PlayToolsTests
//
//  Three-tier hook spec resolution (OPTIMIZATION.md 5.1): external pack
//  wins, bundled pack is next, code matrix is the ultimate fallback.
//

import XCTest

final class HookRuleResolverTests: XCTestCase {

    private func minimalPack(ruleID: String) -> HookRulePack {
        HookRulePack(version: 1, rules: [
            HookRule(id: ruleID,
                     selector: "selector",
                     replacement: "hook_selector",
                     candidates: [HookRuleCandidate(className: "UIScreen", kind: .instance)],
                     policy: .optional,
                     when: nil)
        ])
    }

    func testExternalPackWins() {
        let resolution = HookRuleResolver.specs(facts: HookFactsInput(),
                                                externalPack: minimalPack(ruleID: "external.rule"),
                                                bundledPack: minimalPack(ruleID: "bundled.rule"))

        XCTAssertEqual(resolution.source, .external)
        XCTAssertEqual(resolution.specs.map(\.id), ["external.rule"])
    }

    func testBundledPackUsedWhenExternalMissing() {
        let resolution = HookRuleResolver.specs(facts: HookFactsInput(),
                                                externalPack: nil,
                                                bundledPack: minimalPack(ruleID: "bundled.rule"))

        XCTAssertEqual(resolution.source, .bundled)
        XCTAssertEqual(resolution.specs.map(\.id), ["bundled.rule"])
    }

    func testCodeMatrixUsedWhenBothPacksMissing() {
        var facts = HookFactsInput()
        facts.is163OrNewer = true
        facts.resizableWindow = true
        let resolution = HookRuleResolver.specs(facts: facts, externalPack: nil, bundledPack: nil)

        XCTAssertEqual(resolution.source, .codeMatrix)
        // Code-matrix tier keeps condition closures; installed set matches
        // the filtered code specs.
        let installed = resolution.specs.filter { $0.condition() }
        XCTAssertEqual(installed.first?.id, "resizable.requiresFullScreen")
    }

    func testBundledTierMatchesCodeMatrixInstalledSet() {
        var facts = HookFactsInput()
        facts.is163OrNewer = true
        facts.adaptiveDisplay = true
        facts.unityKeyboardInit = true

        let bundled = HookRuleResolver.specs(facts: facts,
                                             externalPack: nil,
                                             bundledPack: HookRulePackDefaults.bundledPack())
        let code = HookSpecMatrix.allSpecs(facts: facts).filter { $0.condition() }

        XCTAssertEqual(bundled.specs.map(\.id), code.map(\.id))
    }
}
