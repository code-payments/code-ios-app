//
//  FlipcashApp.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-03.
//

import SwiftUI
import FlipcashUI

/// The main entry point for Flipcash.
///
/// `AppDelegate` is retained via `@UIApplicationDelegateAdaptor` for
/// bootstrap (logging, analytics, fonts, appearance), push token
/// registration, and `NotificationCenter`-based deep link observers.
@main
struct FlipcashApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContainerScreen(container: appDelegate.container)
                .injectingEnvironment(from: appDelegate.container)
                .preferredColorScheme(.dark)
                .tint(Color.textMain)
                .onOpenURL { url in
                    appDelegate.handleOpenURL(url: url)
                }
                .withDialogWindow(
                    sessionAuthenticator: appDelegate.container.sessionAuthenticator
                )
                .onScenePhaseChange(appDelegate: appDelegate)
        }
    }
}

// MARK: - DialogWindow Modifier -

/// Creates and retains a ``DialogWindow`` on first appearance.
///
/// `DialogWindow` needs a `UIWindowScene`, which isn't available until a
/// scene connects. This modifier defers creation to `onAppear`, grabbing
/// the first connected `UIWindowScene` (no `.foregroundActive` filter —
/// `onAppear` can fire before the scene is fully active on cold launch).
///
/// `@State` holds a reference type intentionally — SwiftUI preserves the
/// instance across redraws without observing its properties.
private struct DialogWindowModifier: ViewModifier {
    let sessionAuthenticator: SessionAuthenticator

    @State private var dialogWindow: DialogWindow?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard dialogWindow == nil,
                      let scene = UIApplication.shared.connectedScenes
                          .first(where: { $0 is UIWindowScene })
                          as? UIWindowScene
                else { return }

                dialogWindow = DialogWindow(
                    sessionAuthenticator: sessionAuthenticator,
                    windowScene: scene
                )
            }
    }
}

private extension View {
    func withDialogWindow(sessionAuthenticator: SessionAuthenticator) -> some View {
        modifier(DialogWindowModifier(sessionAuthenticator: sessionAuthenticator))
    }
}

// MARK: - ScenePhase Modifier -

/// Forwards scene phase transitions to ``AppDelegate/scenePhaseChanged(_:)``.
///
/// Observes at the view level (not on `App`) so the phase reflects this
/// specific scene rather than the aggregate across all scenes.
private struct ScenePhaseModifier: ViewModifier {
    let appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                appDelegate.scenePhaseChanged(phase)
            }
    }
}

private extension View {
    func onScenePhaseChange(appDelegate: AppDelegate) -> some View {
        modifier(ScenePhaseModifier(appDelegate: appDelegate))
    }
}
