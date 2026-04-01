# AppDelegate → SwiftUI App Migration

**Date:** 2026-03-31
**Status:** Planned
**Branch:** future PR (not part of `remove-interface-reset`)

## Context

After removing the interface reset mechanism, `AppDelegate` is simpler but still uses the UIKit lifecycle as the `@main` entry point. `ContainerScreen` is already a SwiftUI view — the `UIHostingController` wrapper is just plumbing. This plan migrates to a SwiftUI `@main App` struct with `@UIApplicationDelegateAdaptor` for the remaining UIKit-only pieces.

## Current Responsibilities

| # | Responsibility | Location |
|---|---------------|----------|
| 1 | Bootstrap (logging, analytics, error reporting, fonts, appearance) | `didFinishLaunchingWithOptions` |
| 2 | Root view (`installRootScreen` → `UIHostingController` wrapping `ContainerScreen`) | `didFinishLaunchingWithOptions` |
| 3 | Lifecycle forwarding (`willResignActive`, `didEnterBackground`, `willEnterForeground`) | Lifecycle methods → `Session`, `Client`, `Preferences` |
| 4 | Deep links (`application(_:open:)`, `continue userActivity`, `NotificationCenter` observers) | Deep link methods + `handleOpenURL` |
| 5 | Push token registration | `didRegisterForRemoteNotificationsWithDeviceToken` |

## Migration Steps

### Step 1 — Create `FlipcashApp.swift`

New `@main` entry point. Eliminates `installRootScreen()`, manual `UIWindow`, and `UIHostingController`.

```swift
@main
struct FlipcashApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContainerScreen(container: appDelegate.container)
                .injectingEnvironment(from: appDelegate.container)
                .colorScheme(.dark)
                .tint(Color.textMain)
                .onOpenURL { url in
                    appDelegate.handleOpenURL(url: url)
                }
        }
    }
}
```

`onOpenURL` replaces both `application(_:open:)` and `continue userActivity`.

### Step 2 — Slim down AppDelegate

Remove from `AppDelegate`:
- `@main` attribute
- `window` property
- `installRootScreen()` method
- `application(_:open:options:)` delegate method
- `application(_:continue:restorationHandler:)` delegate method

Keep in `AppDelegate`:
- `didFinishLaunchingWithOptions` — bootstrap (logging, analytics, fonts, appearance, NotificationCenter observers)
- Push token registration — no SwiftUI equivalent exists
- `container` property (referenced by the `App` struct)
- Make `handleOpenURL` internal so the `App` struct can call it

### Step 3 — Replace lifecycle methods with ScenePhase

In `FlipcashApp`, observe `scenePhase` instead of UIKit lifecycle methods:

```swift
@Environment(\.scenePhase) private var scenePhase

.onChange(of: scenePhase) { _, phase in
    switch phase {
    case .background:
        // didEnterBackground
        sessionContainer?.session.didEnterBackground()
        container.preferences.appDidEnterBackground()
    case .active:
        // willEnterForeground + didBecomeActive
        container.client.warmUpChannel()
        sessionContainer?.session.didBecomeActive()
    case .inactive:
        // willResignActive (logging only, no-op now)
        break
    }
}
```

Remove `applicationWillResignActive`, `applicationDidEnterBackground`, `applicationWillEnterForeground` from `AppDelegate`.

### Step 4 — Deep link NotificationCenter observers

`pushDeepLinkReceived` and `qrDeepLinkReceived` are posted by `PushController` and `ScanViewModel`. Two options:

- **Quick (recommended for this PR):** Keep the observers in `AppDelegate.didFinishLaunchingWithOptions`. They work fine with the adaptor pattern.
- **Future cleanup:** Refactor `PushController`/`ScanViewModel` to route through `onOpenURL` by opening real `flipcash://` URLs, eliminating the NotificationCenter hop entirely.

### Step 5 — Appearance setup

`setupAppearance()` can stay in `didFinishLaunchingWithOptions` — the adaptor runs it before SwiftUI renders. No change needed.

### Step 6 — UINavigationController extension

The `viewWillLayoutSubviews` override for hiding back buttons (gated to iOS ≤ 18) is independent of lifecycle model. Keep as-is; remove when minimum deployment reaches iOS 26.

## What Must Stay in AppDelegate

- `didFinishLaunchingWithOptions` — bootstrap + NotificationCenter observers
- `didRegisterForRemoteNotificationsWithDeviceToken` — no SwiftUI API
- `didFailToRegisterForRemoteNotificationsWithError`

## Risks

- `ScenePhase` does not distinguish between `willEnterForeground` and `didBecomeActive`. Currently only `willEnterForeground` is used — verify that `.active` fires at the right time for gRPC channel warmup.
- UI testing setup (`--ui-testing` flag, `setAnimationsEnabled(false)`) — confirm it still works when the window is SwiftUI-managed.
