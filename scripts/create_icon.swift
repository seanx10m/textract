#!/usr/bin/env swift
import Cocoa

func createAppIcon(pixelSize: Int) -> NSImage {
    let s = CGFloat(pixelSize)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    // Dark background
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor(red: 0.08, green: 0.08, blue: 0.14, alpha: 1).setFill()
    bg.fill()

    // Subtle gradient overlay
    if let gradient = NSGradient(starting: NSColor(white: 1, alpha: 0.06), ending: NSColor(white: 1, alpha: 0)) {
        gradient.draw(in: bg, angle: -45)
    }

    // "T" letter
    let fontSize = s * 0.48
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let str = NSAttributedString(string: "T", attributes: [
        .font: font,
        .foregroundColor: NSColor.white
    ])
    let sz = str.size()
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2 - s * 0.01))

    // Viewfinder corners (blue accent)
    let margin = s * 0.2
    let cl = s * 0.13
    let lw = s * 0.028

    ctx.setStrokeColor(CGColor(srgbRed: 0.35, green: 0.6, blue: 1.0, alpha: 0.95))
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)

    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: margin, y: s-margin-cl), CGPoint(x: margin, y: s-margin), CGPoint(x: margin+cl, y: s-margin)),
        (CGPoint(x: s-margin-cl, y: s-margin), CGPoint(x: s-margin, y: s-margin), CGPoint(x: s-margin, y: s-margin-cl)),
        (CGPoint(x: margin, y: margin+cl), CGPoint(x: margin, y: margin), CGPoint(x: margin+cl, y: margin)),
        (CGPoint(x: s-margin-cl, y: margin), CGPoint(x: s-margin, y: margin), CGPoint(x: s-margin, y: margin+cl)),
    ]
    for (a, b, c) in corners {
        ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c)
    }
    ctx.strokePath()

    img.unlockFocus()
    return img
}

// Generate .iconset
let iconsetDir = "build/Textract.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
for size in sizes {
    for scale in [1, 2] {
        let px = size * scale
        let img = createAppIcon(pixelSize: px)
        guard let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else { continue }
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
    }
}

print("Created iconset at \(iconsetDir)")
