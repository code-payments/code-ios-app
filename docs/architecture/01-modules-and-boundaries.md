# Modules & Boundaries

The codebase is split into 5 SPM packages plus the app target and two app extensions (NotificationService, NotificationContent); a share helper is embedded in the app target rather than being its own target. The split enforces a strict, acyclic dependency layering: business logic never imports UI, UI never imports the network layer, and generated code is isolated behind one package.

## Module inventory

| Module | Type | Purpose |
|--------|------|---------|
| **CodeCurves** | SPM package | Ed25519 crypto — pure-C implementation (zero Swift; the `KeyPair` wrapper lives in FlipcashCore) |
| **CodeScanner** | SPM package | C++/OpenCV "Kik Code" circular-2D encode/decode/scan; bundles OpenCV 4.10 |
| **FlipcashAPI** | SPM package | **All** generated gRPC/protobuf Swift bindings (both backends), 100% generated |
| **FlipcashCore** | SPM package | Business logic, models, gRPC service wrappers, logging, validation, formatters — **no SwiftUI** |
| **FlipcashUI** | SPM package | Reusable SwiftUI/UIKit components + design tokens — **no networking/persistence** |
| **Flipcash** | Xcode app target | Screens, navigation, controllers (Database, Session, Rates…), 3rd-party SDKs |
| **NotificationService** | Xcode extension | `UNNotificationServiceExtension` — resolves contact names on-device, renders communication notifications, prefetches chat transcripts into the shared cache |
| **NotificationContent** | Xcode extension | `UNNotificationContentExtension` — expanded (long-press) chat push panel; lightweight SwiftUI transcript fed from the shared cache |
| **Flipcash/Share** | Files in app target | System share-sheet wrapper (`UIActivityViewController`) for cash links |
| **FlipcashTests** | Xcode test target | Unit/integration tests (Swift Testing) for app + Core |
| **FlipcashUITests** | Xcode test target | Black-box XCUITest smoke tests |

## Dependency graph

```mermaid
graph TD
    App["Flipcash app"] --> UI["FlipcashUI"]
    App --> Scanner["CodeScanner"]
    App --> SQLite["SQLite fork"]
    App --> SDKs["Firebase · Bugsnag · Mixpanel · Kingfisher · tweetnacl"]
    UI --> Core["FlipcashCore"]
    UI --> ChatLibs["ChatLayout · DifferenceKit"]
    Core --> API["FlipcashAPI"]
    Core --> Curves["CodeCurves"]
    Core --> Libs["BigDecimal · PhoneNumberKit · swift-log"]
    API --> gRPC["grpc-swift 2.x"]
    Core --> gRPC
    NSE["NotificationService extension"] --> Core
    NSE --> API
    NCE["NotificationContent extension"] --> Core
    NCE --> UI
```
*Arrows point to dependencies; the graph is acyclic.*

### Third-party dependencies (where they live)

| Dependency | Pin | Used by |
|------------|-----|---------|
| grpc-swift-2 | ≥2.4 (**v2**; resolved 2.4.1) | FlipcashAPI + FlipcashCore (`GRPCCore`) |
| grpc-swift-protobuf | ≥2.0 | FlipcashAPI (`GRPCProtobuf`) |
| grpc-swift-nio-transport (+ swift-nio) | ≥2.0 / ≥2.81 | FlipcashCore (`GRPCNIOTransportHTTP2` — Network.framework TransportServices) |
| swift-log | ≥1.6 | FlipcashCore |
| BigDecimal | ≥3.0.2 | FlipcashCore (quark/fiat math) |
| PhoneNumberKit | ≥4.1.4 | FlipcashCore |
| ChatLayout / DifferenceKit | ≥2.4.2 / ≥1.3.0 | FlipcashUI (chat transcript layout + diffing) |
| SQLite.swift (**dbart01 fork**, `master`) | — | app only |
| Firebase, Bugsnag, Mixpanel, Kingfisher, tweetnacl | various | app only |
| opencv2 (bundled XCFramework) | ~4.10 | CodeScanner only |

The observability/analytics SDKs (Firebase, Bugsnag, Mixpanel) are confined to the **app target** — they never leak into Core or UI.

## Boundary rules (enforced by convention)

- **`FlipcashAPI/**/Generated/` is never hand-edited.** Regenerate via `Scripts/run -a flipcashPayments` / `flipcashCore`. Edits are overwritten. Wrap generated stubs in hand-written service files instead.
- **FlipcashCore is SwiftUI-free** — zero `import SwiftUI`. Models, clients, logging, validation, formatting only. Anything UI-facing crosses into FlipcashUI or the app.
- **FlipcashUI has no business logic** — it imports FlipcashCore for *model types and formatters* only. No network calls, no session state, no persistence.
- **SQLite belongs to the app layer only** — `import SQLite` appears exclusively under `Flipcash/Core/Controllers/Database/` (plus its tests). Core has no SQLite dependency.
- **CodeScanner is used at exactly two call sites** (`CodeExtractor.swift`, `CashCode.Payload+Encoding.swift`); it never reaches Core or UI.
- **Directory placement**: screens → `Flipcash/Core/Screens/`; domain models → `FlipcashCore/.../Models/`; DB row models → `Flipcash/Core/Controllers/Database/Models/`; test support → `FlipcashTests/TestSupport/`.

## Embedded targets

- **NotificationService** — runs in a tight memory/time budget. Server pushes E.164 numbers + positional placeholders; the extension queries `CNContactStore` to resolve names, and renders "Sent You Cash" pushes as `INSendMessageIntent` communication notifications (sender avatar in the banner). For chat pushes it also prefetches the recent transcript over a transient gRPC connection into `NotificationPreviewCache` (App Group `group.com.flipcash.shared`). Imports FlipcashCore + FlipcashAPI only.
- **NotificationContent** — `UNNotificationContentExtension` behind the expanded (long-press) chat push. Renders a fixed-height, bottom-anchored SwiftUI bubble transcript (`NotificationTranscriptView`) — deliberately **not** the in-app `ChatViewController`, whose footprint exceeds the extension's memory budget and gets it jetsam-killed. Reads `NotificationPreviewCache` first; on a cache miss falls back to a live fetch over a transient connection. Imports FlipcashCore + FlipcashUI only.
- **Share** — `ShareCashLinkItem` (`UIActivityItemSource` providing a cash-link URL) + `ShareSheet` (an enum whose static `present(activityItem:completion:)` builds a `UIActivityViewController` and presents it on the root view controller). Embedded in the app target, not a separate bundle.

## Why this matters

The layering is the single biggest structural guarantee in the project: because Core can't import UI and the app can't reach into generated code, a change to a proto, a UI component, or a screen each has a bounded blast radius. Keep new code on the right layer — that's what keeps the graph acyclic.
