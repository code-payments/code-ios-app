//
//  ChatScreenBarClipTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI

/// The box the bar is seen through, driven entirely by `setBarHeight(_:replying:)`.
///
/// The bar reports one number — its whole measured height — and whether a reply is open. The clip
/// has to turn those two into the height the screen actually sees, which is the same number while a
/// reply is open and that number minus the strip once it closes. The strip's own height is never
/// reported: it has to be inferred from the growth, and a draft restored into the composer is where
/// that inference has the least to go on, because the strip can be in the very first height the
/// screen is ever given.
///
/// Animations are switched off around each call so the constraint's destination can be read off the
/// frame in the same pass.
@MainActor
@Suite("Chat screen bar clip")
struct ChatScreenBarClipTests {

    private let composerRow: CGFloat = 60
    private let strip: CGFloat = 50

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

    private func report(_ screen: ChatScreenViewController, _ height: CGFloat, replying: Bool) {
        UIView.performWithoutAnimation {
            screen.setBarHeight(height, replying: replying)
        }
    }

    @Test("A reply opened after the bar was measured uncovers the strip, and closes back over it")
    func replyOpenedAfterMeasurement_opensAndCloses() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow, replying: false)
        #expect(clipHeight(bar, window) == composerRow)

        report(screen, composerRow + strip, replying: true)
        #expect(clipHeight(bar, window) == composerRow + strip)

        // The strip is still mounted while it fades, so the bar keeps measuring tall and the clip
        // has to come back to the composer row on its own.
        report(screen, composerRow + strip, replying: false)
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("A reply the bar arrives already open on shows the strip, and closes back to the composer row")
    func replyRestoredBeforeMeasurement_closesToTheComposerRow() {
        let (screen, bar, window) = makeScreen()

        // A restored draft is aimed before the bar has ever been measured, so the first height the
        // screen is given already carries the strip.
        report(screen, composerRow + strip, replying: true)
        #expect(clipHeight(bar, window) == composerRow + strip)

        // How much of that height was the strip is unknowable — the screen never saw this bar
        // without one — so the close cannot take it back off, and the clip holds the bar's height
        // rather than guessing at a number that was never measured.
        report(screen, composerRow + strip, replying: false)
        #expect(clipHeight(bar, window) == composerRow + strip)

        // It settles once the strip unmounts and the bar measures short on its own.
        report(screen, composerRow, replying: false)
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("A strip that arrives a pass after the reply does still closes back to the composer row")
    func replyMeasuredInTwoSteps_closesToTheComposerRow() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow, replying: false)

        // The strip mounts at zero height and takes its own a pass later, so the bar reports the
        // reply as open before it reports the height that carries it.
        report(screen, composerRow, replying: true)
        report(screen, composerRow + strip, replying: true)
        #expect(clipHeight(bar, window) == composerRow + strip)

        report(screen, composerRow + strip, replying: false)
        #expect(clipHeight(bar, window) == composerRow)
    }

    @Test("A draft wrapping to a second line mid-reply keeps the strip uncovered")
    func barGrowsMidReply_keepsTheStripUncovered() {
        let (screen, bar, window) = makeScreen()

        report(screen, composerRow, replying: false)
        report(screen, composerRow + strip, replying: true)

        let secondLine: CGFloat = 20
        report(screen, composerRow + secondLine + strip, replying: true)
        #expect(clipHeight(bar, window) == composerRow + secondLine + strip)

        report(screen, composerRow + secondLine + strip, replying: false)
        #expect(clipHeight(bar, window) == composerRow + secondLine)
    }
}
