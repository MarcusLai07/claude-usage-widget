// Generates App/Resources/AppIcon.icns — the clay sunburst mark inside a
// radial progress ring on a dark gradient squircle.
//
// Usage:  swift Scripts/GenerateIcon.swift
// Requires: Xcode (iconutil). Re-run after tweaking, then rebuild.

import AppKit

let clay = NSColor(srgbRed: 217 / 255, green: 119 / 255, blue: 87 / 255, alpha: 1)
let clayLight = NSColor(srgbRed: 227 / 255, green: 144 / 255, blue: 111 / 255, alpha: 1)
let bgTop = NSColor(srgbRed: 0x2D / 255, green: 0x27 / 255, blue: 0x40 / 255, alpha: 1)
let bgBottom = NSColor(srgbRed: 0x10 / 255, green: 0x1D / 255, blue: 0x28 / 255, alpha: 1)

func draw(in ctx: CGContext, size s: CGFloat) {
    // Squircle plate on Apple's 824/1024 icon grid.
    let inset = s * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let plate = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225,
                       cornerHeight: rect.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()

    // Background gradient (top-left violet → bottom-right deep teal, like the
    // wireframe's dark board).
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = rect.width * 0.33
    let ringWidth = rect.width * 0.072

    // Ring track.
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    ctx.setLineWidth(ringWidth)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0,
               endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    // Progress arc — 270° sweep starting at 12 o'clock, round caps.
    ctx.setStrokeColor(clay.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(ringWidth)
    ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2,
               endAngle: .pi, clockwise: true)
    ctx.strokePath()

    // Sunburst mark — 12 rays, round caps.
    ctx.setStrokeColor(clayLight.cgColor)
    ctx.setLineWidth(rect.width * 0.045)
    let r1 = rect.width * 0.085
    let r2 = rect.width * 0.205
    for i in 0..<12 {
        let angle = CGFloat(i) * 30 * .pi / 180
        ctx.move(to: CGPoint(x: center.x + cos(angle) * r1, y: center.y + sin(angle) * r1))
        ctx.addLine(to: CGPoint(x: center.x + cos(angle) * r2, y: center.y + sin(angle) * r2))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(in: context.cgContext, size: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let iconset = repoRoot.appendingPathComponent("build-iconset/AppIcon.iconset")
let output = repoRoot.appendingPathComponent("App/Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset.deletingLastPathComponent())
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset.deletingLastPathComponent())

print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
exit(iconutil.terminationStatus)
