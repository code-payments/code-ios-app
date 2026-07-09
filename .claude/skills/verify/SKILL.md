---
name: verify
description: Build, install, and drive Flipcash on the iPhone 17 simulator to observe a change at its real surface — login deeplink, coordinate-scale gotchas, and chat/send flow routes included.
---

# Verifying Flipcash changes on the simulator

## Build + install + launch

```bash
# Sim build reuses the worktree's own DerivedData (warm after any test.sh run).
xcodebuild -project Code.xcodeproj -scheme Flipcash \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build

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

- XcodeBuildMCP `snapshot_ui`/`tap` return **no targets** for this app and `axe describe-ui`
  returns an empty AX tree — drive by coordinates with `axe tap/swipe` instead.
- **Coordinate scale:** MCP `screenshot` images are 368×800; the device is 402×874 pt
  (iPhone 17 @3x = 1206×2622 px). Multiply screenshot coords by **×1.0924** to get points.
- Useful points (Send flow): Send tab (252, 790) on the scan screen; first conversation row
  (201, 175); in-sheet back chevron (39, 100); keypad "." (67, 706), "0" (201, 706),
  "1" (67, 442); Send Cash button (106, 801) in a conversation.
- **Swipe to Send** is a drag, not a tap:
  `axe swipe --start-x 52 --start-y 790 --end-x 370 --end-y 790 --duration 0.6 --udid <udid>`

## Flows worth driving

- **Send list previews:** Send tab → row subtitles are `conversation.lastMessage`. In-chat
  Send Cash ($0.01) → back → the row must show "You sent $0.01 of <currency>" in-session.
- **Cold-start parity:** `simctl terminate` + relaunch → hydrate from SQLite must show the
  same previews as the live session did.
