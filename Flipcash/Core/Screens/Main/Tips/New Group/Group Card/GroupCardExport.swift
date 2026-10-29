//
//  GroupCardExport.swift
//  Flipcash
//

import CoreGraphics
import Foundation
import UIKit

/// Writes a group card's QR tile out as a file for the "Download As" sheet.
///
/// Both formats draw the tile from the same ``GroupQRGeometry``, so a PNG and an SVG of one group
/// are the same figure. Only the tile is exported, not the card around it.
enum GroupCardExport {

    /// The PNG's side in pixels.
    nonisolated static let pngSide = 1024

    /// Renders the QR for `url` as `format` into a file named for `title`, or returns `nil` if
    /// rendering or writing it failed.
    ///
    /// The file lands in a directory of its own under the temporary directory, so ``discard(_:)``
    /// can take the whole thing away afterwards.
    @MainActor
    static func file(for format: TipCardDownloadFormat, url: URL, title: String?) -> URL? {
        do {
            guard let modules = QRModules.encode(url.absoluteString) else { throw Error.encodeFailed }
            let geometry = GroupQRGeometry(modules: modules)

            let contents: Data
            switch format {
            case .png:
                guard let png = png(geometry) else { throw Error.renderFailed }
                contents = png
            case .svg:
                contents = Data(svg(geometry).utf8)
            }

            let directory = FileManager.default.temporaryDirectory
                .appending(path: "GroupCardExport-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let file = directory.appending(path: filename(for: format, title: title))
            try contents.write(to: file, options: .atomic)
            return file
        } catch {
            ErrorReporting.captureError(
                error,
                reason: "Failed to export group card",
                metadata: ["format": format.rawValue]
            )
            return nil
        }
    }

    /// Removes a file handed out by ``file(for:url:title:)``, along with the directory it was written into.
    static func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    // MARK: - Naming -

    /// `Join Night Owls.png`, or `Group Card.png` when the title is empty. `/` and `:` are
    /// removed because neither is valid in a file name on iOS or Android.
    nonisolated static func filename(for format: TipCardDownloadFormat, title: String?) -> String {
        let cleaned = (title ?? "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = cleaned.isEmpty ? "Group Card" : "Join \(cleaned)"
        return "\(stem).\(format.rawValue)"
    }

    // MARK: - Rendering -

    /// The tile at 1024 x 1024 with a transparent ground outside its rounded corners, the symbol
    /// scaled to the largest whole number of pixels per module that fits and centred.
    nonisolated static func png(_ geometry: GroupQRGeometry) -> Data? {
        let side = CGFloat(pngSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let context = renderer.cgContext

            context.setFillColor(UIColor(red: 0x2E / 255, green: 0x2E / 255, blue: 0x30 / 255, alpha: 1).cgColor)
            let radius = side * GroupQRGeometry.tileCornerFraction
            context.addPath(CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                cornerWidth: radius, cornerHeight: radius, transform: nil
            ))
            context.fillPath()

            let pixelsPerModule = CGFloat(pngSide / geometry.tileSide)
            let inset = (side - pixelsPerModule * CGFloat(geometry.tileSide)) / 2
            context.translateBy(x: inset, y: inset)
            context.scaleBy(x: pixelsPerModule, y: pixelsPerModule)

            context.setFillColor(UIColor.white.cgColor)
            context.addPath(geometry.modulesPath)
            context.fillPath()
            context.addPath(geometry.findersPath)
            context.fillPath(using: .evenOdd)
            context.addPath(geometry.logoPath)
            context.fillPath(using: .evenOdd)
        }
        return image.pngData()
    }

    /// The tile as a standalone SVG: a rounded background rect, then the modules, the finder shapes
    /// and the mark as white vector paths. Nothing is rasterised.
    nonisolated static func svg(_ geometry: GroupQRGeometry) -> String {
        let side = geometry.tileSide
        let radius = number(CGFloat(side) * GroupQRGeometry.tileCornerFraction)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(side) \(side)">
        <rect width="\(side)" height="\(side)" rx="\(radius)" ry="\(radius)" fill="\(GroupQRGeometry.tileHex)"/>
        <path fill="\(GroupQRGeometry.moduleHex)" d="\(pathData(geometry.modulesPath))"/>
        <path fill="\(GroupQRGeometry.moduleHex)" fill-rule="evenodd" d="\(pathData(geometry.findersPath))"/>
        <path fill="\(GroupQRGeometry.moduleHex)" fill-rule="evenodd" d="\(pathData(geometry.logoPath))"/>
        </svg>
        """
    }

    /// An SVG `d` attribute for `path`, with coordinates to three decimals.
    nonisolated static func pathData(_ path: CGPath) -> String {
        var commands: [String] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                commands.append("M\(number(points[0].x)) \(number(points[0].y))")
            case .addLineToPoint:
                commands.append("L\(number(points[0].x)) \(number(points[0].y))")
            case .addQuadCurveToPoint:
                commands.append("Q\(number(points[0].x)) \(number(points[0].y)) \(number(points[1].x)) \(number(points[1].y))")
            case .addCurveToPoint:
                commands.append("C\(number(points[0].x)) \(number(points[0].y)) \(number(points[1].x)) \(number(points[1].y)) \(number(points[2].x)) \(number(points[2].y))")
            case .closeSubpath:
                commands.append("Z")
            @unknown default:
                break
            }
        }
        return commands.joined()
    }

    private nonisolated static func number(_ value: CGFloat) -> String {
        var text = String(format: "%.3f", Double(value))
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") {
            text.removeLast()
            if !text.contains(".") { break }
        }
        return text
    }

    private enum Error: Swift.Error {
        case encodeFailed
        case renderFailed
    }
}
