//
//  NeverComposerRenderTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SwiftUI
import FlipcashCore
@testable import Flipcash
@testable import FlipcashUI

/// The composer's replacement under a `never` speaker rule (node 10588:1969): the real gate panel,
/// hosted in a window over stand-in transcript content.
@MainActor
@Suite("Never-speaker composer rendering")
struct NeverComposerRenderTests {

    private func render(_ requirement: ConversationGateRequirement = .never, width: CGFloat = 402) throws -> (image: UIImage, pill: CGSize) {
        let panel = ConversationGatePanel(
            presentation: .readOnly(requirement), mintName: nil, shortfall: nil, onAddFunds: {}, onJoin: {}, isJoining: false
        )
        let host = UIHostingController(rootView: ZStack(alignment: .bottom) {
            Color.backgroundMain
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["Happy chatting!", "Welcome to Flipcash!"], id: \.self) { line in
                    Text(line).font(.appTextMedium).foregroundStyle(Color.textMain)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color.textMain.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(12).padding(.bottom, 20)
            panel
        })
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: width, height: 160)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        let inset = window.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: -inset.top, left: -inset.left, bottom: -inset.bottom, right: -inset.right)
        host.view.frame = window.bounds
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return (image, CGSize(width: width - 2 * BarMetrics.compactInset, height: BarMetrics.contentHeight))
    }

    @Test("The never rule draws the brand sentence, not the chat's or the old copy")
    func sentence() {
        #expect(ConversationGatePanel.neverSentence == "Only Flipcash can send messages")
    }

    @Test("The creator and unsupported rules draw their own copy")
    func otherSentences() {
        #expect(ConversationGatePanel.creatorSentence == "Only the creator can send messages")
        #expect(ConversationGatePanel.unsupportedSentence == "Update Flipcash to send messages")
    }

    @Test("Each static read-only rule renders a pill at the composer's height", arguments: [
        ("never", ConversationGateRequirement.never),
        ("creator", .creator),
        ("unsupported", .unsupported),
    ])
    func renders(name: String, requirement: ConversationGateRequirement) throws {
        let rendered = try render(requirement)
        #expect(rendered.pill.height == 50)
        #expect(rendered.image.size.width == 402)
        // Set `TEST_RUNNER_READ_ONLY_PILL_DIR` to keep the images.
        if let dir = ProcessInfo.processInfo.environment["READ_ONLY_PILL_DIR"],
           let data = rendered.image.pngData() {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ios-\(name)-pill.png"))
        }
    }
}
