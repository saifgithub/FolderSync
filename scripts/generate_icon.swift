#!/usr/bin/env swift
// Generates AppIcon.icns for Tandem.
// Design: two folder icons with circular sync arrows, blue→teal gradient background.
// Usage:  swift scripts/generate_icon.swift [output-dir]

import Foundation
import CoreGraphics
import ImageIO

func drawIcon(size: Int) -> CGImage {
    let s  = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // ── Background rounded rect + gradient ──────────────────────────────────
    let radius = s * 0.22
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(
        in: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: radius, cornerHeight: radius
    )
    ctx.addPath(bgPath)
    ctx.clip()

    let gc  = [CGColor(red: 0.14, green: 0.44, blue: 0.90, alpha: 1),
               CGColor(red: 0.05, green: 0.70, blue: 0.73, alpha: 1)] as CFArray
    let lo: [CGFloat] = [0, 1]
    let g1  = CGGradient(colorsSpace: cs, colors: gc, locations: lo)!
    ctx.drawLinearGradient(g1,
        start: CGPoint(x: s * 0.2, y: s),
        end:   CGPoint(x: s * 0.8, y: 0), options: [])

    let hc  = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
               CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
    let g2  = CGGradient(colorsSpace: cs, colors: hc, locations: lo)!
    ctx.drawLinearGradient(g2,
        start: CGPoint(x: s / 2, y: s),
        end:   CGPoint(x: s / 2, y: s * 0.45), options: [])
    ctx.resetClip()

    // ── Folder path helper ──────────────────────────────────────────────────
    func folder(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGPath {
        let tabW = w * 0.40
        let tabH = h * 0.20
        let cr   = h * 0.10
        let tc   = tabH * 0.55
        let p    = CGMutablePath()
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y))
        p.addLine(to: CGPoint(x: x + w, y: y + h - tabH))
        p.addArc(center: CGPoint(x: x + w - cr, y: y + h - tabH - cr),
                 radius: cr, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        p.addLine(to: CGPoint(x: x + tabW + tc, y: y + h - tabH))
        p.addArc(center: CGPoint(x: x + tabW, y: y + h - tabH + tc),
                 radius: tc, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        p.addLine(to: CGPoint(x: x + cr, y: y + h))
        p.addArc(center: CGPoint(x: x + cr, y: y + h - cr),
                 radius: cr, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
        p.addLine(to: CGPoint(x: x, y: y))
        p.closeSubpath()
        return p
    }

    let fW = s * 0.33
    let fH = s * 0.27
    let fY = s * 0.33

    // ── Left folder ─────────────────────────────────────────────────────────
    let lp = folder(x: s * 0.10, y: fY, w: fW, h: fH)
    ctx.addPath(lp)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.30))
    ctx.fillPath()
    ctx.addPath(lp)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
    ctx.setLineWidth(s * 0.026)
    ctx.strokePath()

    // ── Right folder ─────────────────────────────────────────────────────────
    let rp = folder(x: s * 0.57, y: fY, w: fW, h: fH)
    ctx.addPath(rp)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.fillPath()
    ctx.addPath(rp)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
    ctx.setLineWidth(s * 0.026)
    ctx.strokePath()

    // ── Sync arrows (↻ centred between folders) ──────────────────────────────
    let cx = s * 0.50
    let cy = fY + fH * 0.48
    let ar = s * 0.115
    let lw = s * 0.048
    let aw = s * 0.075

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)

    // Top arc CW 195° → 15°
    let ts: CGFloat = 195 * .pi / 180
    let te: CGFloat =  15 * .pi / 180
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: ar,
               startAngle: ts, endAngle: te, clockwise: true)
    ctx.strokePath()
    let tx = cx + ar * cos(te)
    let ty = cy + ar * sin(te)
    let tt = te + (.pi / 2)
    ctx.move(to: CGPoint(x: tx, y: ty))
    ctx.addLine(to: CGPoint(x: tx + aw * cos(tt + .pi * 0.75),
                            y: ty + aw * sin(tt + .pi * 0.75)))
    ctx.move(to: CGPoint(x: tx, y: ty))
    ctx.addLine(to: CGPoint(x: tx + aw * cos(tt - .pi * 0.75),
                            y: ty + aw * sin(tt - .pi * 0.75)))
    ctx.strokePath()

    // Bottom arc CCW 345° → 165°
    let bs: CGFloat = 345 * .pi / 180
    let be: CGFloat = 165 * .pi / 180
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: ar,
               startAngle: bs, endAngle: be, clockwise: false)
    ctx.strokePath()
    let bx = cx + ar * cos(be)
    let by = cy + ar * sin(be)
    let bt = be - (.pi / 2)
    ctx.move(to: CGPoint(x: bx, y: by))
    ctx.addLine(to: CGPoint(x: bx + aw * cos(bt + .pi * 0.75),
                            y: by + aw * sin(bt + .pi * 0.75)))
    ctx.move(to: CGPoint(x: bx, y: by))
    ctx.addLine(to: CGPoint(x: bx + aw * cos(bt - .pi * 0.75),
                            y: by + aw * sin(bt - .pi * 0.75)))
    ctx.strokePath()

    return ctx.makeImage()!
}

// ── Save PNG ──────────────────────────────────────────────────────────────────

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dst = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)
    else { fatalError("Cannot create image destination at \(path)") }
    CGImageDestinationAddImage(dst, image, nil)
    guard CGImageDestinationFinalize(dst) else { fatalError("Finalize failed: \(path)") }
}

// ── Main ──────────────────────────────────────────────────────────────────────

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(
    atPath: iconset, withIntermediateDirectories: true, attributes: nil
)

let specs: [(Int, String)] = [
    (16,   "icon_16x16"),
    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),
    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),
    (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),
    (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),
    (1024, "icon_512x512@2x"),
]

for (sz, name) in specs {
    let path = (iconset as NSString).appendingPathComponent("\(name).png")
    savePNG(drawIcon(size: sz), to: path)
    print("  ✓ \(name).png  (\(sz)×\(sz))")
}
print("✓ iconset at \(iconset)")
