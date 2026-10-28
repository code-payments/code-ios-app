//
//  Regression_6ae14e5bc6c10d79fa38eb61.swift
//  FlipcashTests
//
//  EXC_BREAKPOINT in closure #1 in PhotoLibrary.save(originalData:). Saving a photo from
//  the chat viewer handed performChanges a change block formed in the main-actor-default
//  app target, so the block was main-actor isolated. Photos runs it on its own queue, and
//  the executor check trapped in dispatch_assert_queue.
//
//  Fix: the change block is a @Sendable closure, so it carries no actor isolation and runs
//  on whichever queue Photos picks.
//
//  Needs add-only Photos access for the test host, which the runner can't grant itself:
//  `xcrun simctl privacy <udid> grant photos-add com.flipcash.app.ios`. Without it the test
//  is skipped, since performChanges would throw before running the block.
//

import Photos
import Testing
import UIKit
@testable import Flipcash

@Suite("Regression: 6ae14e5 – Saving a photo's original traps on Photos' queue", .bug("6ae14e5bc6c10d79fa38eb61"))
struct Regression_6ae14e5 {

    @Test(
        "Saving original bytes runs the change block on Photos' queue",
        .enabled(if: PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized)
    )
    func savesOriginal() async throws {
        let png = try #require(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.pngData())

        try await PhotoLibrary.save(originalData: png)
    }
}
