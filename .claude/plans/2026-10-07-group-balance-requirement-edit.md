# Editing a group's balance requirements (stubbed)

## Contract gap

`flipcash2-client-protocol` 0.18.0 (latest tag) has no RPC that changes a group's rules after
`StartChat`. `EditChatRequest` carries only title, profile picture, description, and cover
picture. No branch of `code-payments/flipcash2-protobuf-api` adds one as of 2026-10-07. Android has
no setter either.

## What iOS built

- Edit Group's Balance Requirements card always shows (rows read "None" on a group without one).
  Each row (Join, Chat) pushes `.editGroupBalanceRequirement(id, role:)`.
- `EditGroupBalanceRequirementScreen` is `EnterAmountView(mode: .balanceRequirement)` with a
  "Save" title, confirmed through `DialogItem.confirmGroupChange(.joinRequirement / .chatRequirement)`.
- `EditGroupBalanceRequirementModel`: entry in `balanceCurrency`, saved in USD (the creation
  sheet's conversion), keeps the requirement's existing mint, empty mints for a new one. The Chat
  row seeds from `GroupBalanceRequirements.chat`, which falls back to join; saving writes an
  explicit speaker rule.
- The single stub: `SessionGroupChatEditor.setMinimumBalance(conversationID:role:requirement:)`
  throws `ErrorSetGroupMinimumBalance.unavailable`. The model maps it to a "Not Available Yet"
  dialog without reporting it.

## When the RPC lands

1. Bump the package; add a `FlipClient`/`ChatService` call.
2. Replace the stub body with it.
3. Seat the returned rules: `ConversationController.applyEdit` handles title, description, and
   pictures only — add a rules branch (and a store mutation if none exists).
4. Drop the `.unavailable` case and its dialog, and the "stubbed" note in `EditGroupScreen`'s doc.

## Open

- No way to clear a requirement: the keypad can't express "None".
- No check that the chat minimum is at least the join minimum.
