//
//  ScreenGeometryTests.swift
//  PlayToolsTests
//
//  Coverage for the pure display-geometry math (OPTIMIZATION.md 2.2):
//  aspect ratio matrix (16:9 / 4:3 / custom / square), size pairs, rect
//  rescaling with scaler, reversed variants, and the inverse-mode swap.
//

import XCTest

final class ScreenGeometryTests: XCTestCase {

    // MARK: Aspect ratio matrix

    func testAspectRatioLandscape169() {
        let geometry = ScreenGeometry(width: 1920, height: 1080)
        XCTAssertEqual(geometry.aspectRatio, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testAspectRatioPortrait169() {
        let geometry = ScreenGeometry(width: 1080, height: 1920)
        XCTAssertEqual(geometry.aspectRatio, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testAspectRatio43() {
        let geometry = ScreenGeometry(width: 1024, height: 768)
        XCTAssertEqual(geometry.aspectRatio, 4.0 / 3.0, accuracy: 0.0001)
    }

    func testAspectRatioCustom() {
        let geometry = ScreenGeometry(width: 2560, height: 1080)
        XCTAssertEqual(geometry.aspectRatio, 64.0 / 27.0, accuracy: 0.0001)
    }

    func testAspectRatioSquareIsOne() {
        let geometry = ScreenGeometry(width: 1000, height: 1000)
        XCTAssertEqual(geometry.aspectRatio, 1.0, accuracy: 0.000001)
    }

    // MARK: Size pairs

    func testSizeMatchesConfiguredDimensions() {
        let geometry = ScreenGeometry(width: 1920, height: 1080)
        XCTAssertEqual(geometry.size, CGSize(width: 1920, height: 1080))
    }

    func testSizeReversedSwapsDimensions() {
        let geometry = ScreenGeometry(width: 1920, height: 1080)
        XCTAssertEqual(geometry.sizeReversed, CGSize(width: 1080, height: 1920))
    }

    // MARK: Rect rescaling

    func testRectKeepsOriginAndAppliesDimensions() {
        let geometry = ScreenGeometry(width: 1920, height: 1080)
        let rect = geometry.rect(CGRect(x: 3, y: 4, width: 10, height: 10))
        XCTAssertEqual(rect, CGRect(x: 3, y: 4, width: 1920, height: 1080))
    }

    func testRectAppliesScalerAsMultiplier() {
        let geometry = ScreenGeometry(width: 1920, height: 1080, scaler: 2)
        let rect = geometry.rect(CGRect(x: 0, y: 0, width: 10, height: 10), multiplier: geometry.scaler)
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 3840, height: 2160))
    }

    func testRectReversedSwapsDimensionsAndKeepsOrigin() {
        let geometry = ScreenGeometry(width: 1920, height: 1080)
        let rect = geometry.rectReversed(CGRect(x: 5, y: 6, width: 10, height: 10))
        XCTAssertEqual(rect, CGRect(x: 5, y: 6, width: 1080, height: 1920))
    }

    // MARK: Inverse mode (configured size arrives pre-swapped by the factory)

    func testInverseModeFactorySwapSemantics() {
        // inverseScreenValues && adaptiveDisplay: the factory in PlayScreen.swift
        // feeds (configuredHeight, configuredWidth) into the geometry.
        let configuredWidth: CGFloat = 1920
        let configuredHeight: CGFloat = 1080
        let geometry = ScreenGeometry(width: configuredHeight, height: configuredWidth)
        XCTAssertEqual(geometry.size, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(geometry.sizeReversed, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(geometry.rectReversed(CGRect(x: 0, y: 0, width: 0, height: 0)),
                       CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }
}
