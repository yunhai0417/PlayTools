//
//  PlayToolsContractsTests.swift
//  PlayToolsTests
//
//  AppSettingsData decode compatibility rules (OPTIMIZATION.md 3.1/3.2):
//  partial plists must keep present values and default the rest, instead of
//  failing the whole decode.
//

import XCTest

final class PlayToolsContractsTests: XCTestCase {

    private func plistData(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testDecodePartialPlistKeepsPresentValuesAndDefaults() throws {
        let data = try plistData(["windowWidth": 1280, "hideTitleBar": true])
        let decoded = try PropertyListDecoder().decode(AppSettingsData.self, from: data)

        XCTAssertEqual(decoded.windowWidth, 1280)
        XCTAssertTrue(decoded.hideTitleBar)
        XCTAssertEqual(decoded.windowHeight, 1080)
        XCTAssertEqual(decoded.iosDeviceModel, "iPad13,8")
        XCTAssertEqual(decoded.resolution, 2)
        XCTAssertFalse(decoded.safeMode)
    }

    func testDecodeEmptyPlistYieldsDefaults() throws {
        let data = try plistData([:])
        let decoded = try PropertyListDecoder().decode(AppSettingsData.self, from: data)

        XCTAssertTrue(decoded.keymapping)
        XCTAssertEqual(decoded.sensitivity, 50)
        XCTAssertEqual(decoded.version, "2.0.0")
        XCTAssertTrue(decoded.discordActivity.enable)
        XCTAssertEqual(decoded.discordActivity.applicationID, "")
    }

    func testCorruptDiscordActivityFallsBackToDefault() throws {
        let data = try plistData(["discordActivity": ["enable": "not-a-bool"]])
        let decoded = try PropertyListDecoder().decode(AppSettingsData.self, from: data)

        XCTAssertTrue(decoded.discordActivity.enable)
        XCTAssertEqual(decoded.discordActivity.applicationID, "")
    }

    func testEncodeDecodeRoundTripPreservesValues() throws {
        var settings = AppSettingsData()
        settings.windowWidth = 800
        settings.sensitivity = 75
        settings.resolution = 6
        settings.resizableAspectRatioWidth = 16
        settings.resizableAspectRatioHeight = 9

        let data = try PropertyListEncoder().encode(settings)
        let decoded = try PropertyListDecoder().decode(AppSettingsData.self, from: data)

        XCTAssertEqual(decoded.windowWidth, 800)
        XCTAssertEqual(decoded.sensitivity, 75)
        XCTAssertEqual(decoded.resolution, 6)
        XCTAssertEqual(decoded.resizableAspectRatioWidth, 16)
        XCTAssertEqual(decoded.resizableAspectRatioHeight, 9)
    }
}
