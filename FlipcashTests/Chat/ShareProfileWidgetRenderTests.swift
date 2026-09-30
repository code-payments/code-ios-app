//
//  ShareProfileWidgetRenderTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SwiftUI
import FlipcashCore
@testable import FlipcashUI

/// The shared-profile widget as the transcript renders it (node 10588:1979): the real cell, in a
/// window, at the designed card width.
@MainActor
@Suite("Share profile widget rendering")
struct ShareProfileWidgetRenderTests {

    private struct Rendered {
        let image: UIImage
        let card: CGSize
    }

    private func render(ownDisplayName: String?) throws -> Rendered {
        let username = try #require(Username("brad_burnham_2"))
        let cell = ChatShareProfileCell(frame: CGRect(x: 0, y: 0, width: 390, height: 207))
        cell.ownProfile = ownDisplayName.map {
            OwnProfileCard(username: username, resolved: LinkCard.User.Resolved(
                userID: UUID(), isOwn: true, displayName: $0, handle: username.handle,
                joined: nil, imageData: nil, blurHash: nil
            ))
        }
        cell.configure(
            with: ChatMessage(id: "w", content: .shareProfile(LinkCard.User(profileOf: username)), sender: .other),
            maxWidth: 390
        )

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = cell.frame
        window.overrideUserInterfaceStyle = .dark
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        // The window sits under the device's status bar; a cell in the transcript would not.
        let inset = window.safeAreaInsets
        root.additionalSafeAreaInsets = UIEdgeInsets(top: -inset.top, left: -inset.left, bottom: -inset.bottom, right: -inset.right)
        root.view.backgroundColor = UIColor(Color.backgroundMain)
        root.view.addSubview(cell)
        cell.frame = window.bounds
        cell.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        cell.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: cell.bounds.size, format: format).image { _ in
            root.view.drawHierarchy(in: root.view.bounds, afterScreenUpdates: true)
        }
        let card = try #require(Self.firstSubview(of: cell, named: "BubbleBackgroundView"))
        window.isHidden = true
        return Rendered(image: image, card: card.frame.size)
    }

    private static func firstSubview(of view: UIView, named name: String) -> UIView? {
        if String(describing: type(of: view)) == name { return view }
        return view.subviews.lazy.compactMap { firstSubview(of: $0, named: name) }.first
    }

    @Test("The card is the designed 290pt wide and about as tall as the design's 207pt")
    func designedSize() throws {
        let rendered = try render(ownDisplayName: "Brad Burnham")
        #expect(rendered.card.width == 290)
        // 12 + 64 + 12 + name + 2 + handle + 18 + 44 + 12, with the fonts' own line heights.
        #expect((195...215).contains(rendered.card.height))
        #expect(rendered.image.size.width == 390)

        if let path = ProcessInfo.processInfo.environment["SHARE_PROFILE_WIDGET_PNG"],
           let data = rendered.image.pngData() {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    @Test("Without a session profile the card still lays out at the same width")
    func withoutOwnProfile() throws {
        let rendered = try render(ownDisplayName: nil)
        #expect(rendered.card.width == 290)
    }
}
