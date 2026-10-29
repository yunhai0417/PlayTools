//
//  RulePackSigner/main.swift
//  PlayTools tooling (OPTIMIZATION.md 5.1)
//
//  Signs HookRulePack JSON files into the envelope consumed by
//  HookRulePackLoader: payload = base64 of the RAW pack bytes,
//  signature = Ed25519 over exactly those bytes. The pack is never
//  re-encoded on the signing path, so no canonical JSON form exists.
//
//  Build:  swiftc -O -o packsigner main.swift
//  Usage:  ./packsigner genkeys <private.key> [public.key]
//          ./packsigner sign <pack.json> <private.key> <signed.json>
//          ./packsigner verify <signed.json> <public.key>
//
//  Keep the private key out of the repository. The public key is the
//  candidate for HookRulePackPinning.pinnedPublicKey at release time.
//

import CryptoKit
import Foundation

// MARK: - Envelope (mirrors SignedHookRulePack in HookRulePackLoader.swift)

struct SignedEnvelope: Codable {
    let payload: String
    let signature: String
}

// MARK: - Pack validation model (mirrors HookRulePack field names)

struct PackRuleCandidate: Decodable {
    let className: String
    let kind: String
}

struct PackRule: Decodable {
    let id: String
    let selector: String
    let replacement: String
    let candidates: [PackRuleCandidate]
}

struct PackDocument: Decodable {
    let version: Int
    let rules: [PackRule]
}

// MARK: - Key files (base64 of the raw 32-byte representation)

func readBase64File(path: String) -> Data? {
    guard let text = try? String(contentsOf: URL(fileURLWithPath: path),
                                 encoding: .utf8) else { return nil }
    return Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
}

func writeBase64File(data: Data, path: String) throws {
    try data.base64EncodedString().write(to: URL(fileURLWithPath: path),
                                         atomically: true, encoding: .utf8)
}

func readPrivateKey(path: String) -> Curve25519.Signing.PrivateKey? {
    guard let raw = readBase64File(path: path) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func readPublicKey(path: String) -> Curve25519.Signing.PublicKey? {
    guard let raw = readBase64File(path: path) else { return nil }
    return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
}

// MARK: - Subcommands

func genkeys(args: [String]) -> Int32 {
    guard args.count == 3 || args.count == 4 else {
        print("usage: packsigner genkeys <private.key> [public.key]")
        return 64
    }
    let privateKey = Curve25519.Signing.PrivateKey()
    let publicPath = args.count == 4 ? args[3] : args[2] + ".pub"
    do {
        try writeBase64File(data: privateKey.rawRepresentation, path: args[2])
        try writeBase64File(data: privateKey.publicKey.rawRepresentation, path: publicPath)
    } catch {
        print("genkeys: \(error)")
        return 74
    }
    print("private key: \(args[2])")
    print("public key:  \(publicPath)")
    print("pin the public key in HookRulePackPinning before shipping packs")
    return 0
}

func signPack(args: [String]) -> Int32 {
    guard args.count == 5 else {
        print("usage: packsigner sign <pack.json> <private.key> <signed.json>")
        return 64
    }
    guard let privateKey = readPrivateKey(path: args[3]) else {
        print("sign: cannot read private key at \(args[3])")
        return 78
    }
    do {
        let packBytes = try Data(contentsOf: URL(fileURLWithPath: args[2]))
        // Structural validation only; the signature covers the raw bytes
        // so the file on disk is exactly what the runtime will decode.
        let pack = try JSONDecoder().decode(PackDocument.self, from: packBytes)
        let signature = try privateKey.signature(for: packBytes)
        let envelope = SignedEnvelope(payload: packBytes.base64EncodedString(),
                                      signature: signature.base64EncodedString())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let outData = try encoder.encode(envelope)
        try outData.write(to: URL(fileURLWithPath: args[4]))
        print("signed \(pack.rules.count) rules (version \(pack.version)) -> \(args[4])")
        return 0
    } catch let error as DecodingError {
        print("sign: pack JSON does not match the HookRulePack schema: \(error)")
        return 65
    } catch {
        print("sign: \(error)")
        return 74
    }
}

func verifyPack(args: [String]) -> Int32 {
    guard args.count == 4 else {
        print("usage: packsigner verify <signed.json> <public.key>")
        return 64
    }
    guard let publicKey = readPublicKey(path: args[3]) else {
        print("verify: cannot read public key at \(args[3])")
        return 78
    }
    // Mirrors HookRulePackLoader.load — any failure is a rejection.
    guard let signedData = try? Data(contentsOf: URL(fileURLWithPath: args[2])),
        let envelope = try? JSONDecoder().decode(SignedEnvelope.self, from: signedData),
        let payload = Data(base64Encoded: envelope.payload),
        let signature = Data(base64Encoded: envelope.signature),
        publicKey.isValidSignature(signature, for: payload),
        let pack = try? JSONDecoder().decode(PackDocument.self, from: payload) else {
        print("verify: REJECTED (bad envelope, bad signature, or bad pack schema)")
        return 65
    }
    print("verify: OK — \(pack.rules.count) rules, version \(pack.version)")
    return 0
}

func usage() -> Int32 {
    print("usage: packsigner genkeys <private.key> [public.key]")
    print("       packsigner sign <pack.json> <private.key> <signed.json>")
    print("       packsigner verify <signed.json> <public.key>")
    return 64
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else { exit(usage()) }

switch args[1] {
case "genkeys": exit(genkeys(args: args))
case "sign": exit(signPack(args: args))
case "verify": exit(verifyPack(args: args))
default: exit(usage())
}
