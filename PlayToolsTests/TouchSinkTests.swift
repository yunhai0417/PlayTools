//
//  TouchSinkTests.swift
//  PlayToolsTests
//
//  TouchSink seam semantics (OPTIMIZATION.md 2.5): session gating rules and
//  dispatch through a fake sink substituted for the production Toucher.
//

import XCTest
import UIKit

private struct RecordedTouchEvent {
    let point: CGPoint
    let phase: UITouch.Phase
    let actionName: String
    let keyName: String
}

private final class RecordingTouchSink: TouchSink {
    private(set) var events: [RecordedTouchEvent] = []
    var nextTid = 7

    func touchcam(point: CGPoint, phase: UITouch.Phase, tid: inout Int?,
                  actionName: String, keyName: String) {
        guard TouchSession.shouldEmit(phase: phase, tid: tid) else {
            return
        }
        if phase == .began {
            tid = TouchSession.allocatingTid
        }
        tid = phase == .ended ? -1 : nextTid
        tid = TouchSession.normalizeTid(tid!)
        events.append(RecordedTouchEvent(point: point, phase: phase,
                                         actionName: actionName, keyName: keyName))
    }
}

final class TouchSinkTests: XCTestCase {

    // MARK: session gating

    func testBeganEmitsWhenIdle() {
        XCTAssertTrue(TouchSession.shouldEmit(phase: .began, tid: nil))
    }

    func testBeganSuppressedWhileActive() {
        XCTAssertFalse(TouchSession.shouldEmit(phase: .began, tid: TouchSession.allocatingTid))
        XCTAssertFalse(TouchSession.shouldEmit(phase: .began, tid: 7))
    }

    func testMovedAndEndedEmitWhileActive() {
        XCTAssertTrue(TouchSession.shouldEmit(phase: .moved, tid: 7))
        XCTAssertTrue(TouchSession.shouldEmit(phase: .ended, tid: 7))
    }

    func testMovedAndEndedSuppressedWhenIdle() {
        XCTAssertFalse(TouchSession.shouldEmit(phase: .moved, tid: nil))
        XCTAssertFalse(TouchSession.shouldEmit(phase: .ended, tid: nil))
    }

    // MARK: tid lifecycle

    func testNegativeResultIdReleasesSession() {
        XCTAssertNil(TouchSession.normalizeTid(-1))
        XCTAssertNil(TouchSession.normalizeTid(-3))
    }

    func testNonNegativeResultIdKeepsSession() {
        XCTAssertEqual(TouchSession.normalizeTid(0), 0)
        XCTAssertEqual(TouchSession.normalizeTid(9), 9)
    }

    // MARK: dispatch through an injected fake sink

    func testFakeSinkReceivesBeginMoveEndSequence() {
        let sink: TouchSink = RecordingTouchSink()
        let recorder = sink as? RecordingTouchSink

        var tid: Int?
        sink.touchcam(point: CGPoint(x: 10, y: 20), phase: .began, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        XCTAssertEqual(recorder?.events.count, 1)
        XCTAssertNotNil(tid)

        sink.touchcam(point: CGPoint(x: 30, y: 40), phase: .moved, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        XCTAssertEqual(recorder?.events.count, 2)

        sink.touchcam(point: CGPoint(x: 30, y: 40), phase: .ended, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        XCTAssertEqual(recorder?.events.count, 3)
        XCTAssertNil(tid)
        XCTAssertEqual(recorder?.events.map({ $0.phase }),
                       [.began, .moved, .ended])
        XCTAssertEqual(recorder?.events.first?.point, CGPoint(x: 10, y: 20))
        XCTAssertEqual(recorder?.events.first?.actionName, "Button")
        XCTAssertEqual(recorder?.events.first?.keyName, "KeyA")
    }

    func testFakeSinkSuppressesDuplicateBeginAndOrphanEvents() {
        let sink: TouchSink = RecordingTouchSink()
        let recorder = sink as? RecordingTouchSink

        var tid: Int?
        // Orphan events with no active session are dropped.
        sink.touchcam(point: .zero, phase: .moved, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        sink.touchcam(point: .zero, phase: .ended, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        XCTAssertEqual(recorder?.events.count, 0)

        // Begin allocates; a second begin while active is dropped.
        sink.touchcam(point: .zero, phase: .began, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        sink.touchcam(point: .zero, phase: .began, tid: &tid,
                      actionName: "Button", keyName: "KeyA")
        XCTAssertEqual(recorder?.events.count, 1)
        XCTAssertEqual(recorder?.events.last?.phase, .began)
    }
}
