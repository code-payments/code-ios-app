import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Procedurally bakes the gold bar's PBR maps (no bundled assets):
/// - albedo: warm gold field, engraved (darker) stamp text, dark etched QR modules
/// - roughness: smooth polished field, rougher scratches + etched regions
/// - normal: tangent-space relief derived from a height field (stamp/QR recessed, scratches grooved)
nonisolated enum GoldBarMaterialBaker {

    struct Config {
        var pixelSize: CGSize
        var qrPayload: String
        var stampLines: [String]
        var scratchCount: Int = 90
    }

    struct Textures {
        let albedo: UIImage
        let normal: UIImage
        let roughness: UIImage
    }

    // Warm 24k-ish gold field reflectance (sRGB).
    private static let goldField = UIColor(red: 0.95, green: 0.74, blue: 0.36, alpha: 1)
    private static let goldEngraved = UIColor(red: 0.66, green: 0.49, blue: 0.20, alpha: 1)

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

    /// High error-correction QR as a crisp black-on-white mask, nearest-neighbour upscaled.
    private static func makeQRImage(payload: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "H"
        let output = filter.outputImage!
        let scale = 12.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        let cg = context.createCGImage(scaled, from: scaled.extent)!
        return UIImage(cgImage: cg)
    }

    /// Rect for the QR on the bar face (right third, square, with quiet-zone padding).
    private static func qrRect(in size: CGSize) -> CGRect {
        let side = size.height * 0.62
        let margin = size.height * 0.19
        return CGRect(x: size.width - side - margin, y: (size.height - side) / 2, width: side, height: side)
    }

    // MARK: - Albedo

    private static func renderAlbedo(_ config: Config, qr: UIImage) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            goldField.setFill()
            ctx.fill(rect)

            // Engraved stamp text on the left, slightly darker than the field.
            drawStampText(config.stampLines, in: leftPanel(rect), color: goldEngraved)

            // Etched QR: dark modules over a bright gold quiet zone for contrast.
            // Multiply blends the black-on-white QR onto gold → black modules, gold quiet zone.
            let qframe = qrRect(in: config.pixelSize)
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
            UIColor(white: 0.22, alpha: 1).setFill()  // polished base
            ctx.fill(rect)
            drawScratches(count: config.scratchCount, in: rect, color: UIColor(white: 0.55, alpha: 0.5), ctx: ctx)
            // Etched QR + stamp read rougher.
            ctx.cgContext.saveGState()
            ctx.cgContext.clip(to: qrRect(in: config.pixelSize))
            qr.draw(in: qrRect(in: config.pixelSize), blendMode: .multiply, alpha: 1)
            ctx.cgContext.restoreGState()
        }
    }

    // MARK: - Height → Normal

    /// Grayscale height: mid field, recessed (darker) stamp/QR, grooved scratches.
    private static func renderHeightField(_ config: Config, qr: UIImage) -> UIImage {
        renderImage(size: config.pixelSize) { ctx, rect in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(rect)
            drawStampText(config.stampLines, in: leftPanel(rect), color: UIColor(white: 0.32, alpha: 1))
            drawScratches(count: config.scratchCount, in: rect, color: UIColor(white: 0.42, alpha: 0.5), ctx: ctx)
            ctx.cgContext.saveGState()
            ctx.cgContext.clip(to: qrRect(in: config.pixelSize))
            qr.draw(in: qrRect(in: config.pixelSize), blendMode: .multiply, alpha: 1)
            ctx.cgContext.restoreGState()
        }
    }

    /// Tangent-space normal map from a height image via a 3x3 gradient.
    private static func normalMap(from height: UIImage) -> UIImage {
        guard let cg = height.cgImage else { return height }
        let w = cg.width, h = cg.height
        var gray = [UInt8](repeating: 0, count: w * h)
        let grayCS = CGColorSpaceCreateDeviceGray()
        let gctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w, space: grayCS, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        gctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let strength: Float = 2.2
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

    private static func leftPanel(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.width * 0.06, y: rect.height * 0.18,
               width: rect.width * 0.5, height: rect.height * 0.64)
    }

    private static func drawStampText(_ lines: [String], in rect: CGRect, color: UIColor) {
        guard !lines.isEmpty else { return }
        let lineHeight = rect.height / CGFloat(lines.count)
        for (index, line) in lines.enumerated() {
            let font = UIFont.systemFont(ofSize: lineHeight * 0.55, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let str = NSAttributedString(string: line, attributes: attrs)
            let origin = CGPoint(x: rect.minX, y: rect.minY + CGFloat(index) * lineHeight + lineHeight * 0.2)
            str.draw(at: origin)
        }
    }

    private static func drawScratches(count: Int, in rect: CGRect, color: UIColor, ctx: UIGraphicsImageRendererContext) {
        color.setStroke()
        let cg = ctx.cgContext
        cg.setLineWidth(max(0.5, rect.height / 900))
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max)
        }
        for _ in 0..<count {
            let start = CGPoint(x: rnd() * rect.width, y: rnd() * rect.height)
            let length = rect.width * (0.02 + rnd() * 0.12)
            let angle = (rnd() - 0.5) * 0.5
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
