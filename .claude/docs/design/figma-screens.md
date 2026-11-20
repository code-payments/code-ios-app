# Figma screens: the Screen Kit standard

**Owner:** Aiden. **Status:** v1, 2026-10-16, for the chat-first, native, light-and-dark direction.

Every Flipcash device screen in Figma is an instance of a **Screen** component, filled through its slots with
**Chrome** and **content** components. Agents assemble screens. They never draw a status bar, a home indicator, a
device frame, a nav bar or a bubble. If a piece isn't in this kit, flag it (see *When the kit is silent*) instead
of inventing it.

**File:** Components – Flipcash, `R2TbSk4RbeLZz29rJr61uE`. **Page:** Screen Kit (`246:2`). Reference builds
are in its *Examples* section (`247:203`). Read one before building.

---

## 1. Screens: start every frame here

| Component | id | key | Size | Slots (property key → frame in the screen) |
|---|---|---|---|---|
| `Screen/iOS · iPhone 17 Pro` | `246:17` | `53d6c4bcb31dcb3b5bc40ab3c1911f1aa5d3916e` | 402×874 | `Content#246:0` 0,0 402×874 · `Top bar#246:1` 0,0 402×128 · `Bottom bar#246:2` 0,770 402×104 |
| `Screen/Android · 412×915` | `246:76` | `437052ab33fc195f0efabe67de3bd79426197d6c` | 412×915 | `Content#246:3` 0,0 412×915 · `Top bar#246:4` 0,52 412×64 · `Bottom bar#246:5` 0,827 412×88 (runs over the gesture area) |

Already inside each screen (do not add or move them):
- **iOS:** Apple's iOS 27 status bar (with the Dynamic Island) and home indicator.
- **Android:** Material 3's status bar (camera cutout forced to black) and the Android gesture bar.

**Safe areas:**
- **iOS:** content runs edge to edge under the glass bars. The top bar sits over 0–128 and the composer over
  770–874.
- **Android:** the bars are solid. Keep readable content between y 116 and 827.
- **Side margins:** `screen/margin`, which is 20 on iOS and 16 on Android. The nav header's circles stay 16 from the edge.

## 2. Chrome: what goes in the bar slots

| Component | id | Props | Slot |
|---|---|---|---|
| `Chrome/iOS/Title Bar` | `247:172` | `Name#247:4`, `Avatar#247:5` (instance swap) | iOS Top bar, at 0,0 |
| `Chrome/iOS/Composer` (set) | `253:392` | `State` = Resting\|Typing\|Replying\|Editing\|Read-only; `Draft#255:6`, `Reason#255:0` | iOS Bottom bar, at x 0, **y = 104 − height** (Replying is 158 tall and grows upward) |
| `Chrome/iOS/Jump to Bottom` | `253:393` | `Show badge#253:0`, `Count#253:1` | Last child of the iOS Content slot, at x 323, y 726 (over the $ column, 12 pt above the composer) |
| `Chrome/Android/Top App Bar` | `247:191` | `Name#247:7`, `Avatar#247:8` | Android Top bar, at 0,0 |
| `Chrome/Android/Composer` (set) | `254:392` | `State` = Resting\|Typing; `Draft#255:12` | Android Bottom bar, at 0,0. 412×88: a 64 pt bar (field 48 radius 24, controls 32 with 48 touch, $ 48, 16 gutters) plus the 24 pt gesture area under the fade |
| `Chrome/Glass` (set) | `257:358` | `Shape` = Capsule\|Card | Behind every iOS glass control (see below) |

**Glass:** every iOS glass surface uses `Chrome/Glass`. That covers the back button, composer field, `$`, reply
strip, cancel edit, read-only pill and jump button.
- **What it is:** Apple's own iOS 27 "Liquid Glass – Regular – Small" (Active, not Prominent), in both the Light
  and Dark variants. Their visibility is bound to `v2/Color` `appearance/isLight` and `appearance/isDark`, so
  glass follows the screen's appearance with Apple's exact rendering.
- **How to use it:** make it the control's first child, absolute, sized to the control, with constraints
  STRETCH. Give the control frame no fill and no effects.
- **Never build glass by hand.** Rebuilding Apple's recipe with bound variables fails, because Figma drops paint
  blend modes on variable-bound fills.

**The composer matches shipped `ConversationBottomBar`** (latest main `3ae8af58`) in structure and metrics:
- **Field:** a 50 pt capsule (radius 25, padding 8) with `+` attach (34 pt) on the left and the send slot (34 pt)
  on the right.
- **Send:** an accent circle with an arrow, shown only when there's text or a staged photo. While editing it shows
  a checkmark.
- **`$` send-cash:** a 50 pt circle to the right, shown only while the draft is empty.
- **Spacing:** a 32 pt side inset with the keyboard down.
- **Fade:** the bar has no surface. Both platforms float over the shipped `ChatFade` ramp (`ComposerFade.swift`):
  `bg/primary` from clear at the bar's top edge to 90% at the screen's bottom edge. Its opacity follows
  cubic-bezier (0.42, 0.18, 0.17, 1.04) as 33 alpha-mask stops. The bar's top edge is the field top − 8, or the
  reply strip top − 12. On Android the ramp runs on through the gesture area. Never replace it with a solid
  slab or a three-stop gradient.
- **Resting** is the default for a screen with no draft. **Typing** applies whenever the Draft prop has text.
- **Not drawn yet:** multi-line (the controls drop below the text), staged-photo chips, the link-preview card,
  the mention list, keyboard-up (12 pt inset) and the gate panel (Join / Add Cash).

The iOS title bar's back button uses Apple's iOS 27 **Liquid Glass – Regular – Small** (Mode=Light, Active, not
Prominent) with a Central arrow on top. Its blur over the top edge is part of the component.

## 3. Content components (page *Chat v2 · pass 1*, Components section)

| Component | id | Variants / props |
|---|---|---|
| `Chat v2/Bubble` | `202:19` | `sender` = them\|me, `position` = single\|first\|middle\|last; `Text#202:0`. No tail (Aiden, 16 Oct). |
| `Chat v2/Money Card` | `202:56` | `sender` = me\|them; `Caption#202:9` ("You sent" / "You received"), `Amount#202:12` |
| `Chat v2/Reaction` | `238:630` | `state` = default\|mine; `Emoji#238:0`, `Count#238:3` |
| `Chat v2/Add Reaction` | `238:631` | none. It always ends a reaction row |
| `Chat v2/Reaction More` | `238:634` | `Label#238:6` ("3 more"), for when a row would run past two lines |
| `Chat v2/Date Separator` | `202:59` | `Label#202:16` ("Today 12:13 PM", "Yesterday 9:48 PM") |
| `Chat v2/Receipt` | `202:61` | `Status#202:17` (Read / Delivered), `Time#202:18` |
| `Chat v2/Avatar` | `202:20` | `Initials#251:0` ("JL"). The gradient is fixed for now (⚠︎). Rescale instances: 0.55 = 44 pt, 0.5 = 40 pt. Inside Chrome, reach it with `findOne(n => n.type === 'INSTANCE' && n.name.startsWith('Avatar'))` |

`202:19`, `202:56` and `238:630` are **component sets**. Pick a variant by name before calling `createInstance`,
for example `set.children.find(c => c.name === 'sender=me, position=single')`. Variant names use plain keys
(`sender`, `position`, `state`). Only TEXT, BOOLEAN and INSTANCE_SWAP properties carry the `#id` suffix.

Do not use `Chat v2/Reaction Pill` (`202:57`). It is the superseded tapback style.

**Conversation layout** (copy the transcript in `247:204` when in doubt):
- A vertical auto-layout `Transcript` with 16 pt side padding. Each message is a `Row`: horizontal, FILL width,
  aligned MIN for them and MAX for me.
- Gaps, set as each row's `paddingTop`:
  - 3 pt inside a run.
  - 14 pt when the speaker changes.
  - 22 pt before a date separator, and 12 pt after one.
  - 4 pt between a message and its reaction row.
  - 6 pt before a receipt.
- **A money card inside a run** counts as a run member with no position variant. The bubble before it takes
  `first` (or `middle`), and the card sits 3 pt below at its default 240 pt width. If the card ends the run, any
  bubble after it from the same sender starts a new run.
- Reactions are a vertical stack: the message, then 4 pt, then a wrapping row 290 pt wide (gap 4) of `Reaction`
  instances ending with `Add Reaction`, aligned to the sender's side.
- One to three emoji alone are bare 48 pt text, with no bubble. The receipt goes under the latest sent message,
  inset 6 pt.
- Anchor the transcript's bottom just above the composer: iOS y 772, Android y 819. The transcript is a HUG
  vertical auto-layout inside the Content slot. After building it, set `transcript.y = anchor - transcript.height`
  and `constraints.vertical = 'MAX'`. Older messages scroll off the top.

## 4. Tokens and modes

| Collection | id | Modes |
|---|---|---|
| `v2/Color` | `VariableCollectionId:200:8` | Light `200:4`, Dark `200:5` |
| `v2/Accent` | `VariableCollectionId:200:3` | Ink `200:0`, Blue `200:1`, Violet `200:2`, Person `200:3` |
| `v2/Platform` | `VariableCollectionId:200:23` | iOS `200:6`, Android `200:7`. The Screen components already set this |
| Apple Colors (iOS 27 kit) | `VariableCollectionId:d9db42662397f5caf86ba56aafe4ec7588c6e72d/10456:163` | Light `404:0`, Dark `404:1` |
| M3 (Material 3 kit) | `VariableCollectionId:c5d408a1dcb9f7a3cd3c36a5070f681cf8ab13ae/57299:22462` | Light `54778:1`, Dark `54778:4` |

**Dark mode is one mode on the Screen instance: `v2/Color`.** The status-bar glyphs and home indicator inside both
Screen components are bound to `v2/Color` `text/primary` (since 2026-10-19), so never set Apple Colors or M3 modes;
those collections are listed only so you can recognise and clear stale pins.

Colour comes only from `v2/Color` variables:
- Surfaces: `bg/primary`, `bg/elevated`, `bg/chrome`.
- Text: `text/primary`, `text/secondary`, `text/tertiary`, `separator`.
- Bubbles and accent: `bubble/sent`, `bubble/received`, `text/onSent`, `accent`, `onAccent`.
- Money: `money/positive`, `money/onPositive`.
- Reactions: `reaction/fill`, `reaction/mineFill`, `reaction/mineRing`.

Type, radii and bubble padding come from `v2/Platform`. Transparency lives inside the token (RGBA). Never put
opacity on a variable-bound paint (see §7).

Icons are **Central only**, even inside native controls: page *Icons* (`100:2`), sets named
`Icons/<Category>/<Name>` with `Style` = Outlined\|Filled. Recolour every vector fill to a `v2/Color` variable,
because the sets are bound to the old `textMain`.

## 5. Recipe

```js
// use_figma, file R2TbSk4RbeLZz29rJr61uE. Load figma-use first.
const page = await figma.getNodeByIdAsync('<your page>'); await figma.setCurrentPageAsync(page);
await Promise.all([['Inter','Regular'],['Inter','Semi Bold'],['Roboto','Regular'],['Roboto','Medium'],
  ['SF Pro','Regular'],['SF Pro','Semibold']].map(([family, style]) => figma.loadFontAsync({ family, style })));
const screenMain = await figma.getNodeByIdAsync('246:17');            // or '246:76' for Android
const screen = screenMain.createInstance(); screen.name = 'Wallet · iOS · Light';
const slot = name => screen.findAllWithCriteria({ types: ['SLOT'] }).find(s => s.name === name);
const top = (await figma.getNodeByIdAsync('247:172')).createInstance();
slot('Top bar').appendChild(top); top.x = 0; top.y = 0;
top.setProperties({ 'Name#247:4': 'Maya Singh' });                      // see the SF Pro rule below
// Build content: an auto-layout frame of instances, then slot('Content').appendChild(content).
// Dark mode is v2/Color alone; system chrome follows it:
const v2Color = await figma.variables.getVariableCollectionByIdAsync('VariableCollectionId:200:8');
screen.setExplicitVariableModeForCollection(v2Color, '200:5');            // v2 Dark
```

1. **Name the job** (who, what just happened, what they do next) and the pattern before drawing.
2. **Place a Screen instance** on a clear part of the page (not on Screen Kit).
3. **Fill the Top bar and Bottom bar slots** with Chrome. A screen with no composer leaves Bottom bar empty.
4. **Build the content** from §3, inside the Content slot.
5. **Set the appearance and accent** on the instance.
6. **Verify** with `get_screenshot` (the server render), not only `node.screenshot()` (see §7), and read back
   sizes and positions.

## 6. When the kit is silent

These are not in the kit yet: toasts, keyboard-up state, the edited and deleted states, and wallet.

Built since this list was written:
- **Tab bar and headers:** Navigation v2.
- **Settings rows and the chat list row:** Rows v2.
- **Typing indicator, quote panel, mentions and link cards:** the Chat v2 page.
- **Keypad and amount entry:** Screen Kit, Amount v2.
- **Every modal, sheet and dialog:** a **tray**, built from the components on the Trays page (`Tray`, `Tray/Header`,
  `Tray/Page`, `Tray/Action Bar`, `Tray/Option Row`, `Tray/Option Tile`, `Tray/Amount Entry`, `Tray/Content/*`).
  Put it over a screen with the scrim covering the whole frame, status bar included. The card is inset `tray/inset`
  (8) from the sides and the bottom. Copy one of the Examples on the Trays page rather than starting from scratch.

When a screen needs one:
- **A system control:** use the official kit (the keys below) with Central icons swapped in.
- **A Flipcash piece:** compose it from §3 components and §4 tokens, then name the group `⚠︎ not in Screen Kit:
  <name>` so Aiden can decide whether it becomes a component.

Never draw a lookalike of something the kits already have.

**Official kits** (community libraries available to the file):
- **iOS and iPadOS 27** (`lk-3167e7e1…`):
  - Status bar – iPhone 17 Pro: `e01a1714aeec1a5a0a6453485bf16e975008b282`
  - Home Indicator set: `db1fd2b84f66cfc75ab693b5b0b77b90ae471e38`
  - Liquid Glass – Regular – Small set: `2ce2a0ecbf38d9ce2bfe50c3bf99cc28eb52d7b3`
  - Button – Liquid Glass – Symbol set: `36df7438d67ed37c94488fd11d425899f1a902ba`
  - Toolbar – Top – iPhone set: `5a5c7f4643552b05f680c5ee9b1c085a942881cc`
  - Tab Bar – iPhone set: `971f4862d60ea7fb60429ff57f4e51dc42758f6a`
  - Keyboard set: `5fbdb51c96f32525913b449e45f8a821a3e5f032`
- **Material 3 Design Kit** (`lk-5a31d104…`):
  - status-bar: `9ba30f3c7a2122d9ef05a0de9d62435e820e9ed7`
  - App bar set: `23a20484e255cb14cf467ccc984ac918e457cefb`
  - Navigation Bar: Vertical items: `d044e5ea85ee8d7479269dc54c5cb55b7156821d`
  - Keyboard set: `f0b1c4b102ef7a92948e98a6a55ce63cf72fd045`

Import a kit piece with `importComponentByKeyAsync` or `importComponentSetByKeyAsync`.

## 7. Gotchas that cost hours

- **SF Pro can't be edited through the Figma MCP.** It is listed, but it measures at zero width, and
  `setProperties` on SF Pro text throws "uses a font that isn't available". iOS `font/family` is "SF Pro" (with
  `font/emphasis` "Semibold"). To edit iOS text:
  1. Set `font/family` to "Inter" and `font/emphasis` to "Semi Bold" for iOS mode `200:6`.
  2. Edit.
  3. Set them back to "SF Pro" and "Semibold" in the same script.
- **Opacity on a variable-bound paint is the variable's alpha.** A separate `paint.opacity` is silently
  overwritten, so transparency belongs in the token.
- **A variable-bound paint loses its blend mode** (it is reset to NORMAL). When a piece has fixed Light and Dark
  variants, as Apple's glass does, put both inside the component and bind each one's `visible` to a BOOLEAN
  variable in `v2/Color`.
- **`createNodeFromSvg` vectors default to SCALE constraints.** Inserting one into an auto-layout frame resizes the
  frame and shrinks the vector. Set constraints to MIN/MIN first.
- **Bound type and padding values apply lazily.** Measure a frame only after setting literal sizes equal to the
  variable values.
- **Anything that pokes out of a bubble needs ancestors with `clipsContent = false`.**
- **`node.screenshot()` and `get_screenshot` both sometimes return stale renders.** If a render contradicts the
  data you read back, trust the data and render again.
- **Hidden layers named "(previous)"** are Aiden's earlier versions. Leave them alone.
