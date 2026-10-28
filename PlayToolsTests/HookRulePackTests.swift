//
//  HookRulePackTests.swift
//  PlayToolsTests
//
//  HookRulePack model/evaluator/validator and the Ed25519 signed loader
//  (OPTIMIZATION.md 5.1): AND semantics, fail-closed unknown facts,
//  validation problems, and tamper rejection.
//

import CryptoKit
import XCTest

final class HookRulePackTests: XCTestCase {

    private func makeRule(id: String = "r1",
                          when: [HookRuleCondition]? = nil) -> HookRule {
        HookRule(id: id,
                 selector: "selector",
                 replacement: "hook_selector",
                 candidates: [HookRuleCandidate(className: "UIScreen", kind: .instance)],
                 policy: .optional,
                 when: when)
    }

    // MARK: evaluator

    func testRuleWithoutConditionsIsActive() {
        XCTAssertTrue(HookRuleEvaluator.isActive(makeRule(), facts: [:]))
    }

    func testAllConditionsMustMatch() {
        let rule = makeRule(when: [.init(fact: "a", equals: true),
                                   .init(fact: "b", equals: false)])

        XCTAssertTrue(HookRuleEvaluator.isActive(rule, facts: ["a": true, "b": false]))
        XCTAssertFalse(HookRuleEvaluator.isActive(rule, facts: ["a": true, "b": true]))
        XCTAssertFalse(HookRuleEvaluator.isActive(rule, facts: ["a": false, "b": false]))
    }

    func testUnknownFactFailsClosed() {
        let rule = makeRule(when: [.init(fact: "missing", equals: true)])

        XCTAssertFalse(HookRuleEvaluator.isActive(rule, facts: ["other": true]))
    }

    func testActiveRulesFiltersInOrder() {
        let pack = HookRulePack(version: 1, rules: [
            makeRule(id: "on", when: [.init(fact: "flag", equals: true)]),
            makeRule(id: "off", when: [.init(fact: "flag", equals: false)])
        ])

        let active = HookRuleEvaluator.activeRules(from: pack, facts: ["flag": true])
        XCTAssertEqual(active.map(\.id), ["on"])
    }

    // MARK: decoding

    func testDecodeFromJSON() throws {
        let json = """
        {
          "version": 1,
          "rules": [
            {
              "id": "ue.regexChineseFix",
              "selector": "_stringByReplacing:",
              "replacement": "hook_stringByReplacing:",
              "candidates": [{"className": "NSString", "kind": "instance"}],
              "policy": "optional",
              "when": [{"fact": "engine.unreal", "equals": true}]
            }
          ]
        }
        """
        let pack = try JSONDecoder().decode(HookRulePack.self, from: Data(json.utf8))

        XCTAssertEqual(pack.rules.count, 1)
        XCTAssertEqual(pack.rules[0].candidates[0].kind, .instance)
        XCTAssertEqual(pack.rules[0].when?.first?.fact, "engine.unreal")
    }

    // MARK: validator

    func testValidatorAcceptsGoodPack() {
        let pack = HookRulePack(version: 1, rules: [makeRule()])

        XCTAssertTrue(HookRulePackValidator.problems(in: pack).isEmpty)
    }

    func testValidatorReportsProblems() {
        let bad = HookRule(id: "bad", selector: "", replacement: "",
                           candidates: [], policy: nil, when: nil)
        let pack = HookRulePack(version: 99, rules: [makeRule(), bad])

        let found = HookRulePackValidator.problems(in: pack)
        XCTAssertTrue(found.contains { $0.contains("newer than supported") })
        XCTAssertTrue(found.contains { $0.contains("empty selector") })
        XCTAssertTrue(found.contains { $0.contains("empty replacement") })
        XCTAssertTrue(found.contains { $0.contains("no candidates") })
    }

    func testValidatorReportsDuplicateIDs() {
        let pack = HookRulePack(version: 1, rules: [makeRule(id: "same"), makeRule(id: "same")])

        XCTAssertEqual(HookRulePackValidator.problems(in: pack).count, 1)
    }

    func testValidatorRejectsEmptyPack() {
        let pack = HookRulePack(version: 1, rules: [])

        XCTAssertEqual(HookRulePackValidator.problems(in: pack), ["pack has no rules"])
    }

    // MARK: signed loader

    func testSignedRoundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pack = HookRulePack(version: 1, rules: [makeRule()])
        let signed = try HookRulePackLoader.sign(pack: pack, with: key)

        let loaded = HookRulePackLoader.load(signedData: signed, verifyingWith: key.publicKey)
        XCTAssertEqual(loaded?.rules.map(\.id), pack.rules.map(\.id))
    }

    func testTamperedPayloadIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try HookRulePackLoader.sign(pack: HookRulePack(version: 1, rules: [makeRule()]),
                                                 with: key)

        // Decode envelope, swap in a different payload, keep old signature.
        var envelope = try JSONDecoder().decode(SignedHookRulePack.self, from: signed)
        let evil = try JSONEncoder().encode(HookRulePack(version: 1, rules: [makeRule(id: "evil")]))
        envelope = SignedHookRulePack(payload: evil.base64EncodedString(),
                                      signature: envelope.signature)
        let tampered = try JSONEncoder().encode(envelope)

        XCTAssertNil(HookRulePackLoader.load(signedData: tampered, verifyingWith: key.publicKey))
    }

    func testWrongKeyIsRejected() throws {
        let signer = Curve25519.Signing.PrivateKey()
        let verifier = Curve25519.Signing.PrivateKey()
        let signed = try HookRulePackLoader.sign(pack: HookRulePack(version: 1, rules: [makeRule()]),
                                                 with: signer)

        XCTAssertNil(HookRulePackLoader.load(signedData: signed, verifyingWith: verifier.publicKey))
    }

    func testGarbageIsRejected() {
        let key = Curve25519.Signing.PrivateKey()

        XCTAssertNil(HookRulePackLoader.load(signedData: Data("not json".utf8),
                                             verifyingWith: key.publicKey))
    }

    func testInvalidPackContentIsRejectedEvenWithValidSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        // Signed but structurally invalid: version from the future.
        let pack = HookRulePack(version: 99, rules: [makeRule()])
        let signed = try HookRulePackLoader.sign(pack: pack, with: key)

        XCTAssertNil(HookRulePackLoader.load(signedData: signed, verifyingWith: key.publicKey))
    }
}
