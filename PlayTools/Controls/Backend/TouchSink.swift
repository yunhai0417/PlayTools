//
//  TouchSink.swift
//  PlayTools
//
//  Seam between action logic and the fake-touch backend (OPTIMIZATION.md 2.5).
//  Production injects `Toucher` (see the `touchSink` global in Toucher.swift);
//  the logic layer depends on this protocol, so tests can substitute a fake
//  sink. Dual-compiled into PlayToolsTests.
//

import Foundation
import UIKit

protocol TouchSink: AnyObject {
    func touchcam(point: CGPoint, phase: UITouch.Phase, tid: inout Int?,
                  actionName: String, keyName: String)
}

/// Pure per-session gating semantics shared by sinks:
/// `began` allocates a touch id and is suppressed while one is active;
/// `moved`/`ended` are suppressed while none is active; a negative result
/// id from the backend releases the session.
enum TouchSession {
    /// Sentinel tid assigned before emitting a begin event.
    static let allocatingTid = -1

    static func shouldEmit(phase: UITouch.Phase, tid: Int?) -> Bool {
        if phase == .began {
            return tid == nil
        }
        return tid != nil
    }

    static func normalizeTid(_ newTid: Int) -> Int? {
        newTid < 0 ? nil : newTid
    }
}
