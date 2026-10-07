//
//  ProfileSetupEnvironmentTests.swift
//  FlipcashTests
//

import SwiftUI
import Testing
@testable import Flipcash

/// The profile-setup screens read `ProfileCreationState` from the environment.
/// It once came only from the tips stack's roots, so pushing either screen onto
/// any other stack aborted on the missing object.
///
/// Each test renders the destination with only the app and session environment,
/// which is all a non-tips stack provides. A regression aborts the test run
/// rather than failing one test: a missing environment object is a fatal error.
@MainActor
@Suite("Profile Setup Environment Tests")
struct ProfileSetupEnvironmentTests {

    @Test("The name step renders with only the session environment")
    func nameStepRendersWithoutStackState() throws {
        let window = try Self.host(.profileName)
        #expect(window.rootViewController?.view.subviews.isEmpty == false)
    }

    @Test("The photo step renders with only the session environment")
    func photoStepRendersWithoutStackState() throws {
        let window = try Self.host(.profilePhoto)
        #expect(window.rootViewController?.view.subviews.isEmpty == false)
    }

    private static func host(_ destination: AppRouter.Destination) throws -> UIWindow {
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let view = NavigationStack {
            DestinationView(destination: destination)
        }
        .injectingEnvironment(from: sessionContainer)
        .injectingEnvironment(from: Container.mock)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }
}
