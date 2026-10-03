//
//  ComposerChipStripTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Composer chip strip")
struct ComposerChipStripTests {

    @Test("A chip still preparing or uploading shows only its thumbnail; the sent bubble shows progress", arguments: [
        ComposerChip.State.preparing,
        .uploading,
    ])
    func inFlightShowsNothing(state: ComposerChip.State) {
        #expect(ComposerChipBadge(state) == .none)
    }

    @Test("An uploaded chip shows only its thumbnail")
    func uploadedShowsNothing() {
        #expect(ComposerChipBadge(.uploaded(BlobID(data: Data(repeating: 1, count: 32)))) == .none)
    }

    @Test("A chip that can upload again offers Retry")
    func retryableOffersRetry() {
        #expect(ComposerChipBadge(.failed(.retryable)) == .retry)
    }

    @Test("A chip the server refused shows the error without Retry")
    func notRetryableShowsError() {
        #expect(ComposerChipBadge(.failed(.notRetryable)) == .error)
    }

    @Test("The strip shows for staged chips outside an edit", arguments: [
        (0, false, false),
        (1, false, true),
        (10, false, true),
        (1, true, false),
    ])
    func stripVisibility(chipCount: Int, isEditing: Bool, expected: Bool) {
        #expect(ComposerChipStrip.isShown(chipCount: chipCount, isEditing: isEditing) == expected)
    }
}
