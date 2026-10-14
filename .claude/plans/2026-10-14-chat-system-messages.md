# Plan: render server system messages in private group chats (iOS)

Repo `/Users/bmc/dev/bmcreations/code/code-ios-app`, base `main` (HEAD `7fab7a59` when read). Read-only plan.
Abbreviations: `C/` = `FlipcashCore/Sources/FlipcashCore`, `S/` = `FlipcashCore/Sources/FlipcashStore`, `UI/` = `FlipcashUI/Sources/FlipcashUI`.

## Context
Server `SystemContent { fallback_text }` messages are mapped to nil and dropped today
(`C/Models/Conversation/ConversationMessage.swift:333-335`). Goal: keep them, persist them, show them as a
non-bubble transcript row and as the chat-list preview, and keep them out of client-computed unread. Shared
spec with Android. Working visual default is now **Option D** (Figma node 11721:918), not A.

## Steps

### 1. Model + mapping (FlipcashCore)
- `C/Models/Conversation/ConversationMessage.swift:47-70`: add `case system(fallbackText: String)` to `Content` with a `///` contract doc.
- `:333-335`: split `case .system, .none`. New arm `case .system(let system): guard let content = Content(system: system) else { return nil }`.
- Add `init?(system: Flipcash_Messaging_V1_SystemContent)` (fileprivate/internal, same file). Body today: trim `fallbackText` with `.whitespacesAndNewlines`; nil if empty (spec 6), else `.system(fallbackText:)`. This is the single place a future `switch system.event { case known: localized; default: fallback }` goes. Inline comment states only that constraint.
- `senderID` is already optional (`:106`, `:342`), so no sender workaround. `.widget` is the precedent for a sender-less message.
- `:308` (nested reply): leave `.system` returning nil. A reply never wraps server content.
- `:375` `asProto()`: add `.system` to the throwing `unsupported` arm (`.cash, .deleted, .widget`).
- `C/Models/Conversation/MessageCapability.swift:98-120`: `.system` returns `[]` (spec 5, parity with Android `MessageCapability`).
- Other exhaustive `Content` switches that need an arm (compiler will flag all):
  - `C/Models/Chat/ChatPreviewMapping.swift:~72-107` and `:116` (notification preview): same arm as `.widget(.unrecognized)`/`.deleted`; emoji check `false`.
  - `C/Push/NotificationPayload.swift:97` `decryptedBody`: nil (non-text).
  - `FlipcashCore/Tests/FlipcashCoreTests/ConversationStoreMutationTests.swift:~30-36` and `FlipcashTests/Chat/ConversationMediaSendTests.swift:372` test helpers.
- No change to `ChatMessagingService.swift:51,89,138,226,275,316`, `ConversationStreamEvent.swift:294-300`, or `Conversation.swift:170`. They un-drop automatically once the init returns non-nil. `ConversationStreamEvent` is the live arrival path.

### 2. Persistence (FlipcashStore)
- `S/Database+Conversations.swift:~575-606` write: `case .system(let text): kind = 6; text = text`. No new column.
- `:805-852` read: `case 6: guard let text = row[m.text] else { return nil }; return .system(fallbackText: text)`. Same pattern as kind 0.
- `S/Database.swift:224`: bump `schemaVersion` 48 → 49 (hard rule: changed write encoding). Rebuild runs at `Flipcash/Core/Session/DatabaseStore.swift:75-82`.
- Older builds reading kind 6 (confirmed safe):
  - The unknown-kind `default: return nil` drops it.
  - List reads use `compactMap` (`:179,192,203,217`), so there is no crash and paging still works.
  - The notification extension refuses any version mismatch (`S/ExtensionStore.swift:68`).
  - Residual: a downgrade opens the newer DB as-is (rebuild fires only when `current > stored`). It has two visible effects, and both are transient because the old build never writes kind 6, so the next normal message clears them:
    - (a) `latestMessage` (`:127`, `pluck` of one row) returns nil, so that chat's feed preview goes blank.
    - (b) `newestMessage` (`:145`) returns nil, so `lastConfirmedMessage` (`ConversationController.swift:1866-1872`) loses its receive-buzz and mark-read anchor for that chat.
    - No crash and no data loss. Accepted. The only fix would be in the old build.

### 3. Unread (spec 8)
- `S/Database+Conversations.swift:241-251` `inboundMessageCount` (sole caller `ConversationController.swift:1838`, the divider count): add `&& m.kind != 6`. Today `senderId == nil` rows count as inbound.
- `:256-266` `firstInboundMessageID` (divider position; currently filters only id + sender and includes tombstones): add `&& m.kind != 6` and update its doc comment ("A row with no sender counts as someone else's" → except system rows), so the divider never lands directly above a system row. With S between the read pointer and B, `readThrough = B-1`, and `UnreadBoundary.dividerBetween` (`C/Models/Conversation/UnreadBoundary.swift:57-63`) puts the divider below S and above B. When only system messages are unread, there is no divider.
- How unread works today:
  - (a) Divider position and count are local SQL over the stored READ pointer (above).
  - (b) The chat-list badge is `Conversation.unreadCount` (`C/.../Conversation.swift:239-249`) = `lastMessage.unreadSeq − readSeq`. `unreadSeq` is **server-stamped**, so leave it alone.
  - (c) `Conversation.hasUnread` (`:219-229`) is a client boolean: `readPointer < lastMessage.id` unless the last message is the viewer's own. See Open questions.

### 4. Transcript row (spec 3, 5, 6)
- `C/Models/Chat/ChatItem.swift:14-27`: add `case systemMessage(id: String, text: String)` (doc'd). `id` (`:29-37`) returns `id`. Add it to the nil arm at `:48`.
- `Flipcash/Core/Screens/Conversation/ChatItem+Conversation.swift` (`ChatItem.from`, loop `:186-373`):
  - Separator/marker/divider emission at `:192-205` stays first, so a system message on a new day still gets its date header.
  - In the `message.content` switch at `:236`, the `.system(let text)` arm does `items.append(.systemMessage(id: "sys-\(message.stableID)", text: text)); continue`. Mirrors `"sep-\(message.stableID)"`.
  - Break grouping: add `&& !$0.isSystem` (or the `if case .system` equivalent) to the `groupedAbove`/`groupedBelow` closures at `:216-222`. Grouping keys on `senderID` of the adjacent *message*, and system and `.widget` rows both have a nil sender, so without this a share-profile widget would group with a system row. Add it to `rendersBare`/`carriesReceipt` neighbours at `:230-233` so a receipt never anchors to a system row.
  - Other switches in the file: `:154` `isEmojiOnlyBody` → false; `:167` link layouts → none; `:~395-460` reply-quote → same arm as an unavailable original (unreachable, no reply capability).
- `UI/Chat/ChatItem+Differentiable.swift:26-35`: `case .systemMessage: ChatSystemMessageCell.reuseIdentifier`. Identity is `"\(reuseId):\(id)"` and equality is synthesized `==` (`:17-18`), so no other diff code is needed. The `sys-` id is stable across reloads because it derives from `stableID`.
- `UI/Chat/ChatViewController.swift`:
  - Register the cell at `:327-335`.
  - Configure it in `cellForItemAt` at `:590-608`.
  - Add `.systemMessage` to the non-message arms at `:142-149` (continue), `:519-522`, `:545-550`, `:562-565`, and `sender(at:)` `:1302-1309` (nil).
  - Add it to `isHeading(at:)` `:1286-1292` so spacing matches separators.
  - Interaction (spec 5): no new gating needed. Long-press (`:800-807`, `:1320`), context menu (`:1358`), double-tap reaction (`:817`, `:1317`) and swipe-to-reply (`:341-352`) all require `.message` plus `BubbleCarrying`/`ChatColumnCell`. The new cell is a plain `UICollectionViewCell`, so it is excluded. Scroll anchoring at `:845-856` is unaffected.

### 5. Cell, Option D (spec 4, revised)
New `UI/Chat/ChatSystemMessageCell.swift`, a plain UIKit `UICollectionViewCell` that copies `ChatEncryptionMarkerCell`/`ChatUnreadDividerCell` structure (`static let reuseIdentifier`, `configure(text:)`). All styling lives in this file:
- Glyph: `UIImageView(image: UIImage(systemName: "info.circle", withConfiguration: .init(pointSize: 14)))`, the same SF Symbol as `UI/Theme/Image+Symbols.swift:61` (`case info = "info.circle"`). UIKit precedent: `ChatEncryptionMarkerCell.swift:25-26`.
- 6pt gap, then a `UILabel` with `numberOfLines = 0` and centered text.
- Font: no 13pt token exists. `UI/Theme/AppFonts.swift:28-47` has 12/14/16/20/22 only. Use `.default(size: 13, weight: .regular)` (`UI/Theme/FontBook.swift`) inline. Line height 16 via `NSParagraphStyle` min/max line height in an attributed string.
- Color "text/dim" (white 50%): no token. `Color.textSecondary` is opaque rgb 123 (`UI/Theme/Colors.swift:15`). Use `UIColor.white.withAlphaComponent(0.5)` as `ChatDateSeparatorCell.swift:22` does, for both glyph and text.
- Layout: a horizontal stack (glyph top-aligned to the first line), centered with `centerXAnchor`, `width <= 250`, `leading >= 16`, top/bottom 8 like the divider cell. No fill, no hairlines.
- Accessibility: the cell is one element. `accessibilityLabel = text`, traits `.staticText`, glyph hidden from VoiceOver.
- Text is a single server string, so actor names can't be bolded.
- Option E would need, inside the same file:
  - Leading-aligned layout: glyph slot at `ChatColumnCell.rowInset` (12, `UI/Chat/ChatColumnCell.swift:167`), 24pt wide (`ChatAuthorAvatarView.size`, `ChatAuthorAvatarView.swift:23`), a hairline ring of white 0.1 (`Colors.swift:41` `rowSeparator`, or `LinkCardMetrics.borderOpacity`).
  - 8pt gap, then text at x = 44 = the group bubble column (`ChatColumnCell.swift:180,299`), width 272.
  - Caveat: the 44pt column only exists when `reservesAuthorGutter` is true (groups). In a DM the row would sit 32pt right of the bubbles.

### 6. Chat-list preview (spec 7)
- `Flipcash/Core/Controllers/ConversationController.swift:~1568-1617` `lastMessagePreview`: `case .system(let text): return text`, with no prefix (`groupSenderName` `:1645` is nil for a nil sender anyway).
- Other preview call sites: `Flipcash/Core/Spotlight/ChatSpotlightItem.swift:~58-65` returns the text. `ConversationScreen.swift:1003-1021` → nil arm. `ConversationScreen.swift:1080` → `break` arm. `ConversationController.swift:2039` → the log-and-bail arm. `ConversationController.swift:2314` → not-sent arm.
- `S/Database+Conversations.swift:127` needs **no edit**: it is an exclusion filter (`kind != 2 && (kind != 3 || decryptFailure != nil)`), so kind 6 already qualifies as the latest message. `:247` is changed in step 3.

### 7. Encrypted path (spec 9)
Server system messages always arrive as plaintext `Content.system`, never through `ChatSeal`:
- `ChatSeal.open` (`C/Models/Conversation/ChatSeal.swift:127-`) only handles `.encrypted` content.
- The key comes from the chat key plus the sender/peer public keys (`:26`, `:33-39`), which the server does not hold, so it cannot produce a sealed system payload.
- `readable(senderID:)` `:249-269` returning nil for `.system` (`:263`, `:266`) should **stay**. A `.system` inside a sealed payload could only be member-authored and would let a member forge "X joined" notices.
- I found no "First Private Chat" string in the repo. The existing lock notice is the client-derived `.encryptionMarker` (`ChatItem+Conversation.swift:108`, `:194-196`). Any server "First Private Chat" notice would take the plaintext `Content.system` path above.
- Optional one-line comment at `:266` stating the forgery constraint.

### 8. Tests (Swift Testing, existing suites)
- `FlipcashCore/Tests/FlipcashCoreTests/ConversationModelMappingTests.swift` (`@Suite("Conversation model proto mapping")` `:13`). Add:
  - "System content maps to .system with its fallback text": proto `content = [.with { $0.system = .with { $0.fallbackText = "Alex joined the group" } }]`, no sender. Expect `.system(fallbackText:)` and `senderID == nil`.
  - Blank/whitespace-only `fallbackText` → `ConversationMessage(proto) == nil` (parameterized `["", "   ", "\n"]`).
- `FlipcashTests/Chat/ChatMessageMappingTests.swift` (`@Suite("ChatItem mapping from conversation")`, fixtures `text(_:_:_:after:)` `:24`). Add:
  - A system message yields exactly one `.systemMessage(id: "sys-…", text: "Alex joined the group")`.
  - Two bubbles from the same sender on either side of a system row are not grouped (`isContinuationFromPrevious == false`).
  - End-to-end proto → `ConversationMessage` → `ChatItem.from` for the spec example.
  - A blank proto produces no row.
- `FlipcashTests/Chat/UnreadDividerTests.swift` (`@Suite("Unread divider")`): a system message after the pointer is excluded from the count, and only-system-unread gives no divider.
- `FlipcashTests/Database/Database+ConversationsTests.swift` (`@Suite("Conversation offline cache round-trip")`, fixture `textMessage(id:at:)` `:21`): kind-6 write/read round-trip equality with nil sender. `latestMessage` returns the system row. `inboundMessageCount` excludes it.
- **Existing test to change:** `FlipcashCore/Tests/FlipcashCoreTests/Push/NotificationPayloadTests.swift:237-244` uses `system = .with { _ in }` as the "unrepresentable" fixture. It still passes (blank → nil), but its intent is now the blank rule. Swap the fixture to `content = []` (no content), or rename the test.
- Optional: a `ChatSystemMessageCell` layout test following `FlipcashTests/Chat/ChatBubbleViewTests.swift:173` (`systemLayoutSizeFitting`): a 256-char string wraps (height > one line) and does not truncate.

## Parity deviations
- None to the spec's shape. Two interpretation notes for Android:
  - (1) The blank rule is applied at proto mapping, so blank system messages are never stored or used as `lastMessage`. Android should match by dropping at mapping, not only at render.
  - (2) Spec 7's "update the filter at `:127`" is a no-op on iOS (exclusion filter). Only `:247` and `:256` change.
  - (3) Divider *position* also skips system rows (`firstInboundMessageID`). They are treated as read, and the divider lands below them. The spec only says "not counted", so Android must match this or the transcripts diverge.
- The visual default changed from A to D per the updated Figma direction (node 11721:918). The spec text still says A.

## Open questions / risks
1. **`hasUnread` dot** (`Conversation.swift:219-229`) is client-computed from `lastMessage.id`. A system last message lights the unread dot. Suppressing it would hide a real unread message that precedes it. Default: leave it, since the badge count is server `unreadSeq`. Ask the server whether it stamps `unreadSeq` on system messages. If it doesn't, `unreadCount` returns nil when the newest message is system (`:247` guard). Confirm with Android's `FeedProjection.unreadCount`, which the code comment says mirrors iOS.
2. **Receive buzz**: `lastConfirmedMessage` (`ConversationController.swift:1866-1872`, `newestMessage`) would buzz when a system message arrives. Default: allow it. Exclude `.system` if product says no.
3. **Push**: whether the server pushes system messages is unknown. With this change `NotificationPayload.chatMessage` returns a message whose `decryptedBody` is nil, so it falls back to the APS alert.
3b. **Notification rich preview**: the plan maps `.system` to the nil arm in `ChatPreviewMapping.swift:~72-107`, so a push shows no rich content. The alternative is `.text(fallbackText)`. The spec doesn't cover push, so this needs a decision.
3c. **Option D glyph alignment** for multi-line text (top vs vertically centred) isn't specified in the description of node 11721:918. It should be checked against the node.
4. **Future `event` oneof**: kind 6 stores only resolved text. A client-localized event will need its own stored data and another schema bump. That is acceptable under the rebuild-from-server rule.
5. Diff identity `"ChatSystemMessageCell:sys-<stableID>"` cannot collide with message or separator ids.
6. No `.claude/plans/2026-10-13-system-messages.md` was written, because this run was read-only. Copy this plan there when implementing (repo CLAUDE.md convention).

## Verification (narrowest first)
- Step 1: `./Scripts/test.sh FlipcashCoreTests/ConversationModelMappingTests FlipcashCoreTests/NotificationPayloadTests`
- Step 2–3: `./Scripts/test.sh FlipcashTests/DatabaseConversationsTests FlipcashTests/UnreadDividerTests`
- Step 4–6: `./Scripts/test.sh FlipcashTests/ChatMessageMappingTests`, then `./Scripts/build.sh` (exhaustive-switch fallout in Flipcash/FlipcashUI).
- Visual: run on a simulator via loupe, open a group chat that has a system message, and check that a 256-char string wraps centered, long-press and swipe do nothing, and VoiceOver reads the text.
- Final: the user runs the `AllTargets` plan (test.sh refuses it).

## Overrides (2026-10-14)

- Visual is Figma Option E (nodes 11721:934 / 11721:942): ringed `info.circle` slot in the avatar gutter, text at the member bubble column.
- No receive haptic for a system message: the `.sensoryFeedback` closure guards it (`ConversationMessage.buzzesOnReceive(selfUserID:)`); mark-read is untouched and still sees the system message.
- Blank text is stored as `""` in kind 6 and rendered as no row. This replaces dropping it at mapping.
- The chat-list preview query skips blank kind 6 rows, so the preview falls back to the previous message.
- The read pointer may land on a system message id.
- Row key is `sys-<stableID>`, since a message carries a single content.
