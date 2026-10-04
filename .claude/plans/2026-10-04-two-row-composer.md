# Two-row composer (E2)

The composer field becomes two rows inside one glass field.

- Top row: chip strip, then the message text, full width.
- Bottom row: 34pt `+` circle, grey "Send $" capsule, Spacer, white circular send button.
- Field padding 8 all round; the text row is inset 6 more on the leading side.

## Decisions

- `ConversationBarLeadingControl` keeps only what stands outside the field: `.cancelEdit`, `.sendCash` (pre-chat CTA), `.none`.
- New `ConversationBarBottomRow` (plus items, pill flag). Empty while editing and before the chat exists. Cash never appears in its menu: the pill replaces it.
- No bottom row (no `+`, no pill, or editing): single-row field with send on the text row.
- `AttachMenu` is restyled to the 34pt circle and rendered by `ConversationComposer`; panel toggle, frame reporting, stand-in and accessibility are unchanged.
- The attach surface stays an overlay on the bar's row; its collapsed radius is `plus.height / 2`.
- `BarMetrics.contentHeight` still means the single-row field. `BarMetrics.twoRowContentHeight` (84) is the two-row field.

## Tests

Bottom-row decision, Cash dropped from the menu, collapsed radius, bar height, and `AttachPanelPlacementTests` retargeted to `+`'s new column.
