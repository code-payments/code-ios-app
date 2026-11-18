# Group moderation (silence, remove, block) — cross-platform exploration

Status: exploration — design only, not scheduled
Platforms: iOS (`code-ios-app`), Android (`code-android-app`)
Also touches: (read only: both apps pin `flipcash2-client-protocol` 0.21.0 and wrap every RPC
  used here, Android in #1840 and iOS in #1125; no contract change)
Spec: `docs/specs/group-moderation.md`
Figma: file `Jxf2wD9QyfKaONbhHSdU0K`, page `(Brandon) Mute / Unmute Group Chat Participants [Oct 22]` (node `12419:77643`)
  Sections: real-app references `12758:56`, concepts `12766:63`, spec `12770:202`,
  components `12759:56`, Mobbin `12758:74`, decided against `12770:205`

A group host can't stop one member from posting or put them out of the group. The server can
do both: 0.21.0 added `SilenceUser`/`UnsilenceUser`, `BanUser`/`UnbanUser` and
`GetRestrictedUsers` to `chat.v1.Chat`. Android wraps them in `ChatController` (#1840), iOS in
`FlipClient+Chat` (#1125), and nothing on either platform calls them. This note maps Telegram's model onto that contract and
proposes where the actions live in the app.

## What other apps do

- **Telegram:** admins restrict a member per permission (send messages, media, links) for a
  set time or forever, and Remove puts them on a Removed Users list that admins manage from
  group settings. The transcript shows "X removed Y".
- **WhatsApp:** group permissions are group-wide toggles (who can send, who can edit info), not
  per member. Admins remove a member, who can be re-added.
- **Believe:** a holder gate on the composer explains why a member can't post.
- **Kraken:** blocking a contact explains what happens to payments from them.
- **Airtasker:** a blocked conversation replaces the composer with a one-line reason.

## Words

Flipcash already uses "Mute" for notifications: `MuteChat`, the Mute Notifications row in the
group and profile menus, and `MuteChatSheet`. Telegram makes the same split: notification
mute is per viewer, and restricting a member is a moderation action. The per-member action
here is **Silence**, the contract's word, so "Mute" keeps one meaning.

| Telegram | Flipcash contract | Shown as |
|---|---|---|
| Mute notifications | `MuteChat` / `ViewerState.Settings.mute` | Mute Notifications (shipped) |
| Restrict "send messages" | `SilenceUser`, `SilenceState` until or forever | Silence |
| Remove from group | none. `BanUser` is the only removal | Remove from Group |
| Ban | `BanUser` / `UnbanUser` | Remove from Group, Unban |
| Block | `BlockUser`, global blocklist | Block (shipped) |
| Admins and custom rights | `ModerationPermissions{can_silence, can_ban}`, creator only | not exposed |

Remove and ban are one action, because the contract has no kick-without-ban. The copy has to
say the person can't rejoin.

## What each side sees

| | Host | Silenced member | Removed member | Everyone else |
|---|---|---|---|---|
| Event | RPC result | `ViewerStateChanged` with `Restrictions.silence` | plain `RosterUpdate.MemberLeft` | `MemberLeft` for a removal, nothing for a silence |
| Composer | normal | gate pill, C5 | chat leaves the list | normal |
| Learns why | n/a | from the pill | from `JoinChat` `BANNED` or `EnterLobby` `BANNED`, C6 | never |
| Messages | stay | stay | stay | stay |

A timed silence ends with no event. The client starts a timer from `SilenceState.until` to swap
the pill back. `SendMessage` from a silenced member returns plain `DENIED`, so the pill has to
come from `ViewerState` and not from a failed send.

Block does not filter group transcripts. On iOS, the conversation rendering doesn't read the
blocklist. On Android, `Sender.isBlocked` is read only by the profile screen. The contract lists block's effects as `Metadata.is_hidden` on the DM plus
exclusion from `SampleChatters` and mention suggestions. A member who blocks someone in a group
still sees their messages there. The July Block page copy ("you won't see messages from them")
was written for a 1:1 chat, and reads as a promise in a group.

## Concepts

Each frame is built from layers, not a screenshot: an instance of a base screen (group
transcript, member profile, group profile) plus the change, using components already in the file.
The bases were drawn from captures of build 272 (2026.10.5), which stay in the reference rows.
The Android frames (AC1–AC8b, section `12782:224`) use the same bases at 412×915 with Android
chrome: the selection top bar, the Material dropdown, and the bottom-bar alert. In the captures,
the test account isn't the host of Jeffy | All Holders. The frames show it as the host.

| Frame | Node | What changes | Seam |
|---|---|---|---|
| C1 Long-press a member's message | `12766:64` | Silence Grampa… and Remove Grampa… after Report | `MessageCapability` gains two cases at the end of its fixed order |
| C2 Member profile menu | `12766:139` | An "In <group>" section with Silence… and Remove from Group | `ProfileMenuItems`, origin `.groupMember` |
| C3 Silence duration sheet | `12766:201` | `MuteChatSheet` layout: 1 Hour, 8 Hours, 1 Week, Forever | `SilenceState` is the same until-or-forever oneof as `MuteState` |
| C4 Remove confirm | `12766:238` | `DialogItem.alert`, destructive Remove plus Cancel | same call as `UserProfileScreen.blockDialog()` |
| C5 Silenced member's composer | `12766:250` | "You're silenced until 6:02 PM", or "You're silenced in this group" | a new sentence for `ConversationGatePanel.readOnlyPill` |
| C6 Removed member rejoins | `12766:256` | `DialogItem.alert`: "You Can't Join This Group", "The host removed you from <group>", OK | the `JoinChat` `BANNED` result |
| C7a Group overflow | `12766:268` | Host-only Moderation row, opening a submenu | `GroupProfileMenuItems` / `ChatProfileScreen` overflow |
| C7b Moderation submenu | `12768:192` | Silenced and Removed | iOS: a nested `Menu`, drawn in place. Android: Material 3 has no submenu, so a `DropdownMenu` that swaps its items in place |
| C8a Silenced list | `12766:319` | Silenced members, with Unsilence | `GetRestrictedUsers`, filtered to `silence` set and `ban` unset |
| C8b Removed list | `12768:245` | Removed members, with Unban | `GetRestrictedUsers`, filtered to `ban` set |

One Moderation entry keeps the group overflow menu short, since a member never sees it and a
host rarely opens it. The submenu splits the two lists so each row has a single action. A person
who is both silenced and removed appears only under Removed, and their row says so.

C6 names the host as the reason. The server already tells the client through a dedicated
`BANNED` result, so hiding the reason would protect nothing.

Every action is gated on `ViewerState.permissions.moderation` and hidden on the creator's own
row, since the server answers `CANNOT_RESTRICT_CREATOR`. A silence picked from C3 applies
immediately with no confirm, matching Mute Notifications. Remove always confirms.

## Not in the contract

These need a server change. The concepts avoid depending on them.

- **No system message.** `SystemContent` has only `UserJoined`, so the rest of the group sees
  someone disappear from the roster with no line in the transcript. Telegram shows "X removed Y".
- **No `SILENCED` send result.** A client that misses `ViewerStateChanged` shows a generic error.
- **No kick-without-ban.** "Remove" can't mean "leave, but you may come back".
- **No roles.** `Member.version` comments name roles as a future field. Until then, only the
  creator moderates, and only the creator can admit to a private group.
- **No moderator delete.** `DeleteMessage` is sender only. A host can remove a spammer but can't
  take down what they posted.
- **No rekey on removal.** A private group's chat key never changes, so a removed member keeps
  the key for anything already fetched. The server stops serving them new content.

## Open questions

- Should Unban also offer to re-admit the person? `UnbanUser` publishes nothing and doesn't
  rejoin them, so today they have to find the group and join again.
- Which pickers drop silenced and removed members? `group-send.md` and `group-requests.md`
  don't say whether a silenced member can be sent cash or asked to pay.
