//
//  FlipcashApp.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-03.
//

import SwiftUI
import CoreSpotlight
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
            #if DEBUG
            if MotionSandbox.isRequested {
                MotionSandbox()
            } else if let benchmark = ScrollBenchmark.requested {
                benchmark
            } else {
                mainScene
            }
            #else
            mainScene
            #endif
        }
    }

    private var mainScene: some View {
        ContainerScreen()
            // Applied once for the whole app: the style reaches every scrollable
            // view below it, pushed destinations and sheet content included, so
            // no screen has to opt in. The effect is drawn by a bar's own
            // background, so naming both edges costs nothing where there is no
            // bar to draw from.
            .softScrollEdge(for: [.top, .bottom])
            .injectingEnvironment(from: appDelegate.container)
            .preferredColorScheme(.dark)
            .tint(Color.textMain)
            .onOpenURL { url in
                appDelegate.handleOpenURL(url: url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                appDelegate.handleContinue(activity)
            }
            .onContinueUserActivity(AppUserActivity.openChat) { activity in
                appDelegate.handleContinue(activity)
            }
            .withDialogWindow(
                sessionAuthenticator: appDelegate.container.sessionAuthenticator
            )
            .onScenePhaseChange(appDelegate: appDelegate)
    }
}

#if DEBUG
/// The motion sandbox, standing in for the whole app when launched with `--motion-sandbox`.
///
/// A launch argument rather than a hidden menu entry because the point is a *repeatable recording*:
/// one `xcrun simctl launch` line puts the device on the scripted send with nothing else on screen,
/// so a before/after pair differs only by the code under test. DEBUG-only, so it can't ship.
private struct MotionSandbox: UIViewControllerRepresentable {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("--motion-sandbox")
    }

    func makeUIViewController(context: Context) -> ChatMotionSandboxViewController {
        ChatMotionSandboxViewController(autoplay: true)
    }

    func updateUIViewController(_ controller: ChatMotionSandboxViewController, context: Context) {}
}

/// The transcript scroll benchmark, standing in for the whole app when launched with
/// `--scroll-benchmark`.
///
/// Same reasoning as ``MotionSandbox``: a launch argument, because the answer wanted is a number
/// that two builds can be compared on, and a comparison only means something if both runs drove the
/// transcript identically. `--scroll-benchmark-messages=N`, `--scroll-benchmark-authors=N` (0 for a
/// DM-shaped window) and `--scroll-benchmark-velocity=N` size the run; `--scroll-benchmark-pages`
/// adds the owner's reverse-paging loop on top and `--scroll-benchmark-obscured` puts the gate's
/// blur over it. DEBUG-only.
private struct ScrollBenchmark: UIViewControllerRepresentable {

    let configuration: ChatScrollBenchmarkViewController.Configuration

    static var requested: ScrollBenchmark? {
        guard ProcessInfo.processInfo.arguments.contains("--scroll-benchmark") else { return nil }
        var configuration = ChatScrollBenchmarkViewController.Configuration()
        if let messages = intArgument("--scroll-benchmark-messages") { configuration.messageCount = messages }
        if let authors = intArgument("--scroll-benchmark-authors") { configuration.authorCount = authors }
        if let velocity = intArgument("--scroll-benchmark-velocity") { configuration.velocity = CGFloat(velocity) }
        configuration.pages = ProcessInfo.processInfo.arguments.contains("--scroll-benchmark-pages")
        configuration.obscured = ProcessInfo.processInfo.arguments.contains("--scroll-benchmark-obscured")
        return ScrollBenchmark(configuration: configuration)
    }

    private static func intArgument(_ name: String) -> Int? {
        ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("\(name)=") }
            .flatMap { Int($0.dropFirst(name.count + 1)) }
    }

    func makeUIViewController(context: Context) -> ChatScrollBenchmarkViewController {
        ChatScrollBenchmarkViewController(configuration: configuration)
    }

    func updateUIViewController(_ controller: ChatScrollBenchmarkViewController, context: Context) {}
}
#endif

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
                      let scene = UIApplication.shared.firstWindowScene
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
