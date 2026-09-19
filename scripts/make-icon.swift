// Renders Pulse's app icon: the island, a soft black notch growing down from the top edge of a
// soft white tile. Deliberately simple: two shapes, gentle gradients, one soft shadow.
// Usage: swift scripts/make-icon.swift <output.png>   (1024×1024; scripts/make-icon.sh builds the .icns)
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: white, green: white, blue: white, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
// Work top-down like a design tool.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

/// Apple-style continuous-corner tile: a superellipse, so corners flow into the edges with no
/// visible "join" the way a plain rounded rectangle has.
func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// The island silhouette: flush with the top, concave "ears" flaring into the edge (like the
/// MacBook notch), and a deep, soft rounded bottom. Same construction as NotchShape in the app.
func islandPath(_ rect: CGRect, ear: CGFloat, bottom: CGFloat) -> CGPath {
    let left = rect.minX + ear, right = rect.maxX - ear
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY))
    p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
    p.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
    p.addCurve(to: CGPoint(x: left + bottom, y: rect.maxY),
               control1: CGPoint(x: left, y: rect.maxY - bottom * 0.45),
               control2: CGPoint(x: left + bottom * 0.45, y: rect.maxY))
    p.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
    p.addCurve(to: CGPoint(x: right, y: rect.maxY - bottom),
               control1: CGPoint(x: right - bottom * 0.45, y: rect.maxY),
               control2: CGPoint(x: right, y: rect.maxY - bottom * 0.45))
    p.addLine(to: CGPoint(x: right, y: rect.minY + ear))
    p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
    p.closeSubpath()
    return p
}

// macOS icon grid: 824pt tile centered on the 1024 canvas.
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = squircle(tileRect)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 30, color: gray(0, 0.22))
ctx.addPath(tile)
ctx.setFillColor(gray(1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()

// Tile: white, easing into a faint cool gray toward the bottom.
let tileGradient = CGGradient(
    colorsSpace: space,
    colors: [gray(1), CGColor(srgbRed: 0.925, green: 0.93, blue: 0.945, alpha: 1)] as CFArray,
    locations: [0.2, 1]
)!
ctx.drawLinearGradient(tileGradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// The island hangs from the top edge of the tile, like the notch it grows out of. Its top runs
// past the tile edge and is clipped by it, so the island meets the edge seamlessly, and its sides
// curve all the way up for a soft bowl rather than a boxy tab.
let islandRect = CGRect(x: 172, y: 40, width: 680, height: 400)
let island = islandPath(islandRect, ear: 0, bottom: 340)

// One soft shadow, cast down onto the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 26), blur: 54, color: gray(0, 0.3))
ctx.addPath(island)
ctx.setFillColor(gray(0))
ctx.fillPath()
ctx.restoreGState()

// Body: a gentle diagonal gloss, graphite at the top-left settling into black.
ctx.saveGState()
ctx.addPath(island)
ctx.clip()
let body = CGGradient(
    colorsSpace: space,
    colors: [gray(0.30), gray(0.10), gray(0.02)] as CFArray,
    locations: [0, 0.45, 1]
)!
ctx.drawLinearGradient(body, start: CGPoint(x: 220, y: 100), end: CGPoint(x: 800, y: 440),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]) // cover the whole shape, no raw-black slivers
// A faint highlight on the lower curve reads as a soft, rounded surface rather than a flat cutout.
let rim = CGGradient(colorsSpace: space, colors: [gray(1, 0), gray(1, 0.07)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(rim, start: CGPoint(x: 512, y: 330), end: CGPoint(x: 512, y: 440), options: [])
ctx.restoreGState()

ctx.restoreGState() // tile clip

let image = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
