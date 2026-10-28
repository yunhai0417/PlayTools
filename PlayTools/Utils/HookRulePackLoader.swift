//
//  HookRulePackLoader.swift
//  PlayTools
//
//  Signed delivery of HookRulePacks (OPTIMIZATION.md 5.1). The envelope
//  carries the pack JSON as raw payload bytes (base64) plus an Ed25519
//  signature over exactly those bytes, so no canonical JSON form is
//  ever needed. Any failure — bad base64, bad JSON, bad signature,
//  unsupported version, validation problems — yields nil and the caller
//  falls back to the built-in pack. Dual-compiled into PlayToolsTests.
//

import CryptoKit
import Foundation

struct SignedHookRulePack: Codable {
    /// base64 of the HookRulePack JSON bytes.
    let payload: String
    /// base64 Ed25519 signature over the payload bytes.
    let signature: String
}

enum HookRulePackLoader {
    /// Verify then decode a signed pack. Returns nil on any failure.
    static func load(signedData: Data,
                     verifyingWith publicKey: Curve25519.Signing.PublicKey) -> HookRulePack? {
        guard let envelope = try? JSONDecoder().decode(SignedHookRulePack.self, from: signedData),
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              publicKey.isValidSignature(signature, for: payload),
              let pack = try? JSONDecoder().decode(HookRulePack.self, from: payload),
              HookRulePackValidator.problems(in: pack).isEmpty
        else { return nil }
        return pack
    }

    /// Build a signed envelope (host-side tooling and tests).
    static func sign(pack: HookRulePack,
                     with privateKey: Curve25519.Signing.PrivateKey) throws -> Data {
        let payload = try JSONEncoder().encode(pack)
        let signature = try privateKey.signature(for: payload)
        let envelope = SignedHookRulePack(payload: payload.base64EncodedString(),
                                          signature: signature.base64EncodedString())
        return try JSONEncoder().encode(envelope)
    }
}
