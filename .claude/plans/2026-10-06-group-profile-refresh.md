# Group profile refresh (iOS)

Spec: `docs/specs/group-profile-refresh.md` in the orchestrator root, sections "Approved new pieces"
and "Group profile screen". Figma file Jxf2wD9QyfKaONbhHSdU0K: node 10913:358 (profile), 10918:203
(host view), 10935:202/10935:263 (leave), 11001:1674 (share), 10913:246/282/318 (gate states).

## Where things live

- `ChatProfileScreen.swift` — the screen. Same shape as `UserProfileScreen`: `ProfileHeaderView`
  with `.group(conversationID, picture: coverPicture)`, ⋯ menu in the system toolbar, pinned
  actions in `scrollEdgeBar(.bottom)`.
- `GroupProfileState.swift` — the pure logic, tested in `GroupProfileStateTests`:
  - `GroupProfileCTA.resolve(gate:isMember:)` reads the `ConversationGate` verdicts directly.
    `conversationGatePresentation` ignores membership, so it would tell a member who fell under the
    join minimum to "Buy … to Join".
  - `GroupBalanceRequirements` — Join is the first listener minimum; Chat is the first speaker
    minimum, falling back to Join (backend: speaker rules equal listener rules when none are set).
  - `balanceShortfall(of:mint:holdings:rates:)` — the Buy button names the shortfall, the line
    above it the full requirement. Held balance comes from `heldBalance(in:session:)`, extracted
    from `unmetBalance` in `ConversationGate.swift` so the two can't disagree.
- `GroupChattingGrid.swift` — Chatting grid and host wave badge. Fed by `sampleChatters` only, no
  per-chatter GetProfile. Hidden for private groups (the RPC is DENIED) and for an empty sample.

## Decisions

- Join and Open Chat pop back to the conversation: the only entry is `ConversationScreen.swift:154`,
  and that screen loads its transcript when the gate stops obscuring it.
- Overflow: Invite and Mute for members, Report and Encryption for everyone. Edit moved to an
  "Edit Group" capsule in the header row.
- Share sheet "Share on Flipcash" opens `GroupInviteSheet`; Copy Link copies `groupChatInvite`.
- `ChatMuteRow` and `ReportRow` had no other callers and were removed.
