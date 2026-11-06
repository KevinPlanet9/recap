// Draws Resources/AppIcon.png (1024 x 1024) offscreen: no window.
//   swift scripts/make-icon.swift Resources/AppIcon.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
let charcoal = color(0.078, 0.086, 0.098)
let ground = color(0.043, 0.047, 0.055)
let sand = color(0.863, 0.761, 0.698)
let mauve = color(0.690, 0.553, 0.533)
let paper = color(0.949, 0.933, 0.914)

// Rounded square on the macOS icon grid (824 of 1024, centered).
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0, 0, 0, 0.45))
ctx.addPath(shape)
ctx.setFillColor(charcoal)
ctx.fillPath()
ctx.restoreGState()

// Soft vertical shade and a fine sand rim.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0.13, 0.14, 0.16), ground] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
ctx.restoreGState()
ctx.addPath(shape)
ctx.setStrokeColor(color(0.863, 0.761, 0.698, 0.28))
ctx.setLineWidth(4)
ctx.strokePath()

// A waveform in sand on the left, flowing into transcript lines on the right.
let mid = body.midY
let bars: [CGFloat] = [0.22, 0.48, 0.80, 0.56, 1.0, 0.66, 0.36]
let barW: CGFloat = 30, gap: CGFloat = 20, maxH: CGFloat = 330
var x = body.minX + 105
for (i, h) in bars.enumerated() {
    let height = maxH * h
    let r = CGRect(x: x, y: mid - height / 2, width: barW, height: height)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    ctx.setFillColor(i == 4 ? sand : color(0.863, 0.761, 0.698, 0.55 + 0.06 * Double(i)))
    ctx.fillPath()
    x += barW + gap
}

// Transcript lines: a time mark in mauve, then text in paper.
let lineX = x + 40
let widths: [CGFloat] = [250, 200, 235]
for (i, w) in widths.enumerated() {
    let y = mid + 95 - CGFloat(i) * 95
    ctx.setFillColor(mauve)
    ctx.addPath(CGPath(roundedRect: CGRect(x: lineX, y: y - 14, width: 46, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(i == 1 ? paper : color(0.949, 0.933, 0.914, 0.6))
    ctx.addPath(CGPath(roundedRect: CGRect(x: lineX + 64, y: y - 14, width: w - 64, height: 28), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.fillPath()
}

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
