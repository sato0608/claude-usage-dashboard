import Cocoa

// アイコン画像を描いて AppIcon.iconset 用の PNG を書き出す。
//   使い方: swiftc native/make_icon.swift -o /tmp/make_icon && /tmp/make_icon <出力 iconset フォルダ>
// 出力後に `iconutil -c icns <iconset> -o native/AppIcon.icns` で .icns にする。

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024
    func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }
    // macOS 標準の角丸スクエア（周囲に余白）
    let inset = 100 * u
    let box = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let body = NSBezierPath(roundedRect: box, xRadius: 185 * u, yRadius: 185 * u)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * u
    shadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    shadow.set()
    rgb(0x0c0f14).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [rgb(0x1f2840), rgb(0x0c0f14)])!.draw(in: body, angle: -90)
    rgb(0xffffff, 0.08).setStroke()
    body.lineWidth = 3 * u
    body.stroke()

    // 棒グラフ（右肩上がり。最後の 1 本だけアクセント色）
    body.addClip()
    let heights: [CGFloat] = [0.30, 0.44, 0.36, 0.58, 0.50, 0.76]
    let baseY = box.minY + 150 * u
    let areaW = box.width - 2 * 120 * u
    let gap = 26 * u
    let bw = (areaW - gap * CGFloat(heights.count - 1)) / CGFloat(heights.count)
    let maxH = box.height - 150 * u - 170 * u
    for (i, h) in heights.enumerated() {
        let x = box.minX + 120 * u + CGFloat(i) * (bw + gap)
        let r = NSRect(x: x, y: baseY, width: bw, height: maxH * h)
        let path = NSBezierPath(roundedRect: r, xRadius: 26 * u, yRadius: 26 * u)
        (i == heights.count - 1 ? rgb(0x6ea8ff) : rgb(0x6ea8ff, 0.32)).setFill()
        path.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let rep = draw(size: px)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/" + name))
    }
}
