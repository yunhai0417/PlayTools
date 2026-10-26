//
//  PlayKeychainTests.swift
//  PlayToolsTests
//
//  PlayChain keychain emulation semantics (OPTIMIZATION.md 2.4):
//  add / copyMatching / update / delete plist semantics on top of an
//  isolated temp-directory SQLite database (no real PlayChain is touched).
//

import XCTest

final class PlayKeychainTests: XCTestCase {

    private var tempDirectory: URL!
    private var database: PlayKeychainDB!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("playchain-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        database = PlayKeychainDB(directoryURL: tempDirectory)
        PlayKeychain.playChainDB = database
    }

    override func tearDown() {
        PlayKeychain.playChainDB = .shared
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: Helpers

    private func makeItem(account: String, service: String = "svc", secret: String = "secret") -> NSDictionary {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessGroup as String: "test.group",
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecValueData as String: Data(secret.utf8)
        ]
    }

    private func query(account: String, service: String = "svc") -> NSMutableDictionary {
        NSMutableDictionary(dictionary: [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessGroup as String: "test.group",
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ])
    }

    @discardableResult
    private func addItem(_ item: NSDictionary) -> OSStatus {
        PlayKeychain.add(item, result: nil)
    }

    private func copyData(_ queryDict: NSDictionary) -> (OSStatus, Data?) {
        var result: Unmanaged<CFTypeRef>?
        let status = PlayKeychain.copyMatching(queryDict, result: &result)
        let data = result?.takeRetainedValue() as? Data
        return (status, data)
    }

    // MARK: add + query round trip

    func testAddPersistsItemVisibleToDirectQuery() {
        XCTAssertEqual(addItem(makeItem(account: "user")), errSecSuccess)

        let rows = database?.query(query(account: "user"))
        XCTAssertEqual(rows?.count, 1)
        let row = rows?.first
        XCTAssertEqual(row?[kSecAttrAccount as String] as? String, "user")
        XCTAssertEqual(row?[kSecValueData as String] as? Data, Data("secret".utf8))
    }

    // MARK: copyMatching semantics

    func testCopyMatchingReturnsStoredData() {
        addItem(makeItem(account: "user"))

        var queryDict = query(account: "user")
        queryDict.setValue(true, forKey: kSecReturnData as String)
        let (status, data) = copyData(queryDict)

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual(data, Data("secret".utf8))
    }

    func testCopyMatchingWithoutReturnFlagsIsExistenceCheck() {
        XCTAssertEqual(addItem(makeItem(account: "user")), errSecSuccess)

        var result: Unmanaged<CFTypeRef>?
        let status = PlayKeychain.copyMatching(query(account: "user"), result: &result)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNil(result)
    }

    func testCopyMatchingMissingItemReturnsItemNotFound() {
        var queryDict = query(account: "nobody")
        queryDict.setValue(true, forKey: kSecReturnData as String)
        let (status, data) = copyData(queryDict)
        XCTAssertEqual(status, errSecItemNotFound)
        XCTAssertNil(data)
    }

    func testCopyMatchingAttributesStripValueData() {
        addItem(makeItem(account: "user"))

        var queryDict = query(account: "user")
        queryDict.setValue(true, forKey: kSecReturnAttributes as String)
        var result: Unmanaged<CFTypeRef>?
        let status = PlayKeychain.copyMatching(queryDict, result: &result)

        XCTAssertEqual(status, errSecSuccess)
        let dict = result?.takeRetainedValue() as? NSDictionary
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?[kSecAttrAccount as String] as? String, "user")
        XCTAssertNil(dict?[kSecValueData as String])
    }

    func testCopyMatchingMatchLimitAllReturnsEveryMatch() {
        addItem(makeItem(account: "user1", secret: "one"))
        addItem(makeItem(account: "user2", secret: "two"))

        let queryDict = NSMutableDictionary(dictionary: [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccessGroup as String: "test.group",
            kSecAttrService as String: "svc",
            kSecMatchLimit as String: kSecMatchLimitAll as String,
            kSecReturnData as String: true
        ])
        var result: Unmanaged<CFTypeRef>?
        let status = PlayKeychain.copyMatching(queryDict, result: &result)

        XCTAssertEqual(status, errSecSuccess)
        let values = result?.takeRetainedValue() as? [Data]
        XCTAssertEqual(Set(values ?? []), Set([Data("one".utf8), Data("two".utf8)]))
    }

    // MARK: update semantics

    func testUpdateReplacesStoredData() {
        addItem(makeItem(account: "user"))

        var updateAttributes: NSDictionary = [kSecValueData as String: Data("rotated".utf8)]
        let status = PlayKeychain.update(query(account: "user"), attributesToUpdate: updateAttributes)
        XCTAssertEqual(status, errSecSuccess)

        var queryDict = query(account: "user")
        queryDict.setValue(true, forKey: kSecReturnData as String)
        let (queryStatus, data) = copyData(queryDict)
        XCTAssertEqual(queryStatus, errSecSuccess)
        XCTAssertEqual(data, Data("rotated".utf8))
    }

    func testUpdateMissingItemReturnsItemNotFound() {
        let status = PlayKeychain.update(query(account: "ghost"),
                                         attributesToUpdate: [kSecValueData as String: Data()])
        XCTAssertEqual(status, errSecItemNotFound)
    }

    // MARK: delete semantics

    func testDeleteRemovesItem() {
        addItem(makeItem(account: "user"))
        XCTAssertEqual(PlayKeychain.delete(query(account: "user")), errSecSuccess)

        var queryDict = query(account: "user")
        queryDict.setValue(true, forKey: kSecReturnData as String)
        let (status, _) = copyData(queryDict)
        XCTAssertEqual(status, errSecItemNotFound)
    }

    func testDeleteMissingItemReturnsItemNotFound() {
        XCTAssertEqual(PlayKeychain.delete(query(account: "ghost")), errSecItemNotFound)
    }

    // MARK: SQLite persistence

    func testItemsPersistAcrossDatabaseInstances() {
        addItem(makeItem(account: "user"))

        // A fresh instance over the same directory sees the same item.
        let reopened = PlayKeychainDB(directoryURL: tempDirectory)
        PlayKeychain.playChainDB = reopened
        var queryDict = query(account: "user")
        queryDict.setValue(true, forKey: kSecReturnData as String)
        let (status, data) = copyData(queryDict)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual(data, Data("secret".utf8))
    }
}
