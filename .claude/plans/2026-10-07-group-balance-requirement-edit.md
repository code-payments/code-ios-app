# Editing a group's balance requirements

Originally built against a stub (flipcash2-client-protocol 0.18.0 had no rules edit). Wired to
`EditChatRequest.rules` in 0.23.0 on 2026-10-29.

## Contract (`chat/v1/chat_service.proto`, `EditChatRequest.rules`)

- Full replacement rule set. Only a public group created with a listener minimum is editable;
  private is DENIED, anything else INVALID_RULES.
- The listener minimum keeps its currency and mints; it can't be added or removed.
- A speaker minimum uses the listener's currency and mints, exceeds the listener minimum by at
  least the currency's minimum transfer value, and can be added, changed, or removed.
- Every amount is at least the minimum transfer value (0.01 USD, 1 JPY).
- Other rules (staff, creator) go back as the group has them.
- The creator must satisfy the new rules, speaker included (RULES_NOT_SATISFIED otherwise).
- Rules never remove a member: one short of the listener rules keeps reading but can't speak, as
  when their balance falls; after a leave they must satisfy the rules to rejoin.

## How iOS does it

- `ConversationRules` keeps the serialized proto the server last sent (`wire`, outside equality).
  `ConversationRulesEdit` edits that proto, so unreadable rules and malformed mints go back
  verbatim. `ConversationRules(proto)`'s `compactMap` would drop them.
- `EditGroupBalanceRequirementModel` converts the entry into the join minimum's currency, rounds
  to its smallest unit, and blocks before sending: Chat ≤ Join ("Chat Minimum Too Low"), Join ≥
  Chat (INVALID_RULES copy), and the creator not meeting the rules (RULES_NOT_SATISFIED copy,
  skipped when the gate is provisional). Unchanged amounts keep Save shut.
- The Chat row reads the group's own speaker minimum ("None" without one). "Remove" in the Chat
  editor's toolbar clears it.
- Edit Group shows the card only on a public group with a join minimum.
- `applyEdit` seats the returned rules. `applyRulesChanged` ignores a set whose listener rule this
  client can't read (`dropsListenerRule`), keeping the old gate rather than opening the chat.
  A refetch would decode the same way.

## Live rules

- Gates read `conversationController.conversation(withID:)` in their bodies, so the stream's
  `.rulesChanged` reaches them directly. A member failing the listener rules is `.readOnly`, not
  `.blocked`.
- Group link cards overlay the stored rules on their fetched copy (`GroupLinkPresenter.storedRules`).
- A held group the viewer isn't in gets no `.rulesChanged`, so `hydratedConversation` refetches its
  rules when it is reopened.
