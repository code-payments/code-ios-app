# Technology Stack, Setup & Tooling

## Getting Started

Open `Code.xcodeproj` in Xcode 16.x. Swift packages resolve automatically on first open. Build and run the `Flipcash` scheme.

## Protos: consumed, not generated here

This repo no longer vendors `.proto` files or runs protoc. The generated Swift ships from two
published packages, and `FlipcashAPI` is a thin umbrella that `@_exported import`s both so
`import FlipcashAPI` keeps working:

| Module | Package | Contract |
|---|---|---|
| `OCPClientProtocol` | [`ocp-client-protocol`](https://github.com/code-payments/ocp-client-protocol) | `ocp-protobuf-api` |
| `Flipcash2ClientProtocol` | [`flipcash2-client-protocol`](https://github.com/code-payments/flipcash2-client-protocol) | `flipcash2-protobuf-api` |

Android consumes the Kotlin half of the same two packages, so both apps now generate from one
place instead of each vendoring the contract.

**To pick up a contract change:** sync and release it in the client-protocol repo (its README has
the steps), then bump the `exact:` version in `FlipcashAPI/Package.swift`. Nothing in this repo
needs protoc, swift-protobuf, or the grpc-swift plugin installed.

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
FlipcashAPI/       # umbrella over the two published contract packages
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
