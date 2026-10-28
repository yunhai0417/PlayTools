//
//  HookRulePackPinning.swift
//  PlayTools
//
//  Release key pinning and delivery path for externally sourced hook
//  rule packs (OPTIMIZATION.md 5.1). External packs are Ed25519-signed
//  envelopes produced with HookRulePackLoader.sign and dropped at
//  externalPackPath() by the PlayCover host.
//
//  Until a release keypair is generated and the public half pinned
//  here, `pinnedPublicKey` stays nil: external packs are then disabled
//  entirely (fail-safe) and the runtime uses the bundled pack.
//

import CryptoKit
import Foundation

enum HookRulePackPinning {
    /// Ed25519 public key verifying externally delivered packs.
    /// Pin with `Curve25519.Signing.PublicKey(rawRepresentation: Data([...]))`.
    static let pinnedPublicKey: Curve25519.Signing.PublicKey? = nil

    static func externalPackPath(bundleIdentifier: String) -> String {
        "/Users/\(NSUserName())/Library/Containers/io.playcover.PlayCover/Rule Packs"
            + "/\(bundleIdentifier).json"
    }
}
