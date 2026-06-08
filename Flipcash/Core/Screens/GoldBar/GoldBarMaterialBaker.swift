import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Procedurally bakes the portrait gold bar's PBR maps (no bundled assets):
/// - albedo: warm gold field, engraved emblem + stacked markings + serial, dark etched QR
/// - roughness: glossy polished field, rougher scratches, a slightly matte QR patch for scan contrast
/// - normal: tangent-space relief from a height field (markings recessed, QR low-relief, fine scratches)
nonisolated enum GoldBarMaterialBaker {

    struct Config {
        var pixelSize: CGSize
        var qrPayload: String
        var stampLines: [String]
        var serial: String = "No. CH 047219"
        var scratchCount: Int = 150
    }

    struct Textures {
        let albedo: UIImage
        let normal: UIImage
        let roughness: UIImage
    }

    private static let goldField = UIColor(red: 1.0, green: 0.76, blue: 0.33, alpha: 1)
    private static let goldEngraved = UIColor(red: 0.55, green: 0.40, blue: 0.15, alpha: 1)

    static func bake(_ config: Config) -> Textures {
        let qr = makeQRImage(payload: config.qrPayload)
        let height = renderHeightField(config, qr: qr)
        return Textures(
            albedo: renderAlbedo(config, qr: qr),
            normal: normalMap(from: height),
            roughness: renderRoughness(config, qr: qr)
        )
    }

    // MARK: - QR

    private static func makeQRImage(payload: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "H"
        let output = filter.outputImage!
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        let cg = context.createCGImage(scaled, from: scaled.extent)!
        return UIImage(cgImage: cg)
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

    private static func qrRect(_ size: CGSize) -> CGRect {
        let side = size.width * 0.62
        return CGRect(x: (size.width - side) / 2, y: size.height * 0.72 - side / 2, width: side, height: side)
    }

    // MARK: - Albedo

    private static func renderAlbedo(_ config: Config, qr: UIImage) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            goldField.setFill()
            ctx.fill(rect)

            drawEmblem(in: emblemRect(config.pixelSize), color: goldEngraved)
            drawCenteredLines(config.stampLines, in: textColumn(config.pixelSize), weight: .heavy, color: goldEngraved)
            drawCenteredLines([config.serial], in: serialRect(config.pixelSize), weight: .medium, color: goldEngraved)

            // Etched QR: dark modules over a bright gold quiet zone for contrast.
            let qframe = qrRect(config.pixelSize)
            goldField.setFill()
            ctx.fill(qframe.insetBy(dx: -qframe.width * 0.06, dy: -qframe.width * 0.06))
            ctx.cgContext.saveGState()
            ctx.cgContext.clip(to: qframe)
            qr.draw(in: qframe, blendMode: .multiply, alpha: 1)
            ctx.cgContext.restoreGState()
        }
    }

    // MARK: - Roughness

    private static func renderRoughness(_ config: Config, qr: UIImage) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            UIColor(white: 0.15, alpha: 1).setFill()  // glossy polished base
            ctx.fill(rect)
            drawScratches(count: config.scratchCount, in: rect, color: UIColor(white: 0.5, alpha: 0.28), ctx: ctx)
            // Slightly matte QR patch so the bright mirror doesn't wash out the modules.
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.fill(qrRect(config.pixelSize).insetBy(dx: -qrRect(config.pixelSize).width * 0.06, dy: -qrRect(config.pixelSize).width * 0.06))
        }
    }

    // MARK: - Height → Normal

    private static func renderHeightField(_ config: Config, qr: UIImage) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(rect)
            drawEmblem(in: emblemRect(config.pixelSize), color: UIColor(white: 0.34, alpha: 1))
            drawCenteredLines(config.stampLines, in: textColumn(config.pixelSize), weight: .heavy, color: UIColor(white: 0.32, alpha: 1))
            drawCenteredLines([config.serial], in: serialRect(config.pixelSize), weight: .medium, color: UIColor(white: 0.38, alpha: 1))
            drawScratches(count: config.scratchCount, in: rect, color: UIColor(white: 0.62, alpha: 0.12), ctx: ctx)
            // QR low-relief so the engraving doesn't shatter scan contrast under bright light.
            ctx.cgContext.saveGState()
            ctx.cgContext.clip(to: qrRect(config.pixelSize))
            qr.draw(in: qrRect(config.pixelSize), blendMode: .multiply, alpha: 0.3)
            ctx.cgContext.restoreGState()
        }
    }

    private static func normalMap(from height: UIImage) -> UIImage {
        guard let cg = height.cgImage else { return height }
        let w = cg.width, h = cg.height
        var gray = [UInt8](repeating: 0, count: w * h)
        let grayCS = CGColorSpaceCreateDeviceGray()
        let gctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w, space: grayCS, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        gctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let strength: Float = 2.0
        func at(_ x: Int, _ y: Int) -> Float {
            Float(gray[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)]) / 255
        }
        for y in 0..<h {
            for x in 0..<w {
                let dx = (at(x + 1, y) - at(x - 1, y)) * strength
                let dy = (at(x, y + 1) - at(x, y - 1)) * strength
                var n = SIMD3<Float>(-dx, -dy, 1)
                n /= max(0.0001, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
                let i = (y * w + x) * 4
                rgba[i]     = UInt8(max(0, min(255, (n.x * 0.5 + 0.5) * 255)))
                rgba[i + 1] = UInt8(max(0, min(255, (n.y * 0.5 + 0.5) * 255)))
                rgba[i + 2] = UInt8(max(0, min(255, (n.z * 0.5 + 0.5) * 255)))
                rgba[i + 3] = 255
            }
        }
        let rgbaCS = CGColorSpaceCreateDeviceRGB()
        let rctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w * 4, space: rgbaCS,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return UIImage(cgImage: rctx.makeImage()!)
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
            return CGFloat(seed >> 33) / CGFloat(UInt32.max)
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
