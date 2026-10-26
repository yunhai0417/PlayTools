//
//  KeymapCoordinates.swift
//  PlayTools
//
//  Pure conversion between keymap-relative coordinates (0...1) and screen
//  points (OPTIMIZATION.md 2.3). The live screen size is injected, so inverse
//  mode and resolution changes are just different inputs. Dual-compiled into
//  PlayToolsTests.
//

import CoreGraphics

struct KeymapCoordinates {

    /// Live screen bounds in points.
    let screenWidth: CGFloat
    let screenHeight: CGFloat

    init(screenWidth: CGFloat, screenHeight: CGFloat) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }

    /// Longer side, matching PlayScreen.max.
    var maxSide: CGFloat {
        Swift.max(screenWidth, screenHeight)
    }

    /// One percent of the longer side — the unit keymap element sizes use.
    var percent: CGFloat {
        maxSide / 100
    }

    // MARK: Relative (0...1) -> absolute points

    func absolute(x relative: CGFloat) -> CGFloat {
        relative * screenWidth
    }

    func absolute(y relative: CGFloat) -> CGFloat {
        relative * screenHeight
    }

    func absolute(size relative: CGFloat) -> CGFloat {
        relative * percent
    }

    // MARK: Absolute points -> relative (0...1)

    func relative(x absolute: CGFloat) -> CGFloat {
        absolute / screenWidth
    }

    func relative(y absolute: CGFloat) -> CGFloat {
        absolute / screenHeight
    }

    func relative(size absolute: CGFloat) -> CGFloat {
        absolute / percent
    }
}
