import UIKit

/// Procedurally bakes the portrait gold bar's PBR maps (no bundled assets):
/// - albedo: warm gold field, engraved emblem + stacked markings + serial, dark etched Kik code
/// - roughness: glossy polished field, rougher scratches, a slightly matte code patch for scan contrast
/// - normal: tangent-space relief from a height field (markings recessed, code low-relief, fine scratches)
nonisolated enum GoldBarMaterialBaker {

    // UIImage is immutable and documented thread-safe; the config crosses into the
    // detached bake task.
    struct Config: @unchecked Sendable {
        var pixelSize: CGSize
        /// Pre-rendered Kik code (dark on transparent), etched into the lower band.
        var code: UIImage
        var stampLines: [String]
        var serial: String = "No. CH 047219"
        var scratchCount: Int = 150

        /// Full-quality maps for the portrait bar face. Expensive — bake off the main thread.
        static func full(code: UIImage) -> Config {
            Config(
                pixelSize: CGSize(width: 640, height: 1110),
                code: code,
                stampLines: ["FINE GOLD", "999.9", "1 oz"]
            )
        }

        /// Tiny maps that bake in milliseconds — the low-res stand-in shown while the
        /// full set bakes in the background.
        static func preview(code: UIImage) -> Config {
            Config(
                pixelSize: CGSize(width: 96, height: 166),
                code: code,
                stampLines: ["FINE GOLD", "999.9", "1 oz"],
                scratchCount: 0
            )
        }
    }

    // UIImage is immutable and documented thread-safe; baked maps cross from the
    // background bake task back to the main actor.
    struct Textures: @unchecked Sendable {
        let albedo: UIImage
        let normal: UIImage
        let roughness: UIImage
    }

    private static let goldField = UIColor(red: 1.0, green: 0.76, blue: 0.33, alpha: 1)
    private static let goldEngraved = UIColor(red: 0.55, green: 0.40, blue: 0.15, alpha: 1)

    static func bake(_ config: Config) -> Textures {
        let height = renderHeightField(config)
        return Textures(
            albedo: renderAlbedo(config),
            normal: normalMap(from: height),
            roughness: renderRoughness(config)
        )
    }

    // MARK: - Portrait layout

    private static func emblemRect(_ size: CGSize) -> CGRect {
        let side = size.width * 0.22
        return CGRect(x: (size.width - side) / 2, y: size.height * 0.085 - side / 2, width: side, height: side)
    }

    private static func textColumn(_ size: CGSize) -> CGRect {
        CGRect(x: size.width * 0.06, y: size.height * 0.17, width: size.width * 0.88, height: size.height * 0.25)
    }

    private static func serialRect(_ size: CGSize) -> CGRect {
        CGRect(x: size.width * 0.1, y: size.height * 0.45, width: size.width * 0.8, height: size.height * 0.035)
    }

    private static func codeRect(_ size: CGSize) -> CGRect {
        let side = size.width * 0.62
        return CGRect(x: (size.width - side) / 2, y: size.height * 0.72 - side / 2, width: side, height: side)
    }

    // MARK: - Albedo

    private static func renderAlbedo(_ config: Config) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            goldField.setFill()
            ctx.fill(rect)

            drawEmblem(in: emblemRect(config.pixelSize), color: goldEngraved)
            drawCenteredLines(config.stampLines, in: textColumn(config.pixelSize), weight: .heavy, color: goldEngraved)
            drawCenteredLines([config.serial], in: serialRect(config.pixelSize), weight: .medium, color: goldEngraved)

            // Etched code: dark dots laser-etched into the gold (transparent pixels leave it untouched).
            config.code.draw(in: codeRect(config.pixelSize), blendMode: .multiply, alpha: 1)
        }
    }

    // MARK: - Roughness

    private static func renderRoughness(_ config: Config) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            UIColor(white: 0.15, alpha: 1).setFill()  // glossy polished base
            ctx.fill(rect)
            drawScratches(count: config.scratchCount, in: rect, color: UIColor(white: 0.5, alpha: 0.28), ctx: ctx)
            // Slightly matte code patch so the bright mirror doesn't wash out the dots.
            let patch = codeRect(config.pixelSize)
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: patch.insetBy(dx: -patch.width * 0.06, dy: -patch.width * 0.06))
        }
    }

    // MARK: - Height → Normal

    private static func renderHeightField(_ config: Config) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(rect)
            drawEmblem(in: emblemRect(config.pixelSize), color: UIColor(white: 0.34, alpha: 1))
            drawCenteredLines(config.stampLines, in: textColumn(config.pixelSize), weight: .heavy, color: UIColor(white: 0.32, alpha: 1))
            drawCenteredLines([config.serial], in: serialRect(config.pixelSize), weight: .medium, color: UIColor(white: 0.38, alpha: 1))
            drawScratches(count: config.scratchCount, in: rect, color: UIColor(white: 0.62, alpha: 0.12), ctx: ctx)
            // Code low-relief so the engraving doesn't shatter scan contrast under bright light.
            config.code.draw(in: codeRect(config.pixelSize), blendMode: .multiply, alpha: 0.3)
        }
    }

    private static func normalMap(from height: UIImage) -> UIImage {
        guard let cg = height.cgImage else { return height }
        let w = cg.width, h = cg.height
        var gray = [UInt8](repeating: 0, count: w * h)
        let grayCS = CGColorSpaceCreateDeviceGray()
        // The buffer pointer is only valid inside the closure, so the context must not outlive it.
        gray.withUnsafeMutableBufferPointer { buffer in
            let gctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                 bytesPerRow: w, space: grayCS, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            gctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let scale: Float = 2.0 / 255  // gradient strength, folded with the 0...255 → 0...1 conversion
        gray.withUnsafeBufferPointer { src in
            rgba.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let row = y * w
                    let rowAbove = max(y - 1, 0) * w
                    let rowBelow = min(y + 1, h - 1) * w
                    for x in 0..<w {
                        let left = src[row + max(x - 1, 0)]
                        let right = src[row + min(x + 1, w - 1)]
                        let up = src[rowAbove + x]
                        let down = src[rowBelow + x]
                        let dx = Float(Int(right) - Int(left)) * scale
                        let dy = Float(Int(down) - Int(up)) * scale
                        let invLen = 1 / (dx * dx + dy * dy + 1).squareRoot()
                        let i = (row + x) * 4
                        dst[i]     = UInt8(max(0, min(255, (-dx * invLen * 0.5 + 0.5) * 255)))
                        dst[i + 1] = UInt8(max(0, min(255, (-dy * invLen * 0.5 + 0.5) * 255)))
                        dst[i + 2] = UInt8(max(0, min(255, (invLen * 0.5 + 0.5) * 255)))
                        dst[i + 3] = 255
                    }
                }
            }
        }
        let rgbaCS = CGColorSpaceCreateDeviceRGB()
        let image = rgba.withUnsafeMutableBufferPointer { buffer -> CGImage in
            let rctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                 bytesPerRow: w * 4, space: rgbaCS,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return rctx.makeImage()!
        }
        return UIImage(cgImage: image)
    }

    // MARK: - Drawing helpers

    private static func drawCenteredLines(_ lines: [String], in rect: CGRect, weight: UIFont.Weight, color: UIColor) {
        guard !lines.isEmpty else { return }
        let lineHeight = rect.height / CGFloat(lines.count)
        for (index, line) in lines.enumerated() {
            let font = UIFont.systemFont(ofSize: lineHeight * 0.6, weight: weight)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let str = NSAttributedString(string: line, attributes: attrs)
            let textSize = str.size()
            let origin = CGPoint(x: rect.midX - textSize.width / 2,
                                 y: rect.minY + CGFloat(index) * lineHeight + (lineHeight - textSize.height) / 2)
            str.draw(at: origin)
        }
    }

    /// A simple engraved medallion (concentric rings + radial ticks) — generic, not a trademarked logo.
    private static func drawEmblem(in rect: CGRect, color: UIColor) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        color.setStroke()
        cg.setLineWidth(rect.width * 0.025)
        cg.strokeEllipse(in: rect)
        cg.strokeEllipse(in: rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.24))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rOuter = rect.width / 2
        let rInner = rOuter * 0.78
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * .pi * 2
            cg.move(to: CGPoint(x: center.x + cos(a) * rInner, y: center.y + sin(a) * rInner))
            cg.addLine(to: CGPoint(x: center.x + cos(a) * rOuter, y: center.y + sin(a) * rOuter))
        }
        cg.strokePath()
    }

    /// Fine, multi-directional hairline micro-scratches (faint — real bullion, not speed lines).
    private static func drawScratches(count: Int, in rect: CGRect, color: UIColor, ctx: UIGraphicsImageRendererContext) {
        let cg = ctx.cgContext
        color.setStroke()
        cg.setLineCap(.round)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)  // top 31 bits → [0, 1)
        }
        for _ in 0..<count {
            cg.setLineWidth(0.4 + rnd() * (rect.height / 1600))
            let start = CGPoint(x: rnd() * rect.width, y: rnd() * rect.height)
            let length = rect.width * (0.004 + rnd() * 0.028)
            let angle = rnd() * .pi * 2
            cg.move(to: start)
            cg.addLine(to: CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
            cg.strokePath()
        }
    }

    private static func renderImage(size: CGSize, _ draw: (UIGraphicsImageRendererContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in draw(ctx, CGRect(origin: .zero, size: size)) }
    }
}
