# Profile pages redesign (User, Private Group, Public Group)

Branch `feat/ui-profile` (local only), worktree `~/Developer/code-ios-app-profile`, cut from
`feat/ui-swipe-to-send` @ c228fb4a. Round 1 is **Figma only**, on the page **Profiles** (814:2) in
"Components – Flipcash" (`R2TbSk4RbeLZz29rJr61uE`). Aiden makes every taste call.

Note for shipping: this plan lives under `.claude/`, which a design PR must not touch. Leave it out
of any PR, or ask the dev first.

## 1. What exists today

Two screens and one shared header:

| Profile | Screen | Shared pieces |
|---|---|---|
| User | `Screens/Profile/UserProfileScreen.swift` (`UserProfileContent` :46, `UserProfileViewModel` :462) | `ProfileHeaderView`, `ProfileCoverBanner`, `ProfilePinnedBackdrop` |
| Private group + public group | `Screens/Profile/ChatProfileScreen.swift`, one screen that branches on `isPrivate` (:70) and `isMember` (:59) | same, plus `GroupChattingGrid` |

The shared skeleton:
- A cover 214pt tall, made of literals. With no image it shows a flat grey `coverPlaceholder`, and that grey is what most groups show.
- An 84pt avatar overlapping the cover by 42pt, with a 5pt ring.
- A 38pt share circle.
- A title in `.appDisplaySmall`.
- The side inset is 24 (`ProfileHeaderMetrics.inset`). The house standard says 20.
- The CTA is `CodeButton(.filled)`: a square-ish white slab, not the 54pt capsule.

The bottom slot:
- On group pages, "Leave Chat" (`.subtle`) often takes the CTA position.
- No profile has a `#Preview`, a loading skeleton or an error state.

**The CTA slot carries every state.** Its logic is load-bearing and must not change:

| Profile and state | CTA | Source |
|---|---|---|
| User, new | "Send £X to Start Chatting" → gate → `StartChattingSheet` (Lens swipe) | `ProfilePinnedAction`, `UserProfileScreen.swift:351` |
| User, fee unknown | "Start Chatting" → send amount | same |
| User, existing DM | "Open Chat" | same |
| User, blocked | "Unblock" | same |
| Public group | "Open Chat"; the join happens in the chat's gate, not on the profile | `ChatProfileScreen.swift:512` |
| Private, requester | "Request to Join", then "Requested Xm ago" (disabled) and "Cancel Request" | `:550-585` |
| Private, invite preview (Brandon, in development) | "Join Group" | Figma 12846:59 |
| Member, any group | "Leave Chat" (subtle) | `:682` |

## 2. What the data really has

Sources: flipcash2-client-protocol 0.20.0 (f0bc47ee), `FlipcashCore/Models/Profile.swift` and
`Conversation.swift`.

### User (`profile.v1.UserProfile` → `Profile`)

| Field | Status |
|---|---|
| Display name, username, avatar, cover, bio (≤160), joined date (`join_ts`) | exists and is shown |
| Minimum to chat | exists. It is shown via `TipFloor.toOpenDM(...).displayed`, not the raw field. |
| Favourite public groups | exists (`GetFeaturedGroups`) |
| Card colour (`tipCardCustomization.colorHex`) | exists, fetched, **not displayed** |
| X profile (`social_profiles`: handle, verified type, follower count) | **in the proto, not mapped in Swift**. Dev question. |
| Currencies they hold | **absent**. Holdings exist only on groups. Backend question. |
| Chat state with this user | derived locally (DM exists, blocked, muted) |

### Groups (`chat.v1.Metadata` → `Conversation`)

| Field | Private | Public |
|---|---|---|
| Title, picture, cover, description (≤160, not persisted, so nil after a cold start) | exists | exists |
| Member count (`roster_summary.member_count`) | shown | **exists, not shown** |
| Faces | roster (`GetRoster`, members only, paged by 50) | `SampleChatters` (≤100, creator first, then recent senders; not the full roster) |
| Host | `creator` (wave badge) | same |
| Roles beyond host | absent | absent |
| Join requirement | host approval through the lobby; no `rules` | `rules.listener` minimum balance (`amount`, `mints[≤1]`) |
| Minimum to chat | absent | `rules.speaker` (falls back to the join rule) |
| Holdings (`holdings_summary`: mint, quarks, holder_count, as_of) | absent | **exists, never displayed**. Only set above a server holder minimum. |
| Last activity, last message | exists, not shown | exists, not shown |
| Created date, category or tags, "full" | absent | absent |
| Muted | `viewer_state.mute` | same |

## 3. Load-bearing walls (do not touch)

- **Every CTA's action and its resolve order.** That covers `ProfilePinnedAction`, `tapPinned`, the give-cash gate, the `StartChattingSheet` hand-off and `PostPaymentChat`.
- **Fee and amount text.** It is rendered by `TipFloor` and `FiatAmount.formatted*`; we show it, we don't re-derive it.
- **Group logic:** the gate (`ConversationGate`), membership (`isMember` comes from the roster), `canEdit` as the sole gate on Edit, and the lobby request and cancel flow.
- **Navigation:** the `ChatProfileOrigin` and `UserProfileOrigin` semantics, `popToRoot` on leave, block popping, and the profile being a **pushed page** (not a tray).
- **Accessibility ids:** `profile-*`, `group-profile-*` and `chat-profile-*` stay.

## 4. In-flight work the redesign must leave room for

- **Group Invites** (Brandon, 12844:56):
  - an invite-preview state ("You've been invited to join", Join Group, a 10-face grid with "+39 more");
  - a dead-link subtitle;
  - an "Invite to …" sheet from Share;
  - "Invite Links" in the ⋯ menu.
- **Moderation** (12419:77643): "Moderation ›" in the host's ⋯ menu, and an "In {group}" section (Silence, Remove) on a member's profile menu.
- **Join Requests on chats**: lives on the chat-list row, and the profile's Join Requests card stays.

## 5. Prior art (short)

The prior-art agent's full report has Mobbin links. Patterns worth keeping:
1. One skeleton with a swapped subtitle (Telegram).
2. The price in a single pinned capsule (Orb, Telegram, Revolut).
3. Metadata as one muted line (Threads, Luma, Partiful).
4. A colour wash taken from the cover or avatar instead of glass over content (Luma, Discord, Arc).
5. A facepile plus a count for groups (Instagram, Base).
6. Private vs public described by how you get in, not by a lock (Telegram, Discord).
7. Own vs other differs only in the action row (Cash App, Partiful).

Avoid three-stat columns, upsell cards and glass on content.

## 6. Directions (round 1: Figma, all three types side by side)

All three share:
- The CTA is a 54pt capsule, `.filled`, the only filled button on the screen.
- Glass only on the back and ⋯ circles, on iOS 26+, with a material fallback on iOS 18. The CTA floats over
  the shipped fade: no bar surface and no glass.
- 20pt margins (`screen/margin`).
- 2pt Central icons and rows v2.
- Presses are a small scale; state changes snap.

### A · Editorial
- **Type-led and calm.** The cover becomes a soft wash: the cover image, or a tint taken from the avatar, fading to black about a third of the way down. No grey block.
- **Identity block:** a large left-aligned name with the avatar on the right (about 72pt), then one muted line ("@ted · Joined Feb 2026", "Private · 5 members · Host approves", "Public · 22 people · $100 to join"), then the bio or description.
- **Sections** are quiet rows v2 lists: Favourite groups, Members (facepile row → list), Requirements.

References: Threads, Luma, Cash App.

### B · Cover stage
- **An evolution of today's skeleton, made photographic.** A taller full-bleed cover that fades into black, with no hard edge.
- **Empty covers** get a gradient taken from the avatar instead of grey.
- **Identity is centred:** about a 96pt avatar overlapping the fade, then the name and handle.
- **One grouped info card per question:**
  - User: "Minimum to chat · Joined".
  - Group: "Access" (Private · host approves, or Public · Join $100 · Chat $100), then "Members" as a facepile and count.

References: Orb, Venmo org, Revolut group, Discord.

### C · The card
- **Identity lives on an object.** A rounded card at the top holds the cover, avatar and name, like the Flipcash tip card or a Family wallet card. The card colour can come from `tipCardCustomization.colorHex`, which is fetched but unused today.
- **Group cards** carry the facepile and access line on the card itself.
- **Below the card**, grouped rows v2 (style B) hold the rest.
- **The most ownable direction:** it ties the profile to "Share Profile → View Card".

References: Family, Base token card, the Flipcash tip card.

## 7. Taste calls for Aiden (A/B)

1. Minimum to chat appears twice, on the stat card and in the CTA label. **A:** CTA only. **B:** keep both.
2. Leave Chat. **A:** at the end of the scroll as a quiet destructive row. **B:** in the ⋯ menu. B moves a control between view code and `ProfileMenuItems`, so ask the dev first.
3. Empty cover. **A:** a tint taken from the avatar. **B:** no cover area at all when there's no image.
4. Avatar. **A:** left-aligned. **B:** centred.

## 8. Open questions for the dev or backend

1. Currencies a user holds: not in `UserProfile`. Is a field planned, and is it public?
2. The X `social_profiles` in the proto: OK to map into `Profile` and show a verified handle?
3. Public groups: OK to show `member_count` (it exists) and `holdings_summary` ("Held by N people")? What are the semantics of the server holder minimum?
4. Show met or unmet requirement state on the public profile? That needs the `ConversationGate` comparison, so the dev owns it.
5. Should the public profile's CTA ever say "Join" rather than "Open Chat"? Today the join is in the chat by design (Oct 3 note: "The profile always opens the chat").
6. Group created date: absent. Is it wanted?
7. Loading and error: there's no skeleton, and a failed fetch is silent. Is a design-only skeleton OK?
8. Own profile: your own handle routes to the tip card, not this screen. The Oct 3 design had "the You tab becomes your profile". Out of scope here?

## 9. Round 1 frames (Figma)

Page Profiles `814:2`. Sections and frames (User / Private / Public, iOS, Dark):

| Direction | Section | Frames |
|---|---|---|
| A · Editorial | 818:2 | 822:2 · 822:162 · 822:360 |
| B · Cover stage | 818:5 | 822:3997 · 825:4344 · 828:935 |
| C · The card | 818:8 | 823:460 · 824:572 · 827:811 |

The states drawn:
- User: a new contact, with "Send £1.51 to Start Chatting".
- Private: a member who arrived from a link, with Open Chat.
- Public: a non-member, with Open Chat.

Photos are gradient stand-ins named `⚠︎ photo:`. New pieces are named `⚠︎ not in Screen Kit:` (header wash, cover fade,
identity block, facepile, stat card, profile card).

**The critique (design-critic, fresh context)** returned "approve with changes". It was folded in as follows:
- **Leave Chat restored on C · Private.** Also removed there: the redundant "See all 5" row and the slab behind the CTA.
- **CTA fade.** B gets the shipped fade, and B's cover is shortened so content clears the CTA.
- **B · Public logo:** the "f" glyph read as Facebook's logo, so it was replaced.
- **Copy:** "Invite only" became "The host approves who joins"; "Favourite groups" became the shipped "Favorite Public
  Groups".
- **Public "22 members":** the chevron is gone, because non-members have no roster.
- **Hit areas:** Share is 44pt, and C's share circle has no glass.

Kept against the critique:
- **"Your Balance" on public groups:** it ships today (`ChatProfileScreen.swift:453`).
- **Pure black page:** Aiden chose #000000 on 2026-10-28. The critic read `backgroundMain` #19191A in design-standard
  §1, so that doc is out of date.

**Not drawn yet (round 2, for the chosen direction):**
- **Group opened from its chat:** no pinned CTA, and Leave Chat ends the scroll. This is the most common route.
- **User CTA states:** Start Chatting (fee unknown), Open Chat (DM), Unblock, and own profile (no CTA).
- **Private CTA states:** Request to Join; "Requested Xm ago" plus Cancel Request (two controls in one slot);
  Join Group (invite preview, Brandon); and the host with the Join Requests card.
- **Empty and fallback states:** loading, empty bio, no favourites, long title, and AX5.

## 9b. Round 2: states and social links (2026-10-28)

The sections are now 2490×3340 each: A at y 0, B at y 3500, C at y 7000. Row 1 is unchanged except for the X link. Row 2
holds the User states (Own profile / Already chatting / Blocked). Row 3 holds the Group states (Private requester /
Private requested / Private host / Public opened from its chat / Private invite preview).

| Direction | User states | Group states |
|---|---|---|
| A | 840:1015 · 840:1153 · 840:1278 | 840:1410 · 840:1573 · 840:1749 · 840:1942 · 840:2091 |
| B | 842:1788 · 842:1951 · 842:2096 | 842:2248 · 842:2376 · 842:2517 · 842:2688 · 842:2864 |
| C | 846:2571 · 846:2735 · 846:2891 | 846:3054 · 846:3252 · 846:3463 · 846:3673 · 846:3856 |

**Social links.** The proto has X only: `UserProfile.social_profiles`, at most one item, an `XProfile` with username, name,
`verified_type` and `follower_count`. The `LinkSocialAccount` and `UnlinkSocialAccount` RPCs exist. Swift `Profile`
doesn't map any of it yet, and Instagram and the other networks are absent.

How the frames use it:
- X is drawn with sample data (@tedlivingston, verified, 12.4K followers).
- A shows it as an inline link, B as a centred chip, and C as a row in the details card.
- The own profile shows "Connect X".
- Questions for the dev and backend: map `social_profiles`; add the link flow; other networks need backend fields.

**CTA by state** (labels as shipped):

| State | CTA |
|---|---|
| Own profile | none (Edit Profile and Share sit at the header) |
| Already chatting | Open Chat |
| Blocked | Unblock, plus a Blocked chip |
| Private requester | Request to Join, with the roster hidden |
| Private requested | the approval line, a disabled "Requested 2h ago" and a subtle Cancel Request |
| Private host | Edit Group plus a Join Requests card ("3 people are waiting"), then Open Chat |
| Public opened from its chat | no pinned CTA, and Leave Chat ends the scroll |
| Private invite preview | Join Group (Brandon's in-flight design), 48 members, "+38 more" |

Deviations noted by the builder:
- On the host frames in A and C, Leave Chat sits below the fold.
- In B, opened from its chat, Leave Chat ends the scroll (as today) instead of moving to the ⋯ menu as B's round 1 had it.
- To keep content clear of the fade, B's body moved up and C's card was trimmed to 196.

No critique was run on round 2 (Aiden asked for one agent). Run `/critique` on the chosen direction before code.

## 9c. Direction D · Mix (Aiden's steer, 2026-10-28)

Aiden wants the layout to vary by type:
- **Users** get a full-screen poster made from the profile photo, melting into grouped fields, with no cover.
- **Public groups** keep a cover.
- **Private groups** drop the cover.

All three share left-aligned identity and C's grouped cards.

Section `852:3443` (x 0, y 10500, 1526×2340):

| Row | Frames |
|---|---|
| 1 | User · Poster 852:3447 · Private · Member 852:3603 · Public · Non-member 852:3774 |
| 2 | User · No photo 855:3817 · User · Own profile 855:4001 · User · Scrolled 855:4202 |

How it's built:
- **Melt:** an alpha-only `bg/primary` mask over the lower 45% of the poster (y 308–560), 11 smootherstep stops, plus a
  black legibility scrim peaking at 55%. No band.
- **No photo:** the card colour (`tipCardCustomization.colorHex`) with a 120pt monogram.
- **Scrolled:** the poster leaves with a +60 parallax, and the inline nav title takes over.

Questions for the dev:
1. Is the uploaded `profile_picture` resolution enough for full-screen?
2. Should the card colour be the fallback when there's no photo?
3. Today's content only scrolls about 180pt, so the collapsed title would never show. That needs content or an inset decision.
4. Private groups still have `cover_picture` in the data; it's just not shown here.

Rest states:
- The User poster's Favorite Groups card sits under the CTA fade. It's meant to scroll.
- On the private page, Leave Chat brushes the fade.

### D revision 1 (Aiden's feedback, 2026-10-28)

- **Private:** members are a 3-column grid of 72pt avatars with names inside a `list/card` card, the host first with a
  Hand5Finger badge, under the header "Members · 5".
- **Public requirements:** a "requirement pass" tile with the amount as the hero (`type/amount`), then "of ◉ Jeffy" and
  "to join and chat".
  - When join == chat it collapses to one tile. The dev needs to confirm that comparison: same currency, same amount.
  - The new frame 863:4171 covers Join ≠ Chat, with two tiles ($50 to join, $100 to chat).
  - "Your balance" stays as the footer.
  - "Jeffy" is a sample currency name.
- **User:**
  - "Joined" moves out of the Details card into a `text/tertiary` footnote at the end of the scroll.
  - Socials are a horizontally scrolling chip row in the identity block (X with verified mark, Instagram, TikTok;
    Central brand icons). Own profile adds a dashed "+ Add" chip.
  - The Details card holds only "Minimum to chat".
  - Instagram and TikTok are drawn as if linked. They need backend fields and link flows (the proto has X only).

### D: requirement status (met / unmet), 2026-10-28

The question: can a viewer see at a glance whether they meet a public group's requirements? Section D grows to 2008×4666.
Every frame keeps "Open Chat"; the status replaces the "Your balance" footer.

| Option | Met | Short | Split (join $50 / chat $100, hold $70) | Checking |
|---|---|---|---|---|
| A · status line | 868:4259 | 868:4424 | 868:4586 | 868:4779 |
| B · holding meter | 868:4945 | 868:5112 | 868:5274 | 868:5467 |

Colour and treatment:
- **Met:** `money/positive` with Central CircleCheck.
- **Short:** "$N more" in `text/warning`, the rest `text/primary`. No error red.
- **B's short bar:** `text/primary` on a `control/fill` track; a met bar caps at 100%.
- **Checking:** `text/tertiary`, no tick. The gate fails open with no rate (`isProvisional`).

**For the dev:** the verdict and shortfall must come from the existing chat gate (`ConversationGate` `unmetBalance` /
`balanceShortfall`, `GroupProfileState.swift:95`). The view never compares amounts. Option C, a "Buy $X to Join" CTA,
is parked because it changes what the button does.

### D: public group immersive colour (Aiden's reference: cooking-app recipe page), 2026-10-28

The cover melts into a deep colour derived from it, which becomes the whole page background. Secondary text takes a
light tint of the hue instead of grey, the surfaces are a lighter tint, and Share is an outline pill in the tint. The
CTA stays the white capsule, with its fade ramping into the page colour. Row 5 of section D (now 2008×5864).

| Frame | id | Page / tint / surface |
|---|---|---|
| Blue · Met | 870:5124 | #0B1F4D / #A9C1F5 / #1F315B |
| Warm cover · Met | 870:5287 | #3A1606 / #F2C9A8 / #4A291A |
| Blue · Short | 870:5450 | as Blue; `text/warning` (#FFF383) reads on navy, "You hold" in tint |
| No cover (from avatar) | 870:5610 | #0C1C42, a radial glow of the logo blue behind the avatar |

Hairlines are the tint at 20%. Every colour is a literal named "· derived from cover (literal)".

**For the dev: the colour source.** The cover's blurhash already encodes its average colour (the DC term), so the colour
can be derived client-side with no new backend data. Clamp the lightness for contrast, e.g. OKLCH L ≈ 0.20–0.24.
With no cover, derive it from the avatar.

**Known nit:** on the warm frame, the amber-to-umber melt is a little abrupt and shows a faint band.

### D: "Chatting recently", tailored, with the host highlighted (2026-10-28)

Row 6 of section D (now 2008×7218), on the blue immersive page. All three options use the hand badge plus a "Host"
pill. "22 members" is never tappable.

| Option | id | Host distinction |
|---|---|---|
| 1 · Portrait carousel | 874:5553 | a taller featured first card (128×148) with the avatar ringed in the tint; others 88×112 with "2m ago"; the 4th card clips as the scroll hint |
| 2 · Activity list | 875:5674 | a pinned top row on a lighter surface (#2A3E6C), avatar 42; three recent rows; "+2 more this week · 22 members" |
| 3 · Pulse headline | 876:5789 | a "Hosted by **Ted Livingston**" line, then a facepile, "6 people chatted this week" and the recent names with times |

Data: `SampleChatters` (host first; `user_profile`, `last_sent_at`, `is_creator`). The counts and recency are derived
client-side from `last_sent_at` (7-day window per the Oct 3 note), so the dev confirms them. Nothing invented: no
mutuals, presence or message previews.

To fit, padding above the identity block was cut to 4 and the section-title padding to 12, which makes this row's
cover slightly shorter than row 5's.

### D: pulse refined, plus group bio, then a polish pass (2026-10-28) ★ Aiden: "by far the best yet"

Row 8 of section D: Default 885:14427, Busy 885:14621, Quiet 885:14819, Nobody this week 885:15013. Row 7 (the refined
carousel 880:5920 / 880:6224 / 880:6528, plus the anatomy board 881:14237) is parked; Aiden prefers low-detail
participants.

The layout, top to bottom:
1. Cover melting into the derived navy.
2. Avatar, name, "Public group · N members".
3. **Bio** (`Conversation.description`, at most 160 characters, white 16 regular).
4. The outline **Share** pill.
5. **Requirements:** the pass tile with status line A.
6. **Chatting recently:** the pulse card, made of a facepile (up to 5 faces at 36, −10 overlap, plus a "+N" bubble), the
   headline "N chatting this week", the meta line "Last message 2m ago · 22 members", a hairline, and a footer row
   "Hosted by **Ted Livingston** ›" (avatar 28 with the hand badge, 44 tap height).
7. Open Chat.

Copy rules by state:
- **Busy:** "84 chatting this week" plus "+79".
- **Quiet:** singular, "1 chatting this week", so the copy must inflect.
- **Nobody this week:** "Quiet this week", no facepile, no bio.

The bio isn't persisted locally, so it can arrive late after a cold start. Avoid a layout jump (dev).

**Polish pass:**
- One spacing scale. Identity: avatar → name 12, name → meta 4, meta → bio 8, bio → Share 16. Sections: Share → title
  16, title → card 8, card → title 16. Requirement-tile hairlines have 8 above and below; pulse-card hairlines 12.
- A single outline Share (transparent, 1.5pt tint stroke). The duplicate share circle was removed; row 6's source still
  has it.
- The "Chatting recently" title was restored.
- Tile and card padding is 16, with baselines aligned.
- Section titles stay at the kit's bound 14pt.

**Open:** in Default and Quiet the pulse card ends at about y 805, so its "Hosted by" row sits behind Open Chat at
rest (it scrolls). Either accept the scroll, or move Share into the nav bar as a glass circle next to ⋯ (saves about
60pt and is control-layer glass). That's Aiden's call.

## 12. Code build 1: public group profile, D row 8 (2026-10-28)

Aiden chose to let the "Hosted by" row scroll under the CTA. Tuning mode is on, with `Packages/TunerKit` and
`LocalTuner.swift` copied from the swipe worktree, all git-ignored.

### Scope
- **Changes:** the public branch of `ChatProfileScreen` (`!isPrivate`) only. The private group, the user profile and
  every view model are untouched.
- **Unchanged behaviour:**
  - every action and destination: share/invite, Edit Group (only when `canEdit`), the currency row → `.currencyInfo`,
    portrait → `.userProfile(…, .groupMember)`, Open Chat, Leave Chat;
  - the origins and the pinned-bar logic;
  - the `requirementsNamed` hold-back;
  - accessibility ids;
  - the analytics.

### Colour: "Bleed", ported from `~/Developer/Recipes/Recipes/DesignSystem/Bleed/`
- **Location:** FlipcashUI. It's a package, so there are no pbxproj edits.
- **Files:** BleedRGB, OKLab, BleedColorExtractor (a `CGImage` entry point), BleedPalette, BleedTextStyle, EasedStops,
  BleedFade, ObservableBox, BleedColorStore (keyed by a String id), and a modifier taking an id plus image.
- **Defaults** are the values baked in Recipes commit 6e2c13d: kmeans, sample 0.26, saturation 1.2, L dark 0.10,
  pull 0.6, warmth 1.0, vibrant text 0.6, fade 183. The Recipes PLAN.md is stale, so don't use its values.
- **Source order:**
  1. the cover bitmap (`profileAvatars.data(for: .groupCover(id))`);
  2. the cover blurhash image (`BlurHashCache`);
  3. the avatar data or blurhash;
  4. otherwise the placeholder (today's black).
- Dark-mode palette only (the app is dark).
- **Tunables:** `// LOCAL-TUNER` lines under `Profile/Public/*` for saturation, L dark, pull, fade height and cover height.

### Layout (top to bottom)
1. **Cover:** full-bleed, under the status bar, with the Bleed fade into `palette.background`. The page, scroll and
   navigation container backgrounds all use `palette.background`, with `toolbarColorScheme` from the palette.
2. **Identity:**
   - a left-aligned avatar overlapping the melt, with its ring in `palette.background`;
   - the name, large and bold;
   - "Public group · N members" (`rosterSummary.memberCount`) in the secondary style;
   - the bio (`description`) in white.
3. **Actions:** an outline "Share" pill, 44 tall with a 1.5pt stroke in the secondary colour, doing today's
   `isInviting` action. Edit Group (when `canEdit`) uses the same outline pill. The old 38pt circle goes.
4. **Section titles:** "Requirements" and "Chatting recently", 14 semibold, in the secondary style.
5. **Requirement pass tile:** `controlTint` surface, padding 16, with the amount as the hero.
   - It reads "of ◉ <mint>" (the token icon + name, tappable → `.currencyInfo` exactly as today), then "to join and
     chat". If chat ≠ join, there are two tiles side by side.
   - **Footer:** today's "Your Balance $X" string, unchanged. The met/unmet status line is **parked**, because it
     needs the gate verdict (affordability).
6. **Pulse card:** `controlTint` surface.
   - Up to 5 faces at 36 with −10 overlap, each tappable to its profile as today, and a "+N" bubble.
   - "N chatting this week" (sample chatters with `lastSentAt` inside 7 days), then "Last message <relative> ·
     N members".
   - A hairline, then "Hosted by <creator> ›" (→ the creator's profile).
   - With nobody chatting: "Quiet this week".
7. **Leave Chat** (members) at the end, unchanged in behaviour.
8. **Pinned CTA:** "Open Chat" in the branch's capsule primary style. On iOS 18 the backdrop fade uses
   `palette.background`; on iOS 26 it's the system edge effect.

### For the dev (in the report and the plan)
- The met/unmet status needs the gate verdict on the profile.
- "N chatting this week" counts a server sample of at most 100.
- Collapsing join == chat compares the two rule values.
- The member count is shown on public groups.
- The description arrives late after a cold start.

### Code build 1: result (2026-10-29)

Commits on `feat/ui-profile` (local only):
- `3c2db72e` the Bleed port (FlipcashUI/Theme/Bleed);
- `f0c8e540` the public group profile;
- `f799306f` the design-review fold-in.

The build passes and all 46 profile tests pass, including the new `PublicGroupCopyTests`. `privateScreen` is identical to
before.

**Fold-in:**
- A still-loading group renders as private, so a private group never paints as "Public group".
- Faces and the token link get 44pt hit areas.
- Text on tiles is contrast-solved on the control tint (`controlSecondaryStyle`).
- The pulse card is held back with the requirements.
- The bio animation is page-wide and respects Reduce Motion.
- Presses scale to 0.96 with `Haptics.soft()` on touch-down.
- Hairlines are one device pixel.

**Tunables:** `Profile/Public/{Saturation, L dark, Pull, Fade height, Cover height}`. They must be baked before any PR,
because CI can't see `LocalTuner.swift`.

**Taste calls still open** (from the code critique):
1. "+N" isn't tappable; the old grid opened every sampled chatter.
2. Leave Chat now follows the content.
3. A 33pt title next to a 40pt amount (layout rule 2).
4. First paint fades from #19191A to the cover colour over 0.25s; the colour could be seeded from the blurhash instead.

**Parked for the dev / system work:**
- The met/unmet status line.
- One shared capsule CTA style (the screen button height is still open).
- A Bleed row in the standard.
- Device checks: iOS 18 opaque nav bar banding; iOS 26 opened-from-chat with no bottom fade; AX5; long token names.

## 10. Taste calls after round 1

1. Avatar: right of the name (A), centred over the cover (B), or top-left on the card (C).
2. Identity alignment: left-aligned (A, C) or centred (B).
3. Cover: a wash (A), a full-bleed photo (B), or held inside the card (C). Empty cover: a tint from the avatar, or
   nothing.
4. Minimum to chat: CTA only (A), or a stat plus the CTA (B, C).
5. Leave Chat: at the end of the scroll (A, C), or in the ⋯ menu (B, needs the dev's OK). Red or `.subtle`.
6. Private members: a full list (A, C), or a facepile (B).
7. Name size: 34 (A), 28 (B) or 24 (C).
8. CTA inset: 32 (the Amount and tray decision of 2026-10-19), or 20 (the content edge, which the critic prefers).
9. Card radius: 12 (standard rule 15), or about 22 (`card/radius`, rows v2 style B and trays).

The standard is silent on:
- whether a profile counts as a money screen (layout rule 2: money is the largest text);
- section-heading casing;
- a header avatar size token.

## 11. Log
- 2026-10-28: worktree set up; four surveys and the prior-art report done; Profiles page created; directions proposed.
- 2026-10-28: round 1 built (A, B, C × 3 types); critique run; fix pass folded in.
