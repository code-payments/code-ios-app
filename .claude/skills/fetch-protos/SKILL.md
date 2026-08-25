---
name: fetch-protos
description: >
  Bump the published contract packages, verify the build, summarize API changes,
  and scaffold new service stubs. Usage: /fetch-protos [core|payments] [both]
argument-hint: "[core|payments] (default: both)"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Glob
  - Grep
  - Agent
---

# Fetch Protos

Move the app onto newer contract packages, verify they compile, summarize the API changes,
and scaffold missing service-layer implementations.

This repo does not generate protos. `FlipcashAPI` is an umbrella that re-exports two published
packages, and picking up a contract change means bumping their versions — the generation itself
happens in the package repos.

## Pre-flight context

- Pinned versions: !`grep -E 'client-protocol' FlipcashAPI/Package.swift`
- Local override: !`echo "${FLIPCASH_PROTO_LOCAL:-none — building against the pins above}"`
- Git status: !`git status --short FlipcashAPI/ Code.xcodeproj/`

## Input

Parse `$ARGUMENTS` to determine which domain(s) to bump.

**Rules:**
- Known targets: `core` (→ flipcash2), `payments` (→ ocp)
- If no target specified, bump **both**
- `both` explicitly bumps both
- Examples:
  - `/fetch-protos` → bump core + payments
  - `/fetch-protos core` → bump core only
  - `/fetch-protos payments` → bump payments only

| Target | Swift module | Package | Upstream contract |
|--------|--------------|---------|-------------------|
| `core` | `Flipcash2ClientProtocol` | `code-payments/flipcash2-client-protocol` | `code-payments/flipcash2-protobuf-api` |
| `payments` | `OCPClientProtocol` | `code-payments/ocp-client-protocol` | `code-payments/ocp-protobuf-api` |

## Steps

### Step 1 — Find the release to move to

```bash
gh release list --repo code-payments/ocp-client-protocol --limit 5
gh release list --repo code-payments/flipcash2-client-protocol --limit 5
```

If the contract change you want is not released yet, do not reach for a release. Publishing is
for CI release builds, and it is human-gated — never start it from here. Build against the client
checkouts instead:

```bash
export FLIPCASH_PROTO_LOCAL=~/dev/bmcreations/code
xed .
```

`FlipcashAPI/Package.swift` swaps both `.package(url:, exact:)` requirements for `.package(path:)`
when that variable names a directory holding `ocp-client-protocol/` and `flipcash2-client-protocol/`.
Xcode inherits the environment of whatever launched it, so it has to be started from the shell that
exported the variable — if Xcode was already open, relaunch it. Nothing tracked is edited to enter
this mode.

Producing the unreleased change — editing a `.proto` and syncing it into the client repo — happens in
the client repo; the orchestrator's `/contract-change` skill drives both halves. In this mode skip
Step 2 and Step 3: there is no pin to bump, and the diff is whatever is in your checkout.

Android pins the same two packages in its `gradle/libs.versions.toml`. The versions are not
required to match across platforms, but a contract change that matters to both should land on
both — flag it if only one side is moving.

### Step 2 — Bump the pin

Edit the `exact:` requirement in `FlipcashAPI/Package.swift` for each target, then resolve:

```bash
xcodebuild -resolvePackageDependencies -project Code.xcodeproj -scheme Flipcash
```

Show the resulting `Package.resolved` diff — it should change only the bumped package's
`version` and `revision`.

If `FLIPCASH_PROTO_LOCAL` is set, resolving instead **drops** both contract entries from
`Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, because path
dependencies are not recorded there. That is noise rather than a version change — the pins are
`exact` — but restore the file before committing:

```bash
git checkout -- Code.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

### Step 3 — Diff and summarize changes

The packages ship their generated Swift committed, so the API diff is readable directly:

```bash
gh api repos/code-payments/<package>/compare/<old-tag>...<new-tag> --jq '.files[].filename'
```

For each changed service, summarize:
- **New RPCs** added to services (new methods on a `*.Client`)
- **Modified RPCs** (changed request/response types or fields)
- **Removed RPCs**
- **New/modified messages, fields, and enum result cases**

Present a structured change summary. If nothing changed, report that the app is already on the
latest release and stop here.

### Step 4 — Build verification

Verify the app compiles against the new packages before touching anything else:

```bash
./Scripts/build.sh
```

If the build fails, show errors and stop — a broken bump must be resolved (usually a proto
rename that orphaned a Swift type reference) before proceeding.

### Step 5 — Trace service-layer impact

Dispatch the **proto-change-tracer** agent to map the changes through the codebase:

```
Use the proto-change-tracer agent to trace the proto changes just fetched
(see `git diff FlipcashAPI/`) through the service → client → consumer chain.
```

The agent reports the full impact chain (generated → `*Service.swift` →
`FlipClient/Client` extension → Session/Controllers/ViewModels → tests) and a
prioritized checklist. Present its report. New enum result cases and new RPCs are the
common gaps — a proto result enum that gained a case will fall through to `.unknown`
in the existing `Error*(rawValue:)` mapping until a case is added.

### Step 6 — Scaffold new service stubs

For RPCs the tracer marked as needing scaffolding, ask the user before generating.
Follow the existing iOS layering — there is **no** Repository/Controller/DI layer here;
the chain is Service → Client extension → consumer.

#### Service pattern

Location: `FlipcashCore/Sources/FlipcashCore/Clients/{Flip API,Payments API}/Services/<Domain>Service.swift`

```swift
private let logger = Logger(label: "flipcash.<domain>-service")

final class <Domain>Service: Sendable {

    private let service: Flipcash_<Domain>_V1_<ServiceName>.Client<AppTransport>

    init(client: GRPCClient<AppTransport>) {
        self.service = Flipcash_<Domain>_V1_<ServiceName>.Client(wrapping: client)
    }

    func newRpc(/* args */, owner: KeyPair, completion: @Sendable @escaping (Result<Output, ErrorNewRpc>) -> Void) {
        logger.info("Performing new RPC")

        let request = Flipcash_<Domain>_V1_NewRpcRequest.with {
            // set fields
            $0.auth = owner.authFor(message: $0)   // Flip API; Payments uses signature helpers
        }

        Task {
            do {
                let response = try await service.newRpc(request, options: .unaryDefault)  // streaming: pass .defaults
                let error = ErrorNewRpc(rawValue: response.result.rawValue) ?? .unknown
                guard error == .ok else {
                    logger.error("New RPC failed", metadata: ["error": "\(error)"])
                    await MainActor.run { completion(.failure(error)) }
                    return
                }
                await MainActor.run { completion(.success(/* mapped */)) }
            } catch let error as RPCError {
                await MainActor.run { completion(.failure(.from(transportError: error))) }
            } catch {
                await MainActor.run { completion(.failure(.unknown)) }
            }
        }
    }
}
```

Conventions (verify against a neighboring service in the same folder):
- **Unary** RPCs pass `options: .unaryDefault`; **streaming** RPCs pass nothing (`.defaults`) — a stray deadline silently kills long-lived streams.
- Message strings are constants; every variable goes in `metadata` (see CLAUDE.md logging rule). Never log a whole proto blob.
- Hand results back on `MainActor` via `completion`.

#### Error enum pattern

Defined at the bottom of the same `*Service.swift` file, mapping the proto result
enum's `rawValue`. Conform it to `TransportClassifiableError` so the compiler forces
you to classify the four transport cases and every result case's `reportingLevel`:

```swift
enum ErrorNewRpc: Int, Error, TransportClassifiableError {
    case ok
    case denied
    // ... one case per proto result enum value, in rawValue order ...
    case transportFailure
    case cancelled
    case rejected
    case unknown

    var reportingLevel: ErrorReportingLevel {
        switch self {
        case .ok, .denied:            return .info        // expected business outcome
        case .transportFailure:       return .suppressed  // network weather — never Bugsnag
        case .cancelled:              return .info        // app-initiated teardown
        case .rejected, .unknown:     return .error       // client/proto defect
        }
    }
}
```

Match the case ordering to the proto's result enum exactly — `Error*(rawValue:)`
depends on it. See `EmailService.swift` for the canonical shape and the
`FlipcashCoreTests/TransportClassificationTests` registry line every new conformer needs.

#### Async client wrapper

Location: `FlipcashCore/Sources/FlipcashCore/Clients/{Flip API,Payments API}/{FlipClient,Client}+<Domain>.swift`

```swift
extension FlipClient {  // or Client, for Payments
    public func newRpc(/* args */, owner: KeyPair) async throws -> Output {
        try await withCheckedThrowingContinuation { c in
            <domain>Service.newRpc(/* args */, owner: owner) { c.resume(with: $0) }
        }
    }
}
```

### Step 7 — Review and commit

Show the user a summary of all changes (proto/generated updates + any scaffolded
service code). Offer to commit only after approval, with a conventional message:

```
chore: bump <core|payments> client-protocol to <version>
```

If service stubs were scaffolded, suggest a separate commit:

```
feat: scaffold <domain> service for new RPCs
```

## Never

- Cut a release of a client package just to try a change. Use the local override; release when the
  change is settled and a build you do not control needs it.
- Commit a `Package.resolved` that lost its contract entries — that is the local override leaking,
  not a dependency change.
- Leave `FLIPCASH_PROTO_LOCAL` exported once you are done. A later Xcode launched from that shell
  quietly builds someone's working tree instead of the pinned release.
- Patch generated code locally to work around a contract problem. It lives in the package repos; fix it there and cut a release. Update the wrapping `*Service.swift` instead when the gap is app-side.
- Give a streaming RPC a deadline (`.unaryDefault`). Streaming passes `.defaults`.
- Interpolate variables (especially base58/keys) into log message strings — variables go in `metadata`.
- Skip the build verification in Step 4.
- Scaffold service code without asking the user first.
- Commit without user approval.
