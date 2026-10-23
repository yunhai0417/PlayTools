//
//  ScreenGeometry.swift
//  PlayTools
//
//  Pure display-geometry math for the swizzled screen family (OPTIMIZATION.md 2.2).
//  No PlaySettings / UIScreen / AKInterface access: every parameter is injected,
//  so this file is dual-compiled into PlayToolsTests for full unit coverage.
//

import CoreGraphics

struct ScreenGeometry {

    /// Effective window size in points (already swapped for inverse mode).
    let width: CGFloat
    let height: CGFloat
    /// Custom pixel scaler used by the nativeBounds/nativeScale hooks.
    let scaler: CGFloat

    init(width: CGFloat, height: CGFloat, scaler: CGFloat = 1) {
        self.width = width
        self.height = height
        self.scaler = scaler
    }

    /// Longer side over shorter side (1.0 for a square).
    var aspectRatio: CGFloat {
        width > height ? width / height : height / width
    }

    /// (width, height) as configured.
    var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// (height, width) — the reversed size the FBSSceneSettings hooks report.
    var sizeReversed: CGSize {
        CGSize(width: height, height: width)
    }

    /// Rescales the rect to the configured size, keeping its origin.
    func rect(_ rect: CGRect, multiplier: CGFloat = 1) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: width * multiplier, height: height * multiplier)
    }

    /// Rescales the rect to the reversed size, keeping its origin.
    func rectReversed(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: height, height: width)
    }
}
