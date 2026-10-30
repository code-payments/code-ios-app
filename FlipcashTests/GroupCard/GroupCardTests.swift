//
//  GroupCardTests.swift
//  FlipcashTests
//

import CoreImage
import Foundation
import Testing
import UIKit
import FlipcashCore
@testable import Flipcash

/// An invite link of the shape `CreateInvite` returns: the secret rides in the fragment.
private let inviteLinkURL = "https://app.flipcash.com/chat/invite#s=kQ3vR8mZp4LwN2yTb7cXe1aFhJ6sDg0uVq5oIrKxT9a"
private let plainLinkURL = "https://app.flipcash.com/chat/52fba6a9-3940-899e-af16-eddf7c6364b2"

@Suite("Group scan card")
struct GroupCardTests {

    private static let id = ConversationID(data: Data([
        0x52, 0xfb, 0xa6, 0xa9, 0x39, 0x40, 0x89, 0x9e,
        0xaf, 0x16, 0xed, 0xdf, 0x7c, 0x63, 0x64, 0xb2,
    ]))
    private static let expectedURL = "https://app.flipcash.com/chat/52fba6a9-3940-899e-af16-eddf7c6364b2"

    private static func geometry() throws -> GroupQRGeometry {
        GroupQRGeometry(modules: try #require(QRModules.encode(expectedURL)))
    }

    // MARK: - URL -

    @Test("1: the card URL is the dashed lowercase UUID invite")
    func url() {
        let card = GroupCardScreen.Card(id: Self.id, title: nil, avatar: nil, blurhash: nil, memberCount: 0, link: .plain)
        #expect(card.url.absoluteString == Self.expectedURL)
    }

    @Test("An invite link's card encodes the invite link, not the plain link")
    func inviteURL() {
        let card = GroupCardScreen.Card(
            id: Self.id, title: nil, avatar: nil, blurhash: nil, memberCount: 0,
            link: .invite(URL(string: inviteLinkURL)!, expiresAt: nil)
        )
        #expect(card.url.absoluteString == inviteLinkURL)
    }

    @Test("2: any group id matches the invite pattern")
    func urlPattern() throws {
        let regex = try Regex(#"^https://app\.flipcash\.com/chat/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$"#)
        for _ in 0..<20 {
            let id = ConversationID(data: withUnsafeBytes(of: UUID().uuid) { Data($0) })
            #expect(try regex.wholeMatch(in: URL.groupChatInvite(for: id).absoluteString) != nil)
        }
    }

    // MARK: - Encoding -

    @Test("4: the symbol is version 6 at level Q")
    func encoding() throws {
        let modules = try #require(QRModules.encode(Self.expectedURL))
        #expect(modules.size == 41)
        #expect(modules.version == 6)
        #expect(modules.errorCorrection == .quartile)
    }

    @Test("3: the styled QR rendered with its logo decodes to the URL", arguments: [plainLinkURL, inviteLinkURL])
    func styledDecodes(url: String) throws {
        let geometry = GroupQRGeometry(modules: try #require(QRModules.encode(url)))
        let data = try #require(GroupCardExport.png(geometry))
        let image = try #require(CIImage(data: data))
        let detector = try #require(CIDetector(
            ofType: CIDetectorTypeQRCode, context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ))
        let messages = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(messages.contains(url))
    }

    // MARK: - Naming and copy -

    @Test("5, 6: the card's title falls back as specified")
    func displayText() {
        let owls = GroupCardScreen.Card(id: Self.id, title: "Night Owls", avatar: nil, blurhash: nil, memberCount: 0, link: .plain)
        #expect(owls.displayTitle == "Night Owls")

        let untitled = GroupCardScreen.Card(id: Self.id, title: "", avatar: nil, blurhash: nil, memberCount: 0, link: .plain)
        #expect(untitled.displayTitle == "Group Chat")
    }

    @Test("6, 7: export filenames", arguments: [
        ("", "Group Card.png"),
        ("A/B: Test", "Join AB Test.png"),
        ("Night Owls", "Join Night Owls.png"),
    ])
    func filenames(title: String, expected: String) {
        #expect(GroupCardExport.filename(for: .png, title: title) == expected)
        #expect(GroupCardExport.filename(for: .svg, title: title) == (expected as NSString).deletingPathExtension + ".svg")
    }

    // MARK: - Export -

    @Test("8: PNG is 1024 square, transparent at the corner, white at the centre")
    func png() throws {
        let data = try #require(GroupCardExport.png(try Self.geometry()))
        let image = try #require(UIImage(data: data)?.cgImage)
        #expect(image.width == 1024 && image.height == 1024)

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: -x, y: -(1023 - y), width: 1024, height: 1024))
            return rgba
        }
        #expect(pixel(0, 0)[3] == 0)
        // The mark's centre: the middle bar of the logo.
        let centre = pixel(512, 512)
        #expect(centre[0] > 200 && centre[1] > 200 && centre[2] > 200 && centre[3] == 255)
    }

    @Test("9: SVG viewBox is modules plus quiet zone")
    func svg() throws {
        let svg = GroupCardExport.svg(try Self.geometry())
        #expect(svg.contains(#"viewBox="0 0 49 49""#))
        #expect(svg.contains(##"fill="#2E2E30""##))
        #expect(!svg.contains("<image"))
    }

    // MARK: - Rounding -

    @Test("12: a 3 x 1 run rounds the outer corners only")
    func rounding() {
        let set: (Int, Int) -> Bool = { x, y in y == 0 && (0...2).contains(x) }
        #expect(GroupQRGeometry.RoundedCorners.of(x: 0, y: 0, isSet: set) == [.topLeading, .bottomLeading])
        #expect(GroupQRGeometry.RoundedCorners.of(x: 1, y: 0, isSet: set) == [])
        #expect(GroupQRGeometry.RoundedCorners.of(x: 2, y: 0, isSet: set) == [.topTrailing, .bottomTrailing])
    }

    // MARK: - Tile -

    @Test("10, 11: the card tile is for group subjects only")
    func tile() {
        #expect(ShareToChatsSheet.showsGroupCardTile(for: .group(Self.id)))
        #expect(!ShareToChatsSheet.showsGroupCardTile(for: .message(URL(string: "https://app.flipcash.com/chat/x")!)))
        #expect(!ShareToChatsSheet.showsGroupCardTile(
            for: .user(userID: UUID(), username: nil, displayName: "A", directChatID: nil)
        ))
    }
}
