# IPA size analysis (App Store Connect flagged the build as too large)

Measured from local unsigned `Release` archives of `main` @ 9892d63f3
(`xcodebuild archive -scheme Flipcash -configuration Release -destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO`).
Xcode Cloud builds the shipping archive; its numbers were not checked.

## Which 200 MB

The upload cap is 4 GB. 200 MB is the cellular-download threshold on the thinned **download size**
(App Store Connect → build → App Store File Sizes). Download size ≈ Mach-O bytes (FairPlay-encrypted,
so they barely compress) + compressed resources. The `Symbols/` folder in an upload IPA never ships,
so dropping symbol upload does not help.

## Root cause: every extension statically linked the whole stack

All local SPM products were `automatic` (static), and each appex links `FlipcashCore`, which pulls
gRPC, SwiftNIO, BoringSSL and the static `SharedCore` KMP archive.

| Binary | Before |
|---|---|
| Flipcash | 48.2 MB |
| ShareExtension.appex | 35.3 MB |
| NotificationContent.appex | 34.8 MB |
| NotificationService.appex | 31.3 MB |

## Fix (branch `fix/ipa-size-dynamic-frameworks`)

- `FlipcashCore` product → `type: .dynamic`, targets `["FlipcashCore", "FlipcashStore"]`; separate
  `FlipcashStore` product removed. A second dynamic product fails: its target depends on the
  `FlipcashCore` *target*, and Xcode errors "linked as a static library by … cannot be built
  dynamically because there is a package product with the same name".
- `FlipcashUI` product → `.dynamic`; its direct `SharedCoreKit` edge dropped (FlipcashCore
  `@_exported import`s it), so SharedCore is linked once.
- `Code.xcodeproj`: FlipcashStore product links removed from app + 3 appex; new "Embed Frameworks"
  phase on the app target for FlipcashCore + FlipcashUI (Xcode does not embed them on its own);
  FlipcashTests links FlipcashCore, FlipcashUI, SQLite, BigDecimal, Kingfisher, because it used to
  resolve ~2,000 symbols against the static host app binary.

## Results

| Measure | Before | After |
|---|---|---|
| Mach-O total | 160.8 MB | 69.6 MB |
| `Flipcash.app` on disk | 247 MB | 156 MB |
| dSYMs | 592 MB | 220 MB |
| Estimated download size (Mach-O + zipped resources) | ~225 MB | ~134 MB |

Checks run: archive builds, warnings 76 → 74; GRPC/NIO symbols only in `FlipcashCore.framework`;
no `PlugIns/*.appex/Frameworks`; every `@rpath` load of app, appexes and embedded frameworks resolves
inside the bundle; FlipcashTests suites ContactSyncController, Regression_sell_max_precision,
GroupChangeDialog, StoredProfile pass; Debug app launches on a simulator.

Not checked: the extensions at runtime (simulator push refused: notifications not authorized on a
logged-out install), a signed device/TestFlight build, `AllTargets`.

## Step 2: ship the package resource bundles once

The appexes each carried `FlipcashUI_FlipcashUI.bundle` (17.8 MB) and/or `FlipcashCore_FlipcashCore.bundle`
(6.5 MB). The generated `Bundle.module` only looks in the appex and next to the framework, never in
the containing app.

- `Scripts/strip-appex-package-resources.sh`, run as the last phase of all three appex targets,
  deletes both bundles before signing. `ENABLE_USER_SCRIPT_SANDBOXING = NO` on those targets: the
  sandbox refuses the delete ("Operation not permitted"), and declaring the bundles as outputs would
  collide with Xcode's own copy task. The appexes had no other script phases.
- `Bundle.packageResources(named:fallback:)` (FlipcashCore) returns the app's copy when
  `Bundle.main` is an `.appex`, else `fallback`. `Bundle.flipcashCore` / `Bundle.flipcashUI` replace
  every `Bundle.module` call site (pricing tables, emoji catalog, fonts, asset images).

| Measure | After step 1 | After step 2 |
|---|---|---|
| `Flipcash.app` on disk | 156 MB | 104 MB |
| Mach-O | 73 MB | 73 MB |
| Resources zipped | 67 MB | 25 MB |
| Estimated download size | ~140 MB | ~98 MB |

Checks: Release archive builds, unique warning set unchanged; appexes are 0.6–1.1 MB with no
Flipcash bundles; Regression_sell_max_precision + CurrencyInfoScreenTests pass (12, pricing tables);
Debug build on sim 53881C41 opens the share extension from Safari, which draws its sign-in screen in
Avenir with no crash (no bundle of its own, so fonts came from the app's copy).
Not checked: a real device, where the extension's sandbox reading the app bundle should be confirmed.

## Further headroom (not done)

`FlipcashUI` `Assets.car` keeps vector data in every device slice: `waves` 3.8 MB, `hexagons` 0.3 MB,
`rs`, `grid`, `globe` ~0.3 MB each. Turning off "Preserve Vector Data" on the large backgrounds
would save ~4–5 MB if they never render above their rasterized size.
