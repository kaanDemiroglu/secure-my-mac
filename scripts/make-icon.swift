#!/usr/bin/env swift
// Secure My Mac uygulama simgesini (1024x1024 PNG) çizer.
// Kullanım: swift scripts/make-icon.swift <cikti.png>
import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("context") }

// Üstten aşağı koordinat sistemi.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: stops.map { color($0.0) } as CFArray, locations: stops.map { $0.1 })!
}
func rrect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    ctx.restoreGState()
}
func shadowed(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dy), blur: blur, color: color(0x000000, alpha))
    draw()
    ctx.restoreGState()
}

// 1) Beyaz yuvarlatılmış kare zemin (macOS simge ızgarası: 824 px, kenarda 100 px boşluk).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = rrect(tile, 186)
shadowed(blur: 28, dy: 12, alpha: 0.28) {
    ctx.addPath(tilePath); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
}
fill(tilePath, gradient([(0xFFFFFF, 0), (0xEEF0F4, 1)]), from: CGPoint(x: 0, y: 100), to: CGPoint(x: 0, y: 924))

// 2) Ayak ve boyun (gri-mor, referanstaki gibi).
let neck = rrect(CGRect(x: 462, y: 668, width: 100, height: 96), 14)
fill(neck, gradient([(0xB7BCD8, 0), (0x8D93B8, 1)]), from: CGPoint(x: 462, y: 0), to: CGPoint(x: 562, y: 0))
let base = rrect(CGRect(x: 356, y: 742, width: 312, height: 44), 22)
shadowed(blur: 10, dy: 4, alpha: 0.25) {
    ctx.addPath(base); ctx.setFillColor(color(0x9BA1C4)); ctx.fillPath()
}
fill(base, gradient([(0xC3C8E2, 0), (0x8A90B6, 1)]), from: CGPoint(x: 0, y: 742), to: CGPoint(x: 0, y: 786))

// 3) Kırmızı monitör gövdesi.
let body = CGRect(x: 192, y: 236, width: 640, height: 450)
let bodyPath = rrect(body, 56)
shadowed(blur: 30, dy: 16, alpha: 0.35) {
    ctx.addPath(bodyPath); ctx.setFillColor(color(0xC8141F)); ctx.fillPath()
}
fill(bodyPath, gradient([(0xFF6B6B, 0), (0xF0262E, 0.45), (0xB30F1B, 1)]),
     from: CGPoint(x: 0, y: body.minY), to: CGPoint(x: 0, y: body.maxY))

// 4) Ekran (koyu kırmızı cam).
let screen = CGRect(x: 224, y: 266, width: 576, height: 340)
let screenPath = rrect(screen, 34)
fill(screenPath, gradient([(0xFF5A5F, 0), (0xD81B26, 0.55), (0x9E0C18, 1)]),
     from: CGPoint(x: 0, y: screen.minY), to: CGPoint(x: 0, y: screen.maxY))
ctx.saveGState(); ctx.addPath(screenPath); ctx.clip()
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [color(0xFFFFFF, 0.38), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 300), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 300), endRadius: 330, options: [])
ctx.restoreGState()

// 5) Çene (ekranın altındaki şerit) ve küçük nokta.
ctx.setFillColor(color(0xFFFFFF, 0.55))
ctx.fillEllipse(in: CGRect(x: 512 - 11, y: 636 - 11, width: 22, height: 22))

// 6) Kalkan.
func shield(scale: CGFloat, at c: CGPoint) -> CGPath {
    let p = CGMutablePath()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * scale, y: c.y + y * scale) }
    p.move(to: pt(0, -135))
    p.addCurve(to: pt(118, -92), control1: pt(38, -100), control2: pt(82, -96))
    p.addCurve(to: pt(0, 142), control1: pt(122, 44), control2: pt(62, 108))
    p.addCurve(to: pt(-118, -92), control1: pt(-62, 108), control2: pt(-122, 44))
    p.addCurve(to: pt(0, -135), control1: pt(-82, -96), control2: pt(-38, -100))
    p.closeSubpath()
    return p
}
let center = CGPoint(x: 512, y: 436)
let shieldPath = shield(scale: 1.0, at: center)
shadowed(blur: 22, dy: 12, alpha: 0.4) {
    ctx.addPath(shieldPath); ctx.setFillColor(color(0x7A0710)); ctx.fillPath()
}
fill(shieldPath, gradient([(0xFFFFFF, 0), (0xFFE3E3, 1)]), from: CGPoint(x: 0, y: 300), to: CGPoint(x: 0, y: 580))

// Kalkan içi: ince kırmızı çerçeve + onay işareti.
ctx.saveGState()
ctx.addPath(shield(scale: 0.86, at: center))
ctx.setStrokeColor(color(0xE0262F, 0.35)); ctx.setLineWidth(6); ctx.strokePath()
ctx.restoreGState()

let check = CGMutablePath()
check.move(to: CGPoint(x: 512 - 52, y: 436 + 6))
check.addLine(to: CGPoint(x: 512 - 12, y: 436 + 48))
check.addLine(to: CGPoint(x: 512 + 56, y: 436 - 34))
ctx.saveGState()
ctx.addPath(check)
ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(34)
ctx.setStrokeColor(color(0xD81B26))
ctx.strokePath()
ctx.restoreGState()

// PNG olarak yaz.
guard let image = ctx.makeImage() else { fatalError("image") }
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("Yazıldı: \(outPath)")
