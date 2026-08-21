//
//  TipCardExportTests.swift
//  FlipcashTests
//

import Foundation
import UIKit
import Testing
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Tip Card Export")
struct TipCardExportTests {

    @Test("SVG export writes a standalone document with a ground behind the code")
    func svgExport() throws {
        let url = try #require(TipCardExport.file(for: .svg, codeData: .placeholder35, name: "Ada"))
        defer { TipCardExport.discard(url) }

        #expect(url.lastPathComponent == "Tip Ada.svg")

        let svg = try String(contentsOf: url, encoding: .utf8)
        #expect(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\""))
        // Codes are light-on-dark; without the rect the export is invisible on
        // anything pale.
        #expect(svg.contains("fill=\"#19191A\""))
        #expect(svg.contains("<circle"))
        #expect(svg.hasSuffix("</svg>\n"))
    }

    @Test("PNG export writes an image at the export size")
    func pngExport() throws {
        let url = try #require(TipCardExport.file(for: .png, codeData: .placeholder35, name: "Ada"))
        defer { TipCardExport.discard(url) }

        #expect(url.lastPathComponent == "Tip Ada.png")

        let image = try #require(UIImage(data: try Data(contentsOf: url)))
        #expect(image.size == CGSize(width: 1024, height: 1024))
    }

    @Test("A missing display name still produces a named file")
    func unnamedExport() throws {
        let url = try #require(TipCardExport.file(for: .svg, codeData: .placeholder35, name: nil))
        defer { TipCardExport.discard(url) }

        #expect(url.lastPathComponent == "Tip Card.svg")
    }

    /// A display name is server-supplied text landing in a path component.
    @Test("Path separators in the display name don't reach the file path")
    func namesCannotSteerThePath() throws {
        let url = try #require(TipCardExport.file(for: .svg, codeData: .placeholder35, name: "../../etc/Ada"))
        defer { TipCardExport.discard(url) }

        #expect(url.lastPathComponent == "Tip .. .. etc Ada.svg")
    }

    @Test("Discarding an export takes its directory with it")
    func discardRemovesTheDirectory() throws {
        let url = try #require(TipCardExport.file(for: .svg, codeData: .placeholder35, name: "Ada"))
        let directory = url.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: directory.path))

        TipCardExport.discard(url)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
