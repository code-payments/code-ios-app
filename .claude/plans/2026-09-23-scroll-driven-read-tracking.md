# Scroll-driven read tracking (parity with Android)

iOS marks a whole chat read the moment it opens. Android moves the READ pointer only past messages
that have been on screen. This plan brings iOS to Android's behaviour. It follows the unread divider
(code-ios-app#845), which already resolves its boundary before any pointer moves.

Android reference: code-android-app `aba483bb5` (the #1546 branch).

## What Android does

| # | Behaviour | Where |
|---|---|---|
| A1 | While the list is "positioned", report the highest message id among visible rows that someone else sent. Report it only when it beats the last one reported this visit. Tombstones count; they are `ContentBubble`s. | `messenger/.../components/MessageReadReporter.kt` |
| A2 | Reporting stays off until the opening scroll lands (`hasPositioned`). A chat that opens at the divider first lays out at the bottom, and reporting that frame would mark everything read. | `MessageList.kt:96`, `:195-208` |
| A3 | A non-member (an eligible reader outside the group) never advances. | `ChatViewModel.kt:1397-1405` |
| A4 | Advancing works **local first**. It reports the inbound messages crossed (analytics), writes the local pointer (monotonic), then sends the RPC. | `MessagingDelegate.advanceReadPointer`, `reportCrossedMessages` |
| A5 | Feed sync keeps max(local, server). If local is ahead, it re-sends the pointer without re-reporting analytics. | `FeedSyncDelegate.kt:259-264`, `MessagingDelegate.reportReadPointer` |
| A6 | Unread in the feed: the newest *visible* message is past the pointer **and someone else sent it**. A group with no self row is 0. A DM with no self row uses pointer 0. | `FeedProjection.unreadCount` |
| A7 | Whole-chat `markAsRead` is used only by the notification's "Mark as read" action. A send never advances the pointer; A6 ignores self-sent messages instead. | `NotificationActionReceiver.kt:114` |

## Where iOS differs today

| Android | iOS today | Change |
|---|---|---|
| A1/A2 | `loadTranscript` calls `markRead` on open (`ConversationScreen.swift:997`). Each arrival or send calls `scheduleMarkRead` (`:709`). Both move the pointer to the newest stored id. | Replace with a visible-row reporter gated on positioning. |
| A3 | `canAdvancePointer` guard in `markRead` | Keep; apply it to the new path. |
| A4 | RPC first; local advance only on success (`ConversationController.swift:1570-1595`) | Switch to local first. |
| A5 | `ConversationStore.upsert` overwrites the conversation, member pointers included (`ConversationStore.swift:526`). A local advance the server never took is lost. There's no re-send. | Keep max(local, server) for the self pointer on upsert, and re-send when local is ahead. |
| A6 | `Conversation.hasUnread`: nil pointer → unread, any sender counts (`Conversation.swift:176`) | Ignore self-sent newest. A group with no self row → not unread. |
| A7 | No notification mark-read action exists | Nothing to port. Drop mark-on-send, which A6 makes unnecessary. |

## Implementation

1. **Pure rule (FlipcashCore).** Add `ReadProgress.highestSeenInbound(visible: [(id: MessageID, fromSelf: Bool)]) -> MessageID?`, plus a monotonic "should report" check against the last value reported. Keep it free of UIKit so it stays in the KMP shape.
2. **Visibility (FlipcashUI, `ChatViewController`).** Add `onMessagesSeen: ((MessageID) -> Void)?`. Evaluate it from `scrollViewDidScroll` and after each `update(items:)` layout pass. A message arriving while the reader sits at the bottom produces no scroll event, so the post-layout pass is required. Rows need a confirmed numeric id and a sender. `ChatMessage` has a string `id` and `.me`/`.other`, so either add an optional `serverID: UInt64` or have the mapper pass it through. Pending sends have no id and never report.
3. **Positioning gate.** Arm reporting only after `performInitialScrollIfNeeded` / `performPendingScrollIfLanded` has settled, mirroring A2. Unit-test that the bottom-first layout of a divider open reports nothing.
4. **Controller.** Add `ConversationController.advanceReadPointer(to:in:)`. It is guarded by `canAdvancePointer` and monotonic. It reports receipts for the crossed inbound range, advances the store, persists, and then sends the RPC. Coalesce bursts with the existing 400ms debounce, keeping the highest id. On failure, log and report as today; the local pointer stays ahead for A5 to retry.
5. **Re-send (A5).** On feed and stream upsert, keep the higher self pointer. After a feed refresh, re-send any conversation whose local self pointer is ahead of the server's. Check whether the persisted conversation blob changes encoding; if it does, bump `Database.schemaVersion`.
6. **Unread (A6).** Change `hasUnread(for:type:)` to ignore a self-sent newest message and to treat a group without a self row as read. The divider already treats a missing self row as "no divider" and needs no change.
7. **Remove the whole-chat paths.** Delete the `markRead` call in `loadTranscript` and the `scheduleMarkRead` call in `onChange(latestConfirmedMessage)`. Keep `markRead(conversationID:)` only if something still needs it; otherwise delete it.
8. **Receipts.** `receipts.reportRead(crossed)` must cover only inbound messages the reader actually crossed, matching `getInboundMessagesInRange`. Check whether `database.messages(after:through:)` includes self-sent messages today.

## Tests (Swift Testing)

- `ReadProgress`: the highest inbound wins, self-sent is ignored, tombstones count, it never goes backward.
- The reporter is silent before positioning. A divider open that lands at the top reports only the rows actually on screen.
- The controller advances local first and sends one RPC per coalesced burst. A non-member never advances. A failed RPC leaves local ahead, and the next feed refresh re-sends.
- Store: an upsert with an older server pointer keeps the local one.
- `hasUnread` table (propose sharing it with Android in `docs/cross-platform-parity.md`):

| Newest visible message | Sender | Self row | Pointer | Type | Unread |
|---|---|---|---|---|---|
| 5 | other | yes | 4 | DM | yes |
| 5 | self | yes | 4 | DM | no |
| 5 | other | yes | 5 | group | no |
| 5 | other | no | — | group | no |
| 5 | other | no | — | DM | yes |
| none | — | yes | 4 | DM | no |

## Open questions (answered by the Android session; policy calls still Brandon's)

1. **Visibility threshold.** Android counts any part of a row in `visibleItemsInfo`, even a sliver. That's the simplest check, not a deliberate choice; there's no minimum fraction. **iOS: any intersection with the unobscured area.**
2. **Background.** Android has no lifecycle gate. Its reporter reads `listState.layoutInfo`, which only changes on a layout pass, and a stopped activity gets no frames, so a backgrounded arrival likely isn't reported until the app returns (not verified on a device). UIKit can still apply collection view updates while backgrounded, so **iOS gates explicitly on `scenePhase == .active`** and re-evaluates on becoming active. That reaches the behaviour Android gets implicitly. Whether Android adds an explicit RESUMED gate is Brandon's call.
3. **Debounce.** Android has **no** debounce on reads: each new highest visible inbound id writes the local pointer, then launches the RPC. **iOS: advance the local pointer immediately, no debounce.** Coalescing the RPC is fine (latest id wins, one in flight), as long as the local write isn't delayed, and a pending RPC is flushed on disappear. If an RPC is lost, the feed re-send (step 5) covers it, as on Android.

Step 4 changes accordingly: drop the 400ms debounce for the local write.

## Out of scope

- The jump-to-bottom unread badge.
- Porting this logic to `:kmp:shared-core`. The pure rule in step 1 is shaped for it, but moving it is its own milestone.
