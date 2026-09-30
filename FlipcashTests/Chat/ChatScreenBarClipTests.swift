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
            screen.setBarHeight(height, accessories: BarAccessories(open: open, exitingHeight: exiting, mentionsHeight: mentions))
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

    @Test("The mention list stacks over an open reply and the clip reaches the whole bar")
    func mentionsOverReply_clipReachesTheWholeBar() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + strip, open: [.reply])
        report(screen, composerRow + strip + 3 * row, open: [.reply, .mentions], mentions: 3 * row)
        #expect(clipHeight(bar, window) == composerRow + strip + 3 * row)
    }

    @Test("Closing the reply under an open list keeps the list, even as its rows change mid-close")
    func replyClosesUnderTheList_keepsTheList() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow)
        report(screen, composerRow + strip + 3 * row, open: [.reply, .mentions], mentions: 3 * row)

        report(screen, composerRow + strip + 3 * row, open: [.mentions], exiting: strip, mentions: 3 * row)
        #expect(clipHeight(bar, window) == composerRow + 3 * row)

        // A search answers while the strip is still fading and the list drops to one row. The strip
        // is still in the measurement and still has to stay covered.
        report(screen, composerRow + strip + row, open: [.mentions], exiting: strip, mentions: row)
        #expect(clipHeight(bar, window) == composerRow + row)

        report(screen, composerRow + row, open: [.mentions], mentions: row)
        #expect(clipHeight(bar, window) == composerRow + row)
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
