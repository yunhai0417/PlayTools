//
//  PlayToolsTests.swift
//  PlayToolsTests
//
//  Logic-test scaffold (OPTIMIZATION.md 2.1). Pure-logic sources under test are
//  compiled into this target directly (dual compilation), so the PlayTools
//  framework — whose +load/constructors interpose system calls — is never
//  loaded into the test runner.
//

import XCTest

final class PlayToolsTests: XCTestCase {

    func testScaffoldRuns() {
        XCTAssertTrue(true, "logic-test target is wired up")
    }
}
