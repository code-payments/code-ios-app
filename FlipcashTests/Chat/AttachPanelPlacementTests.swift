//
//  AttachPanelPlacementTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import SwiftUI
import UIKit
import FlipcashCore
import FlipcashStore
import FlipcashUI
@testable import Flipcash

/// The real bar, hosted the way the chat screen hosts it, on a live window.
@MainActor
struct AttachPanelHost {

    let window: UIWindow
    let screen: ChatScreenViewController
    let barHost: UIHostingController<AnyView>
    let model: ConversationBarModel
    let composer: ComposerModel
    private let screenBox: ScreenBox
    private let databaseURL: URL

    init(windowSize: CGSize = CGSize(width: 402, height: 874)) throws {
        let (database, url) = try Database.makeTemp()
        databaseURL = url
        let controller = ConversationController(
            fetching: MockConversations(), membership: MockConversations(), viewerSettings: MockConversations(),
            messaging: MockConversations(), streaming: MockConversations(),
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: UUID(),
            typingHeartbeatInterval: .seconds(3), incomingTypingExpiry: .seconds(10)
        )
        let model = ConversationBarModel()
        let composer = ComposerModel()
        self.model = model
        self.composer = composer

        let screenBox = ScreenBox()
        self.screenBox = screenBox
        let root = HostedBar(controller: controller, model: model, composer: composer, screenBox: screenBox)

        barHost = UIHostingController(rootView: AnyView(root))
        barHost.view.backgroundColor = .clear
        barHost.view.clipsToBounds = false
        screen = ChatScreenViewController(bar: barHost.view, barController: barHost)
        screenBox.screen = screen

        // On the host app's scene, so the window is actually on screen and SwiftUI lays the bar out.
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: windowSize)
        } else {
            window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
        }
        window.windowLevel = .alert + 1
        window.rootViewController = screen
        window.makeKeyAndVisible()
        screen.loadViewIfNeeded()
        window.layoutIfNeeded()
    }

    /// Lets SwiftUI and UIKit settle a few turns.
    func settle() async {
        for _ in 0..<8 {
            window.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    /// The bar's measured height, as last reported to the screen.
    var barHeight: CGFloat { screenBox.barHeight }

    /// The window-space point `distance` above the bar's top edge, over `+`'s column: `+` is the
    /// first control in the field's bottom row, past the compact bar's margin and the field's padding.
    func pointAboveBar(by distance: CGFloat) -> CGPoint {
        CGPoint(x: model.overKeyboard.plusFrame.midX, y: window.bounds.height - barHeight - distance)
    }

    /// The window's rendered colour at `point`.
    func renderedColor(at point: CGPoint, backdrop: UIColor) -> UIColor {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { ctx in
            backdrop.setFill()
            ctx.fill(window.bounds)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cg = image.cgImage!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(cg, in: CGRect(x: -point.x, y: point.y - CGFloat(cg.height) + 1, width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }

    func tearDown() {
        window.isHidden = true
        Database.removeTemp(at: databaseURL)
    }

    fileprivate final class ScreenBox {
        weak var screen: ChatScreenViewController?
        var barHeight: CGFloat = 0
    }
}

/// The bar as `ChatScreenRepresentable` hosts it: measured, bottom-pinned, and lifting the screen's
/// clip while the panel holds the room above it.
private struct HostedBar: View {

    let controller: ConversationController
    let model: ConversationBarModel
    let composer: ComposerModel
    let screenBox: AttachPanelHost.ScreenBox

    var body: some View {
        ConversationBottomBar(
            showsSendCash: true,
            conversationID: .test(1),
            symbol: "$",
            onSendCash: {},
            model: model,
            composer: composer,
            acceptsMedia: true
        )
        .environment(controller)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            screenBox.barHeight = height
            screenBox.screen?.setBarHeight(height, accessories: BarAccessories())
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .modifier(BarOverflowReporting(model: model) { [screenBox] in screenBox.screen })
    }
}

@MainActor
@Suite("Attach panel placement")
struct AttachPanelPlacementTests {

    @Test("The open panel floats above the bar, over the transcript, and takes taps there")
    func openPanel_sitsAbovePlus() async throws {
        let host = try AttachPanelHost()
        defer { host.tearDown() }
        await host.settle()

        host.model.attachPanel.open()
        await host.settle()

        // Inside the panel's rows, above the bar: before the fix the panel hung down from `+`'s top
        // and nothing of the bar reached here.
        let point = host.pointAboveBar(by: 40)
        let transcript = host.renderedColor(at: CGPoint(x: point.x, y: 100), backdrop: .black)
        let probe = host.renderedColor(at: point, backdrop: .black)
        #expect(!probe.isClose(to: transcript), "Panel is not drawn above the bar")

        // The screen lifts its clip for the panel, so taps there reach the bar rather than the transcript.
        let hit = try #require(host.window.hitTest(point, with: nil))
        #expect(hit.isDescendant(of: host.barHost.view), "Taps above the bar miss the panel")
    }

    @Test("The bar is one row tall: +, the text, and the controls beside it")
    func barHeight_isOneRow() async throws {
        let host = try AttachPanelHost()
        defer { host.tearDown() }
        await host.settle()

        let expected = BarMetrics.contentHeight + BarMetrics.contentPadding * 2
        #expect(abs(host.barHeight - expected) < 1, "Bar is \(host.barHeight) tall, expected \(expected)")
    }

    @Test("The menu's leading edge is the composer field's, past the compact margin and the `$` beside it")
    func menu_linesUpWithField() async throws {
        let host = try AttachPanelHost()
        defer { host.tearDown() }
        await host.settle()

        let plus = host.model.overKeyboard.plusFrame
        let menu = AttachSurfaceLayout.menuRect(plus: plus, size: CGSize(width: 280, height: 200), placement: .standsOnPlus)
        let field = BarMetrics.compactInset + BarMetrics.contentHeight + ConversationBottomBar.leadingSpacing
        #expect(abs(menu.minX - field) < 1, "Menu starts at \(menu.minX), the field at \(field)")
    }

    @Test("The card stands on the composer over the transcript, takes taps on itself, and lets taps above it through")
    func card_overlaysTranscript() async throws {
        let host = try AttachPanelHost()
        defer { host.tearDown() }
        await host.settle()
        let barHeight = host.barHeight

        // Photos, not the camera, which would put up the system's permission prompt in the test host.
        host.model.attachCard.open(.photos, screenHeight: host.window.bounds.height)
        await host.settle()

        // The card is an overlay: the bar, and so the transcript's inset, keeps the composer's height.
        #expect(host.barHeight == barHeight, "The card resized the bar")

        let cardTop = host.model.cardTop
        let cardBottom = cardTop + host.model.attachCard.height
        let barTop = host.window.bounds.height - barHeight
        #expect(cardBottom > barTop + 20 && cardBottom <= host.window.bounds.height, "The card does not stand on the composer row")

        let onCard = CGPoint(x: host.window.bounds.midX, y: cardTop + 60)
        let onCardHit = try #require(host.window.hitTest(onCard, with: nil))
        #expect(onCardHit.isDescendant(of: host.barHost.view), "Taps on the card miss it")

        let aboveCard = CGPoint(x: host.window.bounds.midX, y: cardTop - 40)
        let aboveHit = host.window.hitTest(aboveCard, with: nil)
        #expect(aboveHit.map { !$0.isDescendant(of: host.barHost.view) } ?? true, "The bar swallows taps above the card")
    }

    @Test("Adding from the card shrinks the surface onto the staged chip, which shows once it has landed")
    func card_landsOnChip() async throws {
        let host = try AttachPanelHost()
        defer { host.tearDown() }
        await host.settle()
        host.model.attachCard.open(.photos, screenHeight: host.window.bounds.height)
        await host.settle()

        let red = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let chipID = try #require(
            host.composer.stageChip(image: red, preview: red, uploader: ChatMediaUploader(blob: MockChatMediaBlobStore()))?.id
        )
        host.model.attachCard.beginLanding(on: chipID)

        // The strip lays the chip out, the bar reports it, and the card shrinks onto it.
        await host.settle()
        #expect(!host.model.attachCard.isOpen, "The card never shrank onto the chip")
        await host.settle()
        #expect(host.model.attachCard.landingChipID == nil, "The landing never finished")
        #expect(host.composer.chips.count == 1)
    }
}

private extension UIColor {

    func isClose(to other: UIColor, tolerance: CGFloat = 0.02) -> Bool {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < tolerance && abs(g1 - g2) < tolerance && abs(b1 - b2) < tolerance
    }
}
