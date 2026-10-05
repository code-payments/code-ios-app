---
name: verify
description: Build, install, and drive Flipcash on the iPhone 17 simulator to observe a change at its real surface — login deeplink, loupe driving, and chat/send flow routes included.
---

# Verifying Flipcash changes on the simulator

Done when the changed surface has been driven on the simulator and captured in a screenshot.
Report expected vs. observed, and if they differ, which step.

## Build + install + launch

```bash
# Sim build reuses the worktree's own DerivedData (warm after any test.sh run).
set -o pipefail
xcodebuild -project Code.xcodeproj -scheme Flipcash \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | xcsift -f toon

# Locate the .app by BUILD_DIR (never newest-mtime — other worktrees' DerivedData collides):
xcodebuild -project Code.xcodeproj -showBuildSettings -scheme Flipcash | grep -m1 BUILD_DIR
# → $BUILD_DIR/Debug-iphonesimulator/Flipcash.app; confirm CFBundleIdentifier == com.flipcash.app.ios

xcrun simctl install <udid> "<...>/Flipcash.app"
xcrun simctl launch  <udid> com.flipcash.app.ios
```

`xcodebuild test` leaves an incomplete `.app` (no Info.plist) — always run a `build` action first.

## Login

Test-account login is a deeplink; the key lives in the gitignored
`Configurations/secrets.local.xcconfig`. Untracked files don't propagate into worktrees, so
from a worktree read it out of the **main checkout's** `Configurations/` directory:

```bash
KEY=$(grep '^FLIPCASH_UI_TEST_ACCESS_KEY' <main-checkout>/Configurations/secrets.local.xcconfig | cut -d= -f2 | tr -d ' ')
xcrun simctl openurl <udid> "flipcash://login#e=$KEY"
```

The account has balances (USDF + launchpad currencies) and a "Raul Riera" contact with an
existing DM conversation. Small sends ($0.01) are the established probe amount.

## Driving the UI

Drive the simulator through loupe (`~/dev/loupe`, "Agent API" in its README), not the Claude
iOS Sim panel, XcodeBuildMCP, or `axe`. It serves HTTPS on `:18456` with a bearer token, and
every call takes `?target=sim:<udid>`:

```bash
T=$(cat ~/Library/Caches/loupe/token)
L() { curl -sk -H "Authorization: Bearer $T" -H 'Content-Type: application/json' "$@"; }
U="https://localhost:18456"; TGT="target=sim:<udid>"

L "$U/api/ui?interactive=1&$TGT"                     # accessibility tree; each node has `center`
L "$U/api/input?$TGT" -d '{"action":"tap","x":603,"y":525}'
L "$U/api/input?$TGT" -d '{"action":"text","text":"hello"}'
L "$U/api/screenshot?$TGT" -o shot.png               # PNG at device resolution
```

- **Coordinates are device pixels**, the same space `/api/ui` reports, so tap a node's
  `center` as-is. iPhone 17 is 1206×2622 px (402×874 pt @3x).
- Prefer the tree's `center` over reading positions off a screenshot. Fallback pixels for
  the Send flow: Send tab (756, 2370) on the scan screen; first conversation row (603, 525);
  in-sheet back chevron (117, 300); keypad "." (201, 2118), "0" (603, 2118), "1" (201, 1326);
  Send Cash button (318, 2403) in a conversation.
- **Swipe to Send** is a drag, not a tap:
  `{"action":"swipe","x":156,"y":2370,"x2":1110,"y2":2370,"ms":600}`
- A `409` with `code: "hubHeld"` means Xcode's Device Hub took the simulator's input; send
  `{"action":"reclaim"}` (restarts SpringBoard, ~9s). If taps answer `{"ok":true}` but the
  screen doesn't change and `reclaim` reports `no frontmost application`, CoreSimulator is
  wedged — see the `unwedging-ios-simulator` skill rather than retrying.

## Flows worth driving

- **Send list previews:** Send tab → row subtitles are `conversation.lastMessage`. In-chat
  Send Cash ($0.01) → back → the row must show "You sent $0.01 of <currency>" in-session.
- **Cold-start parity:** `simctl terminate` + relaunch → hydrate from SQLite must show the
  same previews as the live session did.
