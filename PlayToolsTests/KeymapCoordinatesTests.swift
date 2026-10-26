//
//  KeymapCoordinatesTests.swift
//  PlayToolsTests
//
//  Coverage for keymap relative (0...1) <-> absolute point conversion
//  (OPTIMIZATION.md 2.3): axis mapping, size percent unit, round trips,
//  resolution changes and inverse (portrait) layouts.
//

import XCTest

final class KeymapCoordinatesTests: XCTestCase {

    let landscape = KeymapCoordinates(screenWidth: 1920, screenHeight: 1080)
    let portrait = KeymapCoordinates(screenWidth: 1080, screenHeight: 1920)

    // MARK: Axis mapping

    func testAbsoluteAxesMapToOwnDimension() {
        let coords = landscape
        XCTAssertEqual(coords.absolute(x: 0.5), 960)
        XCTAssertEqual(coords.absolute(y: 0.25), 270)
    }

    func testRelativeAxesMapToOwnDimension() {
        let coords = landscape
        XCTAssertEqual(coords.relative(x: 960), 0.5, accuracy: 0.000001)
        XCTAssertEqual(coords.relative(y: 270), 0.25, accuracy: 0.000001)
    }

    // MARK: Size percent unit

    func testPercentIsOnePercentOfLongerSide() {
        XCTAssertEqual(landscape.percent, 19.2, accuracy: 0.000001)
        XCTAssertEqual(portrait.percent, 19.2, accuracy: 0.000001)
    }

    func testSizeConversionUsesPercentUnit() {
        XCTAssertEqual(landscape.absolute(size: 10), 192)
        XCTAssertEqual(landscape.relative(size: 192), 10, accuracy: 0.000001)
    }

    // MARK: Round trips

    func testAxisRoundTrips() {
        XCTAssertEqual(landscape.relative(x: landscape.absolute(x: 0.3)), 0.3, accuracy: 0.000001)
        XCTAssertEqual(landscape.relative(y: landscape.absolute(y: 0.7)), 0.7, accuracy: 0.000001)
    }

    func testSizeRoundTrip() {
        XCTAssertEqual(landscape.relative(size: landscape.absolute(size: 12)), 12, accuracy: 0.000001)
    }

    // MARK: Resolution changes

    func testSameRelativeCoordinateAcrossResolutions() {
        // A keymap stored at 0.5/0.5 lands on different points per resolution,
        // and converts back to the same relative coordinate everywhere.
        let resolutions = [
            KeymapCoordinates(screenWidth: 1920, screenHeight: 1080),
            KeymapCoordinates(screenWidth: 1024, screenHeight: 768),
            KeymapCoordinates(screenWidth: 2732, screenHeight: 2048)
        ]
        for coords in resolutions {
            let point = CGPoint(x: coords.absolute(x: 0.5), y: coords.absolute(y: 0.5))
            XCTAssertEqual(point.x, coords.screenWidth / 2, accuracy: 0.000001)
            XCTAssertEqual(point.y, coords.screenHeight / 2, accuracy: 0.000001)
            XCTAssertEqual(coords.relative(x: point.x), 0.5, accuracy: 0.000001)
            XCTAssertEqual(coords.relative(y: point.y), 0.5, accuracy: 0.000001)
        }
    }

    // MARK: Inverse (portrait) layout

    func testInversePortraitLayoutSwapsAxes() {
        // inverseScreenValues feeds a portrait live screen: X maps to the short
        // side, Y to the long side.
        XCTAssertEqual(portrait.absolute(x: 0.5), 540)
        XCTAssertEqual(portrait.absolute(y: 0.5), 960)
        XCTAssertEqual(portrait.relative(y: 960), 0.5, accuracy: 0.000001)
    }

    func testExtremeBounds() {
        XCTAssertEqual(landscape.absolute(x: 0), 0)
        XCTAssertEqual(landscape.absolute(x: 1), 1920)
        XCTAssertEqual(landscape.absolute(y: 1), 1080)
    }
}
