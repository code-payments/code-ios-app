//
//  DeepLinkControllerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
@testable import Flipcash

@MainActor
@Suite("DeepLinkController routing")
struct DeepLinkControllerTests {

    private let sessionAuthenticator = SessionAuthenticator(container: Container())

    private func makeController() -> DeepLinkController {
        DeepLinkController(sessionAuthenticator: sessionAuthenticator)
    }

    @Test("A recognized route resolves to an action, so open reports it handled")
    func recognizedRoute_isHandled() {
        #expect(makeController().open(URL(string: "flipcash://give")!) == true)
    }

    @Test("An ordinary web URL resolves to no action, so open reports it unhandled and the caller opens it externally")
    func ordinaryWebURL_isNotHandled() {
        #expect(makeController().open(URL(string: "https://apple.com")!) == false)
    }

    @Test("A duplicate in-flight open is reported handled without re-processing")
    func duplicateInFlightOpen_isDeduped() {
        let controller = makeController()
        // The first open enters the in-flight set; its async cleanup can't run before the next
        // synchronous call, so the immediate duplicate is short-circuited to handled.
        _ = controller.open(URL(string: "https://apple.com")!)
        #expect(controller.open(URL(string: "https://apple.com")!) == true)
    }
}
