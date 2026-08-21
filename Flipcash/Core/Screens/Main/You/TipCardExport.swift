//
//  TipCardExport.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashUI
import SharedCoreKit

/// Writes a tip code out as a file for the You tab's "Download As" sheet.
///
/// Both formats draw the same figure: the SVG comes from the shared Kotlin
/// renderer, the PNG from the same `CodeView` the app draws on screen, so a
/// user who exports one and then the other gets the same code twice rather
/// than two different pictures of it.
enum TipCardExport {

    /// The exported square's side. Only sets the PNG's pixel count — the SVG
    /// scales losslessly from it.
    private static let dimension: CGFloat = 1024

    /// Codes are drawn light-on-dark, so an export with no ground behind it is
    /// invisible the moment it lands on a light surface. Both formats paint the
    /// app's own background (`background.colorset`) behind the marks.
    private static let backgroundHex = "#19191A"

    /// Renders `codeData` as `format` into a file named for `name`, or returns
    /// `nil` if rendering or writing it out failed.
    ///
    /// The file lands in a directory of its own under the temporary directory,
    /// so ``discard(_:)`` can take the whole thing away afterwards without
    /// touching anything else.
    @MainActor
    static func file(for format: TipCardDownloadFormat, codeData: Data, name: String?) -> URL? {
        do {
            let contents: Data
            switch format {
            case .png:
                guard let png = png(codeData: codeData) else {
                    throw Error.renderFailed
                }
                contents = png

            case .svg:
                contents = Data(svg(codeData: codeData).utf8)
            }

            let directory = FileManager.default.temporaryDirectory
                .appending(path: "TipCardExport-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let url = directory.appending(path: filename(for: format, name: name))
            try contents.write(to: url, options: .atomic)
            return url

        } catch {
            ErrorReporting.captureError(
                error,
                reason: "Failed to export tip card",
                metadata: ["format": format.rawValue]
            )
            return nil
        }
    }

    /// Removes a file handed out by ``file(for:codeData:name:)``, along with the
    /// directory it was written into.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Rendering -

    private static func svg(codeData: Data) -> String {
        KikCode.svg(payload: codeData, dimension: dimension, background: backgroundHex)
    }

    @MainActor
    private static func png(codeData: Data) -> Data? {
        let renderer = ImageRenderer(
            content: CodeView(data: codeData)
                .foregroundStyle(Color.white)
                .frame(width: dimension, height: dimension)
                .background(Color.backgroundMain)
        )
        // The frame above is already in export pixels, so rendering at the
        // screen's scale would multiply the size a second time.
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }

    // MARK: - Naming -

    /// `Tip Ada.svg` — the name the share sheet shows and the file the user
    /// ends up with. Path separators are dropped so a display name can't steer
    /// where the file is written.
    private static func filename(for format: TipCardDownloadFormat, name: String?) -> String {
        let subject = name?
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let stem = if let subject, !subject.isEmpty { "Tip \(subject)" } else { "Tip Card" }
        return "\(stem).\(format.rawValue)"
    }

    private enum Error: Swift.Error {
        case renderFailed
    }
}
