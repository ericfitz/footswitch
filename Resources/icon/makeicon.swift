import AppKit
import Foundation

let a = CommandLine.arguments
guard a.count == 4, let canvas = Int(a[3]) else { exit(1) }
let S = CGFloat(canvas)
let cs = CGColorSpaceCreateDeviceRGB()

let img = NSImage(contentsOfFile: a[1])!
let src = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let sw = src.width, sh = src.height
let sctx = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw*4,
                     space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sctx.draw(src, in: CGRect(x: 0, y: 0, width: sw, height: sh))
let buf = sctx.data!.bindMemory(to: UInt8.self, capacity: sw*sh*4)

// Brightness-keyed knockout. Background is overwhelmingly minC>=250 (a hard
// cliff in the histogram); pedal is far darker. Key on minC alone — no
// saturation gate (the photo's white carries faint tints that a sat gate
// wrongly preserved, leaving a visible box).
let solidWhite = 245   // >= this -> fully transparent
let keepBelow  = 225   // <= this -> fully opaque; between = feather
for i in stride(from: 0, to: sw*sh*4, by: 4) {
    let m = min(Int(buf[i]), min(Int(buf[i+1]), Int(buf[i+2])))
    if m >= solidWhite {
        buf[i]=0; buf[i+1]=0; buf[i+2]=0; buf[i+3]=0
    } else if m > keepBelow {
        let t = Double(m - keepBelow) / Double(solidWhite - keepBelow) // 0..1 toward white
        let alpha = Int((1.0 - t) * 255.0)
        let af = Double(alpha)/255.0
        buf[i]   = UInt8(Double(buf[i])   * af)
        buf[i+1] = UInt8(Double(buf[i+1]) * af)
        buf[i+2] = UInt8(Double(buf[i+2]) * af)
        buf[i+3] = UInt8(alpha)
    }
}
let cutout = sctx.makeImage()!

let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let margin = S * (100.0/1024.0)
let tile = CGRect(x: margin, y: margin, width: S-2*margin, height: S-2*margin)
let radius = tile.width * 0.2237
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
              CGColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0,1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

let inset = tile.width * 0.12
let content = tile.insetBy(dx: inset, dy: inset)
let cw = CGFloat(cutout.width), ch = CGFloat(cutout.height)
let scale = min(content.width/cw, content.height/ch)
let dw = cw*scale, dh = ch*scale
ctx.draw(cutout, in: CGRect(x: content.midX-dw/2, y: content.midY-dh/2, width: dw, height: dh))

let out = ctx.makeImage()!
let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: a[2]))
