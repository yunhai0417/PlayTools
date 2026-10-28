//
//  HookRulePackEquivalenceTests.swift
//  PlayToolsTests
//
//  Drift guard for OPTIMIZATION.md 5.1: the bundled data pack must
//  produce, for every settings combination, exactly the specs the code
//  matrix (HookSpecMatrix) produces — same rules, same order, same
//  candidates, same policies.
//

import XCTest

final class HookRulePackEquivalenceTests: XCTestCase {

    private func kindName(_ kind: HookInstallKind) -> String {
        switch kind {
        case .instance: return "instance"
        case .exchange: return "exchange"
        case .classMethod: return "classMethod"
        }
    }

    private func signature(_ specs: [HookSpec]) -> [[String]] {
        specs.map { spec in
            [spec.id, spec.selector, spec.replacement, spec.policy == .always ? "always" : "optional"]
                + spec.candidates.map { "\($0.className)|\(kindName($0.kind))" }
        }
    }

    private func assertEquivalent(_ facts: HookFactsInput, _ label: String) throws {
        let pack = try XCTUnwrap(HookRulePackDefaults.bundledPack())
        // The code matrix emits condition-gated specs that install() skips;
        // the pack path pre-filters them. Compare what each would install.
        let codeSpecs = HookSpecMatrix.allSpecs(facts: facts).filter { $0.condition() }
        let packSpecs = HookRuleAdapter.specs(from: pack, facts: HookRuleFacts.dict(from: facts))

        XCTAssertEqual(signature(packSpecs), signature(codeSpecs), "matrix drift at \(label)")
    }

    func testBundledPackIsValid() throws {
        let pack = try XCTUnwrap(HookRulePackDefaults.bundledPack())

        XCTAssertEqual(pack.version, HookRulePackValidator.currentVersion)
        XCTAssertTrue(HookRulePackValidator.problems(in: pack).isEmpty)
        XCTAssertEqual(pack.rules.count, 37)
    }

    func testEquivalentAcrossDisplayMatrix() throws {
        for is163 in [false, true] {
            for resizable in [false, true] {
                for adaptive in [false, true] {
                    for inverse in [false, true] {
                        for fixedWindow in [false, true] {
                            var facts = HookFactsInput()
                            facts.is163OrNewer = is163
                            facts.resizableWindow = resizable
                            facts.adaptiveDisplay = adaptive
                            facts.inverseScreenValues = inverse
                            facts.windowFixMethod1 = fixedWindow

                            let label = "163=\(is163),resizable=\(resizable),"
                                + "adaptive=\(adaptive),inverse=\(inverse),fixed=\(fixedWindow)"
                            try assertEquivalent(facts, label)
                        }
                    }
                }
            }
        }
    }

    func testEquivalentWithAllConditionalFixesOn() throws {
        var facts = HookFactsInput()
        facts.is163OrNewer = true
        facts.engineUnreal = true
        facts.systemEncodingChinese = true
        facts.micPermissionSync = true
        facts.limitMotionFrequency = true
        facts.disableBuiltinMouse = true
        facts.unityKeyboardInit = true

        try assertEquivalent(facts, "all fixes on")
    }

    func testEquivalentWithEngineAlone() throws {
        var facts = HookFactsInput()
        facts.engineUnreal = true // without Chinese encoding the UE rule stays off

        try assertEquivalent(facts, "engine only")
    }
}
