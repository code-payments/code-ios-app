# Join requests on the Chats list (iOS)

Spec: orchestrator PR code-payments/flipcash-client-orchestrator#69,
`docs/superpowers/specs/2026-10-27-join-requests-chat-list-design.md`. Figma node 12824:117.

## Shape
- `ChatListEntry.joinRequests: ChatListJoinRequests` (count + newest `entered_at`), default `.none`
  so the Share Extension (`ChatListSelection`) and the cross-platform vectors are unchanged.
- `ChatListJoinRequests.sortTime(after:)` is the one `max(lastActivity, newest entered_at)`; the
  projection orders by it and the row shows it as the timestamp.
- Projection: a chat is unread when `unread.isUnread || joinRequests.count > 0`. Feeds Unread chip,
  Groups chip count, Archived row count (muted still excluded) and tab badge. These count chats,
  not messages.
- `ConversationController.chatListProjection` reads `hostedLobbies?.requests(for:)` per entry.
  `HostedLobbies` is `@Observable`, so lobby changes re-sort the list.
- Row (`TipConversationRow`): `ChatRowJoinRequests` (app target, pure) builds the subtitle
  (requests only → request line in `unreadIndicator`; with unread messages → request line, " · ",
  preview in `textSecondary`) and the pill count (requests + unread messages; nil when the message
  count is unknown → dot).

## Verification data
DEBUG launch argument `--stub-join-requests` swaps `HostedLobbies.getMembers` for fixture members
on hosted groups, following the `--motion-sandbox` precedent in `FlipcashApp.swift`.
