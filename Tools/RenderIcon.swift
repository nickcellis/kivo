import AppKit

// Kivo's icon: the capacity ring the app itself draws.
//
// A broom or a sparkle would say "cleaner" and nothing else. This says
// what Kivo shows you the moment it opens: how full the disk is. The solid
// arc is used space, the faint one is what's left.
//
// Drawn at each size rather than scaled from one master, because the
// detail that reads at 512 turns to mush at 16: below 64 the centre dot
// merges with the ring, so the small sizes drop it and thicken what's
// left. Apple's grid expects this; one bitmap resized is what makes an
// icon look cheap in the menu bar.

let size = CGFloat(Int(CommandLine.arguments[1])!)
let path = CommandLine.arguments[2]
let simplified = size <= 64

guard let context = CGContext(
    data: nil,
    width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// macOS icons sit inside the canvas: the grid leaves a margin so icons of
// different shapes optically match each other in the Dock.
let inset = size * (simplified ? 0.07 : 0.098)
let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner = plate.width * 0.2237

let squircle = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)

context.saveGState()
context.addPath(squircle)
context.clip()

let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(red: 0.259, green: 0.514, blue: 0.965, alpha: 1),
        CGColor(red: 0.071, green: 0.267, blue: 0.659, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!

context.drawLinearGradient(
    gradient,
    start: CGPoint(x: plate.minX, y: plate.maxY),
    end: CGPoint(x: plate.maxX, y: plate.minY),
    options: []
)
context.restoreGState()

if !simplified {
    context.addPath(squircle)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.setLineWidth(size * 0.006)
    context.strokePath()
}

let centre = CGPoint(x: size / 2, y: size / 2)
let radius = size * (simplified ? 0.255 : 0.245)
let thickness = size * (simplified ? 0.135 : 0.105)

context.setLineWidth(thickness)
context.setLineCap(.round)

context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.24))
context.addArc(center: centre, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

// A wider gap when small, or the break in the ring disappears entirely.
let start = CGFloat.pi / 2
let sweep = CGFloat.pi * 2 * (simplified ? 0.66 : 0.72)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.addArc(center: centre, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
context.strokePath()

if !simplified {
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    context.fillEllipse(in: CGRect(
        x: centre.x - size * 0.052, y: centre.y - size * 0.052,
        width: size * 0.104, height: size * 0.104
    ))
}

guard let image = context.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: path))
