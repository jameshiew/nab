#!/usr/bin/env swift

// Generates the Nab app icon: a tray glyph, echoing the menu bar icon, on a
// blue squircle. Drawn with Core Graphics so the icon lives in the repo as
// code rather than as an opaque binary asset.
//
// Usage: Scripts/generate-app-icon.swift [output-iconset-directory]
// Defaults to Resources/AppIcon.iconset.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Geometry

/// Everything is laid out against a 1024pt canvas and scaled down from there.
private let canvas: CGFloat = 1024

/// macOS icon grid: the rounded-square body is 824pt centred in the canvas,
/// leaving the surrounding margin for the shadow.
private enum Body {
    static let inset: CGFloat = 100
    static let size: CGFloat = canvas - 2 * inset
    static let cornerRadius: CGFloat = 185.4
    static var rect: CGRect { CGRect(x: inset, y: inset, width: size, height: size) }
}

/// Tray proportions, in top-left-origin coordinates (`y` grows downward), which
/// is how the shape is easiest to reason about.
private enum Tray {
    static let left: CGFloat = 216
    static let right: CGFloat = canvas - left
    static let centerX: CGFloat = canvas / 2

    /// Top edge of the tray's back wall, and the narrower span it covers.
    /// Sitting a little above the body's centre reads as centred, since the
    /// solid front panel carries most of the glyph's visual weight.
    static let top: CGFloat = 304
    static let topLeft: CGFloat = 336
    static let topRight: CGFloat = canvas - topLeft

    /// Where the sloped walls meet the front panel — the tray's "lip".
    static let lip: CGFloat = 528
    static let bottom: CGFloat = 718

    /// Semicircular scoop out of the lip, the detail that makes the shape read
    /// as a tray rather than a plain box.
    static let notchRadius: CGFloat = 84

    static let strokeWidth: CGFloat = 44
    static let cornerRadius: CGFloat = 58
    static let lipCornerRadius: CGFloat = 30
    static let topCornerRadius: CGFloat = 52
}

/// Flips a top-left-origin point into Core Graphics' bottom-left-origin space.
private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: canvas - y)
}

// MARK: - Paths

/// The squircle body, using the same continuous curvature as macOS app icons.
private func bodyPath() -> CGPath {
    Path(
        roundedRect: Body.rect,
        cornerSize: CGSize(width: Body.cornerRadius, height: Body.cornerRadius),
        style: .continuous
    ).cgPath
}

/// Outline of the whole tray: front panel walls plus the sloped back wall.
private func trayOutlinePath() -> CGPath {
    let corners: [(point: CGPoint, radius: CGFloat)] = [
        (pt(Tray.left, Tray.bottom), Tray.cornerRadius),
        (pt(Tray.left, Tray.lip), Tray.lipCornerRadius),
        (pt(Tray.topLeft, Tray.top), Tray.topCornerRadius),
        (pt(Tray.topRight, Tray.top), Tray.topCornerRadius),
        (pt(Tray.right, Tray.lip), Tray.lipCornerRadius),
        (pt(Tray.right, Tray.bottom), Tray.cornerRadius),
    ]
    let path = CGMutablePath()
    // Start midway along the bottom edge so the first arc has a straight run-up.
    path.move(to: pt(Tray.centerX, Tray.bottom))
    for (index, corner) in corners.enumerated() {
        let next = corners[(index + 1) % corners.count].point
        path.addArc(tangent1End: corner.point, tangent2End: next, radius: corner.radius)
    }
    path.closeSubpath()
    return path
}

/// The solid front panel, with the notch scooped out of its top edge.
private func trayPanelPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: pt(Tray.left, Tray.lip))
    path.addLine(to: pt(Tray.centerX - Tray.notchRadius, Tray.lip))
    path.addArc(
        center: pt(Tray.centerX, Tray.lip),
        radius: Tray.notchRadius,
        startAngle: .pi,
        endAngle: 2 * .pi,
        clockwise: false
    )
    path.addLine(to: pt(Tray.right, Tray.lip))
    path.addArc(
        tangent1End: pt(Tray.right, Tray.bottom),
        tangent2End: pt(Tray.left, Tray.bottom),
        radius: Tray.cornerRadius
    )
    path.addArc(
        tangent1End: pt(Tray.left, Tray.bottom),
        tangent2End: pt(Tray.left, Tray.lip),
        radius: Tray.cornerRadius
    )
    path.closeSubpath()
    return path
}

// MARK: - Drawing

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

private func drawIcon(in ctx: CGContext) {
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let body = bodyPath()

    // Soft contact shadow, matching how macOS icons sit on a surface.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: rgb(0, 0.04, 0.16, 0.4))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0, 0, 0, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()

    // Blue gradient, light at the top edge.
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgb(0.35, 0.63, 1.0), rgb(0.11, 0.36, 0.93), rgb(0.05, 0.20, 0.74)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: pt(0, Body.inset),
        end: pt(0, canvas - Body.inset),
        options: []
    )

    // Gloss: a wide, very soft highlight across the upper half.
    let gloss = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gloss,
        start: pt(0, Body.inset),
        end: pt(0, canvas * 0.62),
        options: []
    )

    drawTray(in: ctx)
    ctx.restoreGState()

    // Hairline rim so the body keeps a defined edge on light backgrounds.
    ctx.addPath(body)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()
}

private func drawTray(in ctx: CGContext) {
    // Drop the tray onto the gradient so it lifts off the background slightly.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0, 0.06, 0.28, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    ctx.setFillColor(rgb(1, 1, 1))
    ctx.addPath(trayPanelPath())
    ctx.fillPath()

    ctx.setStrokeColor(rgb(1, 1, 1))
    ctx.setLineWidth(Tray.strokeWidth)
    ctx.setLineJoin(.round)
    ctx.addPath(trayOutlinePath())
    ctx.strokePath()

    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: - Output

private func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        fatalError("could not create a drawing context")
    }
    let scale = CGFloat(pixels) / canvas
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG at \(pixels)px")
    }
    return data
}

/// The ten representations macOS asks for, as (points, scale) pairs.
private let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

private func filename(points: Int, scale: Int) -> String {
    "icon_\(points)x\(points)\(scale == 1 ? "" : "@\(scale)x").png"
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "Resources/AppIcon.iconset"
)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for variant in variants {
    let name = filename(points: variant.points, scale: variant.scale)
    try renderPNG(pixels: variant.points * variant.scale).write(to: outputDirectory.appending(path: name))
    print("wrote \(name)")
}
