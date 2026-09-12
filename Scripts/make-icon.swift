#!/usr/bin/env swift
// Renders Resources/AppIcon.icns from code — no design tool in the loop.
// Usage: swift Scripts/make-icon.swift <output.icns>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MaadyCyclop.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let px = Int(s)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024

    // Apple-style squircle. Charcoal body, not pitch black — same register as
    // Settings / Shortcuts tiles, so the notch and the mark both have somewhere
    // to sit.
    let body = CGRect(x: 88 * k, y: 88 * k, width: 848 * k, height: 848 * k)
    let corner = 190 * k
    let squircle = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
    ctx.fillPath()
    ctx.addPath(squircle)
    ctx.clip()

    // Hardware notch: flush with the top, darker than the tile, same family
    // of corners as the real housing.
    let notchW = 292 * k
    let notchH = 78 * k
    let notchR = 30 * k
    let nx = body.midX - notchW / 2
    let ny = body.maxY - notchH
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: nx, y: body.maxY))
    notch.addLine(to: CGPoint(x: nx, y: ny + notchR))
    notch.addQuadCurve(to: CGPoint(x: nx + notchR, y: ny), control: CGPoint(x: nx, y: ny))
    notch.addLine(to: CGPoint(x: nx + notchW - notchR, y: ny))
    notch.addQuadCurve(to: CGPoint(x: nx + notchW, y: ny + notchR), control: CGPoint(x: nx + notchW, y: ny))
    notch.addLine(to: CGPoint(x: nx + notchW, y: body.maxY))
    notch.closeSubpath()
    ctx.addPath(notch)
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1))
    ctx.fillPath()

    // One eye, drawn like an SF Symbol: a white almond, a dark pupil, a
    // single highlight. The notch above is the brow — that is the creature.
    let cx = body.midX
    let cy = body.midY - 36 * k
    let eyeW = 340 * k
    let eyeH = 188 * k
    let lid = CGMutablePath()
    lid.move(to: CGPoint(x: cx - eyeW / 2, y: cy))
    lid.addQuadCurve(to: CGPoint(x: cx + eyeW / 2, y: cy), control: CGPoint(x: cx, y: cy + eyeH / 2))
    lid.addQuadCurve(to: CGPoint(x: cx - eyeW / 2, y: cy), control: CGPoint(x: cx, y: cy - eyeH / 2))
    lid.closeSubpath()
    ctx.addPath(lid)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()

    let pupil = 118 * k
    ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - pupil / 2, y: cy - pupil / 2, width: pupil, height: pupil))
    let glint = 28 * k
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx + 10 * k, y: cy + 18 * k, width: glint, height: glint))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (size, name) in [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
] {
    let data = draw(size: CGFloat(size)).representation(using: .png, properties: [:])!
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outPath]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(outPath)" : "iconutil failed")
