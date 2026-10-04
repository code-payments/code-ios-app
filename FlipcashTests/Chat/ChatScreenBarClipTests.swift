//
//  ChatScreenBarClipTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI

/// The box the bar is seen through, driven entirely by `setBarHeight(_:accessories:)`.
///
/// The bar reports its whole measured height and the cards above the composer row: which are open,
/// and how tall the ones that have closed but are still mounted are. The clip is that height less
/// the closing cards, and it travels only when the open set changes.
///
/// Animations are switched off around each call so the constraint's destination can be read off the
/// frame in the same pass.
@MainActor
@Suite("Chat screen bar clip")
struct ChatScreenBarClipTests {

    private let composerRow: CGFloat = 60
    private let strip: CGFloat = 50
    private let row: CGFloat = 50

    /// A screen on a live window, since the clip's animated path is taken only in one.
    private func makeScreen() -> (ChatScreenViewController, UIView, UIWindow) {
        let bar = UIView()
        let screen = ChatScreenViewController(bar: bar)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = screen
        window.makeKeyAndVisible()
        screen.loadViewIfNeeded()
        window.layoutIfNeeded()
        return (screen, bar, window)
    }

    /// What the screen sees as the bar: the clip is the bar's superview.
    private func clipHeight(_ bar: UIView, _ window: UIWindow) -> CGFloat {
        window.layoutIfNeeded()
        return bar.superview?.frame.height ?? 0
    }

    private func report(
        _ screen: ChatScreenViewController,
        _ height: CGFloat,
        open: Set<BarAccessories.Kind> = [],
        exiting: CGFloat = 0,
        mentions: CGFloat = 0
    ) {
        UIView.performWithoutAnimation {
            // What the bar measures under the list: everything but the list, less a strip collapsing
            // beside it.
            let rest = height - mentions - (open.contains(.mentions) ? exiting : 0)
            screen.setBarHeight(height, accessories: BarAccessories(open: open, exitingHeight: exiting, restHeight: rest))
        }
    }

    @Test("A reply opened after the bar was measured uncovers the strip, and closes back over it")
    func replyOpenedAfterMeasurement_opensAndCloses() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        #expect(clipHeight(bar, window) == composerRow)

        report(screen, composerRow + strip, open: [.reply])
        #expect(clipHeight(bar, window) == composerRow + strip)

        // The strip is still mounted while it fades, so the bar keeps measuring tall and reports it
        // as closing.
        report(screen, composerRow + strip, exiting: strip)
        #expect(clipHeight(bar, window) == composerRow)

        // It unmounts and the bar measures short; the clip was already there.
        report(screen, composerRow)
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("A reply the bar arrives already open on closes back to the composer row")
    func replyRestoredBeforeMeasurement_closesToTheComposerRow() {
        let (screen, bar, window) = makeScreen()

        // A restored draft is aimed before the bar has ever been measured, so the first height the
        // screen is given already carries the strip.
        report(screen, composerRow + strip, open: [.reply])
        #expect(clipHeight(bar, window) == composerRow + strip)

        report(screen, composerRow + strip, exiting: strip)
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("A draft wrapping to a second line mid-reply keeps the strip uncovered")
    func barGrowsMidReply_keepsTheStripUncovered() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + strip, open: [.reply])

        let secondLine: CGFloat = 20
        report(screen, composerRow + secondLine + strip, open: [.reply])
        #expect(clipHeight(bar, window) == composerRow + secondLine + strip)

        report(screen, composerRow + secondLine + strip, exiting: strip)
        #expect(clipHeight(bar, window) == composerRow + secondLine)
    }

    @Test("A composer shrinking holds the clip until its spring is done, and reserves the new room at once")
    func composerShrink_holdsTheClip() async throws {
        let (screen, bar, window) = makeScreen()
        let stacked = composerRow + 48

        report(screen, composerRow)
        report(screen, stacked)
        let transcript = try #require(screen.view.firstSubview(of: UICollectionView.self))
        let insetBefore = transcript.contentInset.bottom

        report(screen, composerRow)
        #expect(transcript.contentInset.bottom == insetBefore - 48)
        #expect(clipHeight(bar, window) == stacked, "The clip keeps the text and caret uncovered on the way down")

        try await Task.sleep(for: .seconds(ChatMotion.replySurface.duration + 0.2))
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("The mention list stacks over an open reply and the clip reaches the whole bar")
    func mentionsOverReply_clipReachesTheWholeBar() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + strip, open: [.reply])
        report(screen, composerRow + strip + 3 * row, open: [.reply, .mentions], mentions: 3 * row)
        #expect(clipHeight(bar, window) == composerRow + strip + 3 * row)
    }

    @Test("Closing the reply under an open list never cuts into the list, and settles once the strip has collapsed")
    func replyClosesUnderTheList_keepsTheList() async throws {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + strip + 3 * row, open: [.reply, .mentions], mentions: 3 * row)

        // The strip collapses itself under the list, so the clip holds its height while it does.
        report(screen, composerRow + strip + 3 * row, open: [.mentions], exiting: strip, mentions: 3 * row)
        #expect(clipHeight(bar, window) >= composerRow + 3 * row)

        // A search answers mid-close and the list drops to one row: still held, still over the list.
        report(screen, composerRow + strip + row, open: [.mentions], exiting: strip, mentions: row)
        #expect(clipHeight(bar, window) >= composerRow + row)

        report(screen, composerRow + row, open: [.mentions], mentions: row)
        try await Task.sleep(for: .seconds(ChatMotion.replyMerge.duration + 0.2))
        #expect(clipHeight(bar, window) == composerRow + row)
    }

    @Test("Closing the list over an open reply never cuts into the strip, and settles once the list has merged back")
    func listClosesOverTheReply_keepsTheStrip() async throws {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + strip, open: [.reply])
        report(screen, composerRow + strip + 3 * row, open: [.reply, .mentions], mentions: 3 * row)

        // The list collapses into the strip's glass, so the clip holds its height while it does.
        report(screen, composerRow + strip, open: [.reply])
        #expect(clipHeight(bar, window) == composerRow + strip + 3 * row)

        try await Task.sleep(for: .seconds(ChatMotion.replyMerge.duration + 0.2))
        #expect(clipHeight(bar, window) == composerRow + strip)
    }

    @Test("A list gaining rows while open follows the bar")
    func listRowsChange_followTheBar() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + row, open: [.mentions], mentions: row)
        report(screen, composerRow + 4 * row, open: [.mentions], mentions: 4 * row)
        #expect(clipHeight(bar, window) == composerRow + 4 * row)

        report(screen, composerRow + 4 * row, exiting: 4 * row)
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("The room reported leaves the list out and counts the reply strip")
    func mentionRoom_excludesTheListAndCountsTheStrip() {
        let (screen, _, window) = makeScreen()
        var rooms: [CGFloat] = []
        screen.onMentionRoomChange = { rooms.append($0) }

        report(screen, composerRow + strip, open: [.reply])
        window.layoutIfNeeded()
        let withStrip = rooms.last

        report(screen, composerRow + strip + 2 * row, open: [.reply, .mentions], mentions: 2 * row)
        window.layoutIfNeeded()
        #expect(rooms.last == withStrip)

        report(screen, composerRow + 2 * row, open: [.mentions], mentions: 2 * row)
        window.layoutIfNeeded()
        #expect(rooms.last.map { $0 - strip } == withStrip)
    }
}

private extension UIView {
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstSubview(of: type) { return match }
        }
        return nil
    }
}
