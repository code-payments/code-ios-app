# Technology Stack, Setup & Tooling

## Getting Started

Open `Code.xcodeproj` in Xcode 16.x. Swift packages resolve automatically on first open. Build and run the `Flipcash` scheme.

## Regenerating Protos

Swift gRPC bindings in `FlipcashAPI/Sources/FlipcashAPI/Payments/Generated` and `FlipcashAPI/Sources/FlipcashAPI/Core/Generated` are generated from `.proto` files pulled from the server-protobuf repos. To regenerate:

```
cd Scripts
./run -a flipcashPayments
./run -a flipcashCore
```

Each invocation clones the latest `.proto` files from the upstream repo, replaces the local `proto/` directory, and regenerates the Swift code in `Generated/`.

**Required tools** (checked by the script; aborts if missing):
- `protoc` — `brew install protobuf`
- `protoc-gen-swift` — `brew install swift-protobuf`
- `protoc-gen-grpc-swift-2` (grpc-swift **2.x**) — `./Scripts/install-grpc-swift-2-plugin.sh`

**Never modify files under `Generated/` directly** — changes will be overwritten on the next regen.

## Required Technologies

| Technology | Version/Notes |
|------------|---------------|
| Swift | 6.0 (language mode); Xcode toolchain 16.x |
| iOS Minimum | 18.0 |
| UI Framework | SwiftUI (primary), UIKit (AppDelegate, navigation) |
| Testing | Swift Testing (`import Testing`) |
| Database | SQLite via SQLite.swift (fork, see below) |
| Networking | gRPC via grpc-swift 2 (GRPCCore + Network.framework TransportServices) |
| Crypto | Ed25519 via CodeCurves |

## Package Structure

```
Flipcash/          # Main app - focus here
FlipcashCore/      # Business logic, models, clients
FlipcashUI/        # UI components, theme
FlipcashAPI/       # gRPC proto definitions + generated v2 bindings (Payments/ + Core/)
CodeCurves/        # Ed25519 cryptography
CodeScanner/       # C++/OpenCV circular code scanning (see below)
```

## SQLite.swift Fork

**We use a fork of SQLite.swift** (`dbart01/SQLite.swift`), not the official `stephencelis/SQLite.swift`. The fork is pinned to `master` branch and adds two changes on top of the official `0.15.4` base:

1. **Upsert WHERE clause fix** — moves `whereClause` after `DO UPDATE SET` (the official repo places it before `ON CONFLICT`, producing invalid SQL for filtered upserts like `table.filter(...).upsert(...)`)
2. **Custom dispatch queue injection** — adds a `queue:` parameter to `Connection.init` so callers can supply their own `DispatchQueue`
3. **Public `Setter` access (pending)** — `Setter.column` and `Setter(excluded:)` need to be made `public` so callers can build custom ON CONFLICT SET clauses (e.g., `COALESCE(excluded.column, column)` for conditional upserts). See `Database+Balance.swift` TODO.

**Do not switch to the official repo** without verifying:
- Filtered upserts still generate valid SQL
- `Connection.init(queue:)` is no longer needed
- Custom SET clause building still compiles

## CodeScanner Project

C++ library for encoding, decoding, and scanning custom circular 2D codes ("Kik Codes"). Uses OpenCV 4.10.0 and a bundled ZXing Reed-Solomon subset.

- **Location:** `CodeScanner/`
- **Public API:** `CodeScanner/CodeScanner/Code.h` (`KikCodes` class — encode, decode, scan)
- **Used by:** `CodeExtractor.swift`, `CashCode.Payload+Encoding.swift`
- **Full spec:** `.claude/spec.md` (API details, build docs, OpenCV upgrade history)
- **Updating OpenCV:** `cd CodeScanner && ./Scripts/build_opencv.sh --version <version>`

## Orphaned DerivedData Pruning

Every git worktree builds into its own `~/Library/Developer/Xcode/DerivedData/<Name>-<hash>`
folder (Xcode keys on the checkout's path), and `git worktree remove` does **not** delete it.
These orphans accumulate silently and can reach tens of GB across a handful of worktrees.

- **Manual:** `Scripts/prune-orphan-deriveddata` (`--dry-run` to preview). It deletes only folders
  whose recorded `WorkspacePath` no longer exists on disk, so live checkouts and Xcode's shared
  caches are never touched. DerivedData is a pure cache — anything pruned is rebuilt on next build.
- **Automatic:** wire it to a Claude Code hook (`PostToolUse` filtered to `git worktree remove`,
  plus `WorktreeRemove`) in your gitignored `.claude/settings.local.json` so it runs on every
  worktree removal. The exact hook block is in the script's header comment.
