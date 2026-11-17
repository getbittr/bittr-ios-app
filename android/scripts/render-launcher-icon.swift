// Renders the Android launcher icon from the iOS app icon, so both platforms ship the same pixels.
//
//   swift android/scripts/render-launcher-icon.swift      (from the repo root)
//
// iOS ships one 1024 px PNG: the mark on a flat yellow. Android wants that split in two for the
// adaptive icon, so the mark is unmixed from the yellow here. Every pixel of the source is the
// yellow, the white arc, the near-black wedge, or an antialiased blend of the yellow with ONE of
// them (the two shapes never touch), so each pixel's coverage can be solved for exactly. Composited
// back over the yellow, the foreground reproduces the source; the script checks that it does.
//
// The adaptive icon is 108 dp with only the central 72 dp visible, so the 1024 px iOS square maps
// onto that 72 dp and the mark keeps the size and position it has on iOS.
//
// Writes, under android/app/src/main/res/:
//   mipmap-*dpi/ic_launcher_foreground.png    the mark, transparent around it (108 dp)
//   mipmap-*dpi/ic_launcher_monochrome.png    the mark as one white silhouette, for themed icons
//   mipmap-*dpi/ic_launcher.png               the iOS icon as is, square (48 dp)
//   mipmap-*dpi/ic_launcher_round.png         the iOS icon cropped to a circle (48 dp)
// The background layer is drawable/ic_launcher_background.xml, filled with `yellow` below.

import AppKit

let source = "ios/bittr/Assets.xcassets/AppIcon.appiconset/appicon20241206.png"
let res = "android/app/src/main/res"
let densities: [(String, CGFloat)] = [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]

let yellow = (r: 255.0, g: 196.0, b: 0.0)   // #FFC400, the source's background
let white = (r: 255.0, g: 255.0, b: 255.0)
let ink = (r: 21.0, g: 21.0, b: 20.0)       // #151514, the source's wedge

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func write(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// The source, redrawn into sRGB RGBA so its bytes can be read directly.
guard let data = NSData(contentsOfFile: source),
      let provider = CGDataProvider(data: data),
      let decoded = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent) else { fatalError("cannot read \(source)") }
let n = decoded.width
precondition(n == decoded.height, "the iOS icon is expected to be square")
let src = context(n)
src.draw(decoded, in: CGRect(x: 0, y: 0, width: n, height: n))
let srcImage = src.makeImage()!
let px = src.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
let bpr = src.bytesPerRow

// Unmix: red separates the two. Yellow and white both have red 255, so an arc blend never moves it,
// while any blend with the wedge pulls it below 255.
let fg = context(n), mono = context(n)
let fgPx = fg.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
let monoPx = mono.data!.bindMemory(to: UInt8.self, capacity: n * n * 4)
var worst = 0.0
for y in 0..<n {
    for x in 0..<n {
        let i = y * bpr + x * 4
        let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
        let isInk = r < 255
        let c = isInk ? ink : white
        let a = min(1, max(0, isInk ? (yellow.r - r) / (yellow.r - ink.r) : (b - yellow.b) / (white.b - yellow.b)))
        // How far the solved pixel lands from the source, recomposited over the yellow.
        worst = max(worst, abs(a * c.g + (1 - a) * yellow.g - g), abs(a * c.b + (1 - a) * yellow.b - b))
        let o = y * fg.bytesPerRow + x * 4
        fgPx[o] = UInt8((c.r * a).rounded()); fgPx[o + 1] = UInt8((c.g * a).rounded())
        fgPx[o + 2] = UInt8((c.b * a).rounded()); fgPx[o + 3] = UInt8((255 * a).rounded())
        let m = UInt8((255 * a).rounded())
        monoPx[o] = m; monoPx[o + 1] = m; monoPx[o + 2] = m; monoPx[o + 3] = m
    }
}
precondition(worst <= 2, "the source is not the yellow/white/ink icon this script expects (off by \(worst))")
let fgImage = fg.makeImage()!, monoImage = mono.makeImage()!

for (name, d) in densities {
    let dir = "\(res)/mipmap-\(name)"
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    // Adaptive layers: 108 dp canvas, the iOS square on the central 72 dp.
    let canvas = Int((108 * d).rounded()), inset = 18 * d, visible = 72 * d
    for (image, file) in [(fgImage, "ic_launcher_foreground"), (monoImage, "ic_launcher_monochrome")] {
        let ctx = context(canvas)
        ctx.draw(image, in: CGRect(x: inset, y: inset, width: visible, height: visible))
        write(ctx.makeImage()!, "\(dir)/\(file).png")
    }

    // Legacy rasters: the whole iOS icon at 48 dp.
    let legacy = Int((48 * d).rounded())
    let square = context(legacy)
    square.draw(srcImage, in: CGRect(x: 0, y: 0, width: legacy, height: legacy))
    write(square.makeImage()!, "\(dir)/ic_launcher.png")
    let round = context(legacy)
    round.addEllipse(in: CGRect(x: 0, y: 0, width: legacy, height: legacy))
    round.clip()
    round.draw(srcImage, in: CGRect(x: 0, y: 0, width: legacy, height: legacy))
    write(round.makeImage()!, "\(dir)/ic_launcher_round.png")
}
print("Rendered from \(source); unmixing reproduces it to within \(Int(worst)) of 255 per channel.")
