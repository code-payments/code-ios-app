# Group moderation: silencing and removing members

Status: decided, not started
Platforms: Android (`code-android-app`, base `code/cash`), iOS (`code-ios-app`, base `main`)
Contract: flipcash2 0.21.0, which both apps already pin: `SilenceUser`, `UnsilenceUser`,
`BanUser`, `UnbanUser`, `GetRestrictedUsers` on `chat.v1.Chat`, and
`ViewerState.permissions.moderation` / `ViewerState.restrictions.silence`. No contract change.
Design: Figma page node 12419:77643, concepts sections 12766:63 (iOS, C1–C8b) and 12782:224 (Android, AC1–AC8b). Exploration and the
Telegram comparison: `docs/superpowers/specs/2026-10-27-group-moderation-design.md`.

A group's host can't stop one member from posting or put them out of the group. This spec adds
two host actions, Silence and Remove from Group, the screens where the host undoes them, and what
the silenced or removed person sees. Both apps already wrap all five RPCs (Android #1840, iOS
#1125), and nothing in either app calls them.

The contract is the spec for validity. Read the comments on `SilenceUser` through
`GetRestrictedUsers` in `proto/chat/v1/chat_service.proto`, and on `ViewerState`,
`ModerationPermissions`, `Restrictions`, `SilenceState`, `BanState` and `RestrictedUser` in
`proto/chat/v1/model.proto`. This document does not restate them.

Design values (spacing, type, color) are a guide. Each app's existing tokens win; list differences
in the PR rather than copying hard-coded values. On Android, every spacing, padding and gap comes
from the app's grid spacing tokens; no literal `dp` values for spacing.

## Decisions

| Question | Answer |
|---|---|
| Name of the per-member action | **Silence**. "Mute" stays the notification setting (`MuteChat`), so it keeps one meaning. |
| Remove vs ban | One action, "Remove from Group", calling `BanUser`. The contract has no kick-without-ban, so the confirm says they can't rejoin. |
| Who sees the actions | Silence when `moderation.can_silence`; Remove when `moderation.can_ban`; the Moderation row when either. Never on the group's creator (`Metadata.creator`) or the viewer's own messages and profile. Today only the creator holds these, but the client reads the flags and never checks "is creator". |
| Silence confirm | None. Picking a duration applies it, as Mute Notifications does. Picking again replaces the duration (the contract allows it). |
| Remove confirm | Always, with the bottom-bar alert both apps use for Block. |
| Silenced member's composer | Replaced by the read-only gate pill with a silence sentence, driven by `restrictions.silence`, not by a failed send. |
| Removed member | Learns why only when they try to come back: `JoinChat` or `EnterLobby` returns `BANNED`, and the app says "The host removed you from <group>". |
| Host's lists | One host-only **Moderation** row in the group overflow menu, opening a submenu with **Silenced** and **Removed**. Each opens its own list with one action per row. |
| Feature flag | None on either platform. The server's permission flags gate everything. |

## Host: Silence and Remove

### C1. Long-press a member's message (node 12766:64)

Two actions after Report: **Silence <first name>…** and **Remove <first name>…**, both destructive
(red). Shown under the rules in Decisions.

- iOS: two new `MessageCapability` cases, appended to the fixed render order in
  `ChatItem+Conversation.swift` after `.report`, granted in `MessageCapability.resolve`, handled in
  `ConversationScreen.handleMessageAction`.
- Android: a long-press puts `ChatTopBar` into selection mode. Add two `MessageCapability` entries
  and two `MessageAction`s after Report in the `ChatTopBar` builder. They always go in the
  `MessageOverflow` dropdown, never inline, whatever `inlineActionCapacity` allows.

Silence opens C3 for that sender. Remove opens C4.

### C2. Member profile opened from a group (node 12766:139)

The profile overflow menu gains a section titled **In <group name>** with **Silence…** and
**Remove from Group**, after Mute Notifications, Report and Block. Block stays and stays global.
The section only appears when the profile was opened from a group.

The profile needs to know which group:
- iOS: `UserProfileOrigin.groupMember` has no associated value. Change it to
  `.groupMember(ConversationID)` and pass the ID from `GroupMembersScreen` and the three
  `ConversationScreen` call sites. Update its four `switch` statements.
- Android: the profile runs inside the chat flow, so the group is the flow's chat. Gate on that
  chat being a group, not on `ProfileOrigin`: the members list passes `GroupMember`, but an avatar
  tap in a group transcript passes `Chat`. `profileMenuItems(isBlocked, hasDm)` gains the group's
  viewer state and creator, and `ChatProfileAction` gains `Silence` and `Remove`.

### C3. Silence duration sheet (node 12766:201)

Same layout as Mute Notifications: title "Silence <first name>", subtitle "They can still read and
react in <group>, but can't send messages. Only they're told", rows 1 Hour, 8 Hours, 1 Week,
Forever. Both apps say Forever, including Android, whose Mute Notifications sheet says Always.
Picking calls
`SilenceUser` with `SilenceState.until` (now + duration) or `forever` and dismisses.

- iOS: `MuteChatSheet` is hard-wired to mute (conversation ID, copy, analytics, the unmute row).
  Extract the row list into a shared view and build a `SilenceUserSheet` beside it that takes the
  chat ID and user ID.
- Android: `MuteChatSheet` loops `MuteOption.entries`. Pass the options and labels in as
  parameters, add a `SilenceOption` enum with the same durations, and give it its own route
  (`AppRoute.Messaging.SilenceUser(chatId, userId)`, presented like `MuteChat`).

The labels are new strings; the mute ones say "mute".

### C4. Remove confirm (node 12766:238)

Title "Remove <first name>?", subtitle "They'll leave <group> and can't rejoin until you unban
them. Their messages stay in the chat", actions **Remove** (destructive) and Cancel.

- iOS: `DialogItem.alert`, the same call as `UserProfileScreen.blockDialog()`.
- Android: `BottomBarManager.showAlert(title, message, actions, showCancel = true)`, as
  `ChatProfileViewModel` does for Block.

On success, nothing else to do: the roster drops them through the `RosterUpdate.MemberLeft` the
other members already receive.

### Results

| Result | What the host sees |
|---|---|
| `OK` | Nothing beyond the sheet or dialog closing. |
| `CANNOT_RESTRICT_CREATOR` | Can't happen if the actions are hidden correctly. Show the generic error. |
| `DENIED` | The host lost the permission between render and tap. Show the generic error and re-read viewer state. |
| `NOT_FOUND` | The chat is gone. Generic error. |

## Silenced member

### C5. Composer (node 12766:250)

When `restrictions.silence` is active, the composer is replaced by the read-only gate pill:
"You're silenced until <time>" for a timed silence (time only when today, otherwise date and
time), or "You're silenced in this group" for forever. Reactions and votes still work, and the
member can still delete their own messages.

A timed silence lapses with no event. Each app schedules a refresh at `until` and swaps the pill
back to the composer.

- iOS: `conversationGatePresentation` takes no viewer state. Apply silence as an override after it
  (an open or read-only gate becomes read-only with the silence sentence), using
  `ConversationViewerState.isSilenced(at:)`. The sentence goes beside `creatorSentence` in
  `ConversationGatePanel`.
- Android: `ChatViewModel` derives `isReadOnlySpeaker` from `speakerBlock`. Add a silence source
  that wins over it, and a silence branch in `SpeakerGateBar` with new strings next to
  `subtitle_chatGate_speakerCreatorOnly`.

If `SendMessage` returns `DENIED` anyway (the client missed the event), show the generic error and
re-read viewer state.

### Persistence

- iOS: `ConversationViewerState` is stored as one JSON blob, and #1125 already added `silence`,
  `canSilence` and `canBan` to it. Nothing to do.
- Android: `ChatMetadataDataSource` stores only mute, `canEdit` and version, and
  `ChatEntityMapper` rebuilds `ViewerState` without moderation or restrictions. Add columns for
  `canSilence`, `canBan` and the silence state, with a Room migration, or every cold start
  forgets them until the next `ViewerStateChanged`.

## Removed member

### C6. Trying to rejoin (node 12766:256)

`JoinChat` `BANNED` and `EnterLobby` `BANNED` show an alert: title "You Can't Join This Group",
subtitle "The host removed you from <group name>", one OK.

- iOS: `ConversationScreen.joinFailureSubtitle` handles only `rulesNotSatisfied`; add
  `ErrorJoinChat.banned`. `LobbyRequests.request(_:)` doesn't catch `ErrorEnterLobby.banned`;
  catch it and show the same alert.
- Android: the `JoinChat` failure `when` in `ChatViewModel` sends `JoinChatError.Banned` to the
  generic failure; add a case. Add the same to `showLobbyError` for `EnterLobbyError.Banned`, which the service already maps.

Before that, the removed member's chat simply leaves their list, the same as leaving.

## Host: Moderation lists

### C7a–C7b. Group overflow menu (nodes 12766:268, 12768:192)

A **Moderation** row, shown under the rules in Decisions, after Mute Notifications and before
the Report divider. It opens a submenu with **Silenced** and **Removed**.

- iOS: a nested `Menu` inside `ChatProfileScreen.overflowMenu`. SwiftUI draws it in place.
- Android: Material 3 has no submenu (checked in 1.4.0, which BOM 2026.09.00 ships, and in
  1.5.0-alpha22). Build one that matches iOS: tapping Moderation replaces the `DropdownMenu`'s
  items in place with a header row (back chevron and "Moderation") and the two entries, and the
  header row or system back returns to the first level. Put it in the shared UI module so other
  menus can use it.

### C8a–C8b. Silenced and Removed lists (nodes 12766:319, 12768:245)

Both lists come from one paged `GetRestrictedUsers` call, split on the client:

- **Silenced**: users with `silence` set and `ban` unset. Row: avatar, name, "Silenced · until
  <time>" or "Silenced · forever", trailing **Unsilence** button.
- **Removed**: users with `ban` set. Row: avatar, name, "Removed <date>", with " · also silenced"
  appended when `silence` is set, trailing **Unban** button.

Tapping a row's avatar or name opens the profile. The trailing button runs the RPC with a spinner
and removes the row on `OK`, with no confirm. The empty states aren't designed; use "No one is silenced" and "No one has been
removed" until they are.

The contract says the index trails writes briefly. Apply the viewer's own changes to the list
locally and don't refetch immediately after them.

- iOS: copy `JoinRequestsScreen` (avatar button plus trailing capsule buttons). New destinations
  after `groupMembers(ConversationID)` in `AppRouter+Destination.swift`.
  `FlipClient.getRestrictedUsers` pages to exhaustion already.
- Android: new `ChatStep` objects registered in `ChatFlowScreen`, following `JoinRequests` for
  per-row actions and `BlocklistScreenContent` for the list and its screenshot test.

## Test cases

- A host long-presses a member's message and sees Silence and Remove after Report. On the
  creator's own message, and on the viewer's own, neither appears.
- A member without `can_silence` or `can_ban` sees none of the actions or the Moderation row.
- Silence for 1 hour: the silenced account's composer turns into the pill within a few seconds,
  and back into the composer at the hour without reopening the chat.
- Silence Forever, then Silence 1 hour: the pill changes from "in this group" to "until <time>".
- A silenced member can still react and delete their own message.
- Kill and relaunch the silenced account's app while silenced: the pill is still there before any
  stream event (Android persistence).
- Remove: the confirm shows; on Remove the member disappears from the host's roster, and the
  chat leaves the removed account's list. Trying to rejoin shows C6. For a private group,
  requesting to join shows C6 too.
- Silenced and Removed lists show the right people. Unsilence and Unban take the row out at once.
  A user both silenced and removed appears only under Removed, marked "also silenced".
- After Unban the person can join again (public) or request again (private). They aren't
  rejoined automatically.

## Where it lands in each app

| Piece | Android | iOS |
|---|---|---|
| RPCs | `ChatController.silenceUser` / `unsilenceUser` / `banUser` / `unbanUser` / `getRestrictedUsers` | `FlipClient+Chat.swift` (same five) |
| Viewer state | `ViewerState` maps moderation and restrictions; Room drops them (see Persistence) | `ConversationViewerState`, persisted, with `isSilenced(at:)` |
| Long-press | `ChatTopBar` builder, `MessageCapability` | `MessageCapability`, `ChatItem+Conversation.swift`, `ConversationScreen.handleMessageAction` |
| Profile menu | `ProfileMenuItems.kt`, `ProfilePinnedAction.kt`, `ChatProfileViewModel` | `ProfileMenuItems.swift`, `UserProfileScreen`, `UserProfileOrigin` |
| Silence sheet | `MuteChatSheet.kt`, `MuteOption` | `MuteChatSheet.swift` |
| Composer | `ChatViewModel` `isReadOnlySpeaker`, `SpeakerGateBar` | `ConversationGate.swift`, `ConversationGatePanel` |
| Join failure | `ChatViewModel` join `when`, `showLobbyError` | `ConversationScreen.joinFailureSubtitle`, `LobbyRequests.request` |
| Group menu | `GroupProfileMenuItems.kt`, `GroupProfileScreen` | `ChatProfileScreen.overflowMenu` |
| Lists | new `ChatStep`s in `ChatFlowScreen` | new `Destination`s |

## Per-platform verification before a PR opens

Both:
- On two accounts in one public group and one private group, where the first is the creator:
  every test case above.
- Screenshots of C1–C8b on the device, attached to the PR next to the design frames.

Android: `./gradlew` unit tests for the touched modules, the Room migration test, and screenshot
tests for both lists and the nested menu.
iOS: the `FlipcashTests` target.

## Out of scope

- Roles or co-hosts. The client reads the permission flags, so a server-side role needs no client
  change to show the actions.
- Deleting another member's messages. `DeleteMessage` is sender-only.
- A transcript line when someone is removed. `SystemContent` has only `UserJoined`.
- Rotating a private group's key on removal. The contract doesn't rotate it.

## Open

- Should Unban offer to re-admit the person? `UnbanUser` doesn't rejoin them.
- Which pickers drop silenced and removed members? `group-send.md` and `group-requests.md` don't
  say whether a silenced member can be sent cash or asked to pay. A removed member is no longer
  on the roster, so they drop out already.
