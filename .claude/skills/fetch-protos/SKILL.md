---
name: fetch-protos
description: >
  Fetch latest protobuf definitions, regenerate Swift bindings, verify the build,
  summarize API changes, and scaffold new service stubs. Usage: /fetch-protos [core|payments] [both]
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

Pull `.proto` files from upstream, regenerate the Swift gRPC bindings under
`FlipcashAPI/Sources/FlipcashAPI/{Core,Payments}/Generated`, verify they compile,
summarize the API changes, and scaffold missing service-layer implementations.

## Pre-flight context

- Core protos: !`find FlipcashAPI/Sources/FlipcashAPI/Core/proto -name "*.proto" 2>/dev/null | wc -l | tr -d ' '`
- Payments protos: !`find FlipcashAPI/Sources/FlipcashAPI/Payments/proto -name "*.proto" 2>/dev/null | wc -l | tr -d ' '`
- Git status: !`git status --short FlipcashAPI/`

## Input

Parse `$ARGUMENTS` to determine which domain(s) to fetch.

**Rules:**
- Known targets: `core` (→ `flipcashCore`), `payments` (→ `flipcashPayments`)
- If no target specified, fetch **both**
- `both` explicitly fetches both
- Examples:
  - `/fetch-protos` → fetch core + payments
  - `/fetch-protos core` → fetch core only
  - `/fetch-protos payments` → fetch payments only

Target-to-repo mapping (handled by `Scripts/run`):

| Target | App flag | Upstream repo |
|--------|----------|---------------|
| `core` | `flipcashCore` | `code-payments/flipcash2-protobuf-api` |
| `payments` | `flipcashPayments` | `code-payments/ocp-protobuf-api` |

## Steps

### Step 1 — Pre-flight tool check

The script aborts if any generator is missing, but confirm first so the user can
install before anything destructive runs:

```bash
command -v protoc protoc-gen-swift protoc-gen-grpc-swift-2
```

If any are missing, install and stop:
- `protoc` → `brew install protobuf`
- `protoc-gen-swift` → `brew install swift-protobuf`
- `protoc-gen-grpc-swift-2` → `./Scripts/install-grpc-swift-2-plugin.sh`

### Step 2 — Fetch protos and regenerate

For each target, run from the repo root:

```bash
cd Scripts && ./run -a flipcashCore      # core
cd Scripts && ./run -a flipcashPayments  # payments
```

Each invocation clones the latest `.proto` files from upstream, replaces the local
`proto/` directory, copies `proto_deps/` back in, and regenerates the Swift bindings
in `Generated/`. It also drops `validate_validate.pb.swift` (unused client mirror)
and, for core, renames the messaging service files to avoid a basename collision with
the payments messaging service in the merged `FlipcashAPI` module. Show the output.

### Step 3 — Diff and summarize changes

The meaningful diff is the regenerated Swift, since `proto/` is wiped and re-cloned:

```bash
git diff --stat FlipcashAPI/Sources/FlipcashAPI/Core/Generated FlipcashAPI/Sources/FlipcashAPI/Payments/Generated
git diff FlipcashAPI/Sources/FlipcashAPI/*/proto
```

For each changed service, summarize:
- **New RPCs** added to services (new methods on a `*.Client`)
- **Modified RPCs** (changed request/response types or fields)
- **Removed RPCs**
- **New/modified messages, fields, and enum result cases**

Present a structured change summary. If nothing changed, report that protos are
already up to date and stop here.

### Step 4 — Build verification

Verify the regenerated code compiles before touching anything else:

```bash
./Scripts/build.sh
```

If the build fails, show errors and stop — a broken generation must be resolved
(usually a proto rename that orphaned a Swift type reference) before proceeding.

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
chore: sync <core|payments> protos
```

If service stubs were scaffolded, suggest a separate commit:

```
feat: scaffold <domain> service for new RPCs
```

## Never

- Edit generated files under `Generated/` directly — they are overwritten on the next regen. Update the wrapping `*Service.swift` instead.
- Give a streaming RPC a deadline (`.unaryDefault`). Streaming passes `.defaults`.
- Interpolate variables (especially base58/keys) into log message strings — variables go in `metadata`.
- Skip the build verification in Step 4.
- Scaffold service code without asking the user first.
- Commit without user approval.
