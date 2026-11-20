# States and copy lens

This lens judges the states a screen can be in and the words it shows in each: the four data states (empty, loading, error, populated), long content, Dynamic Type, in-flight and success controls, destructive confirmation, first-paint correctness, validation timing, shipped leftovers, and every label, title, error, toast and dialog. The reviewer's posture: assume the happy path was tested on a seeded account and the other states were not. Find the branch that does not exist first, then read the copy in the branches that do.

## Rules

1. **Write all four branches of every data-driven view as one exhaustive `switch`: loading, failed, empty, loaded.** The developer's seeded account only ever showed the last one; a new account meets the other three first. `CurrencyDiscoveryList.swift:17-22,34-62`.
2. **Gate the empty branch on a loaded flag, never on `isEmpty` alone.** An array is empty before the first fetch returns, so an ungated branch tells a user with chats that they have none. `BlockedUsersScreen.swift:25`.
3. **Size the empty state to the populated state's box and point at the next action.** A `Spacer()`-only or single-line empty branch is the first screen every new account sees, and nothing on it says what to do. `TipConversationsScreen.swift:256-280` (`NoChatsView`: icon, headline, one sentence, `.frame(maxWidth: .infinity, maxHeight: .infinity)`).
4. **Show a search miss with `SearchResultsUnavailableView(searchText:)`, not the first-run empty state.** A miss has to name what was searched so the user knows what to retype. `CurrencySelectionScreen.swift:62-63`.
5. **Hold the page's shape while it loads: `.redacted(reason: .placeholder)` skeleton rows for content, a spinner only inside the control that is working.** A centered `ProgressView()` collapses the list and the rows jump in when data lands. `CurrencyDiscoveryList.swift:47-49`; `CurrencyDiscoverySkeletonRow.swift:47`; `Loadable` at `ConfirmPhoneScreen.swift:67`.
6. **Delay a loading indicator 300 ms and keep populated rows on screen during a refresh.** A spinner that flashes for 80 ms on a fast response reads as a glitch, and blanking rows the user was reading is worse than the wait. `ReactorsSheet.swift:162-177`.
7. **Give every failed load a message and a retry that refetches.** Spinning forever or rendering nothing is what the app does on a train. `ChatItem+Conversation.swift:293` ("Not Delivered. Tap to retry").
8. **Paint the right state in the first frame: seed `@State` from the store in `init`; never render a default and correct it in `.task`.** The user sees the flash on every cold launch, and a synchronous seed costs single-digit milliseconds. `ActivityHistoryScreen.swift:37-39`; `RatesController.swift:94-116`.
9. **Check a blocking precondition before `router.present`, not inside the sheet.** A sheet that opens, finds it cannot proceed and dismisses itself flashes, and once froze the app (`.claude/reflections/2026-02-06-give-flow-currency-selection.md`). `DeepLinkController.swift:459-467`.
10. **Route a dialog that fires across a sheet boundary through `session.dialogItem`; keep a leaf's one-off dialog in local `@State`.** `.dialog(item:)` is `.sheet(item:)` underneath, so two live bindings of one item fight for the single presentation slot. `DialogWindow.swift:11-13`; `UsernameEntryScreen.swift:32`.
11. **Truncate user strings with `.lineLimit` plus a `.truncationMode` chosen by kind: `.middle` for addresses and keys, `.tail` for names; give long body text an expand control.** Dev data is "Test Project"; real data is a 90-character display name and an address with no break opportunity. `ImmutableField.swift:27`; `TipCardLinkRow.swift:46`; `ExpandableText.swift:10-12`.
12. **Let an amount shrink with `.minimumScaleFactor` before it truncates.** An ellipsis inside money is a different number. `AmountText.swift:43-45`.
13. **Mark multi-line copy `.fixedSize(horizontal: false, vertical: true)` so it wraps at accessibility sizes instead of clipping.** `Font.default` is `.custom(_:size:)`, which scales with Dynamic Type, so a two-line subtitle is four lines at AX3. `Dialog.swift:49`; `PhantomEducationScreen.swift:42`.
14. **Reserve the width and height a label needs at its widest before it changes.** A link that swaps to a spinner or a counter that ticks moves everything beside it. `ConfirmPhoneScreen.swift:67-70` (blank second line reserved); `CurrencyDiscoveryRow.swift:22` (`.monospacedDigit()`).
15. **Disable the submit control and lock the field while a request is in flight, and re-enable both in every failure path.** An enabled button double-fires and one tap becomes two charges; a form left disabled after a failure is the same bug from the other side. `UsernameEntryScreen.swift:70,84`; `OnboardingNameViewModel.swift:80-97`.
16. **Drive a progress-reporting button with `ButtonStateLabel` through `.loading` then `.success`, hold `.success` 500 ms, then navigate.** `ButtonStyle` cannot see the action's state, and an `if isSubmitting { ProgressView() }` label drops the checkmark every other completed action shows. `OnboardingNameViewModel.swift:74-78`.
17. **Show a toast only through `ToastController.show` (its factories such as `.archivedChat` included): one at a time, 4 s default, `inPlace: true` for a message that updates, an action for anything undoable.** A screen-level overlay with a `@State` timer stacks under sheets, outlives its screen, and nothing drops it while the bill is up. `TipConversationsScreen.swift:195`; `YouScreen.swift:467-470`; `ToastController.swift:67-73`.
18. **Confirm an irreversible action with a dialog whose confirming button names the outcome in `.destructive` kind beside `.cancel()`; give a reversible action reached by a swipe or a single tap an Undo toast instead.** "OK" or "Yes" makes the user re-read the subtitle to learn what they agreed to, and a dialog on a reversible action is friction that protects nothing. `DialogItem+ProfileChange.swift:65-83`; `AccountSelectionScreen.swift:111-121`; `ArchivedRow.swift:47-53`.
19. **Validate free-form input through the `Validator` family on submit, raise the rejection as a dialog or an inline hint, and submit the validator's `Output`.** Rejecting at the keystroke yells at a half-typed first attempt, and an inline regex drifts from the server's. `UsernameEntryScreen.swift:119-127`; `EnterPhoneScreen.swift:115-116`.
20. **Once a field has shown an error, re-validate on change so the error clears the moment the input is fixed.** Punish late, reward early. `EnterAmountView.swift:99-108`.
21. **Flag any UI that parses, formats or compares money by hand: a keypad string parses only through `AmountValidator`, a money string comes only from `FiatAmount.formatted(...)`, affordability goes only through `Session.hasSufficientFunds(for:)`.** The UI is where the hand-rolled compare sneaks in; two real-money bugs shipped that way on 2026-07-08. `EnterAmountView.swift:100`; `DialogItem+Username.swift:29`; `GiveViewModel.swift:76`.
22. **Change the words when you change the color.** `textError` alone is invisible to a colorblind user. `EnterPhoneScreen.swift:115-116`.
23. **Write each piece of copy as one complete literal in `Text("...")` or `String(localized:comment:)`; never assemble a sentence from fragments or `Text(verbatim:)`.** The repo has no strings catalog, so the literal is the key SwiftUI exports, and a fragment or a `== 1 ? "Contact" : "Contacts"` branch cannot be translated. A FlipcashUI component that shows copy takes `LocalizedStringKey` or `LocalizedStringResource`, never `String`, so its callers' literals stay keys. `HomeTab.swift:55-58`.
24. **Label a button with its outcome: "Add Money", "Join Chat", "Next" on a setup step, "Save" on an edit; never "Submit", and "OK" only to acknowledge.** The label is the only place the user learns what the tap does. `UsernameEntryScreen.swift:81`.
25. **Title an error with what failed and subtitle it with the fix; raise a rejection the user can fix by typing as gray `.info`, and keep red `.error` for a failure that is nobody's fault.** The red banner also fires an analytics event, so a too-short handle must not count as a failure. `DialogItem+Username.swift:15-21,44-47`.
26. **Ship no placeholder copy, `print(`, ungated `#if DEBUG` UI, or `TODO` on a user path.** Lorem inside `#Preview` is fine; anywhere else it is on screen. `ExpandableText.swift:164` (preview only); `FlipcashApp.swift:64-73` (DEBUG sandbox gated by a launch argument).
27. **Never use an emoji as an icon; use an asset or an SF Symbol.** Emoji render differently per OS version and ignore `foregroundStyle`; the app's copy has zero today. `TipConversationsScreen.swift:242` (`Image.system(.plus)`).

## The states checklist

| State | What must be true | How to see it |
|---|---|---|
| Empty, first run | Headline, one line, next action; fills the populated box; gated on loaded | `#Preview` with `.injectingEnvironment(from: .mock)` and empty arrays; a fresh account on device |
| Empty, no results | `SearchResultsUnavailableView` names the query | Type `zzzq` into the search field |
| Empty, filtered | One line naming the filter (`No Unread Chats`); no headline or action; the list stays mounted | Select a filter with nothing in it |
| Loading, first | Skeleton rows after 300 ms; no centered spinner; no empty flash | Network Link Conditioner "100% Loss", then "3G"; Simulator Debug > Slow Animations |
| Loading, refresh | Rows stay; a footer `ProgressView` only | Open with a warm cache, pull to refresh |
| Failed | Message plus retry; the retry refetches | Airplane mode, open the screen, restore Wi-Fi, tap retry |
| Populated | Real data at its widest; nothing truncates without a `.truncationMode` | The longest real display name, group title and address |
| Long content | `.lineLimit` + `.truncationMode`; `ExpandableText` for body; amounts scale | Preview with a 90-character name and a 44-character address |
| Dynamic Type | Nothing clips; `.fixedSize(horizontal: false, vertical: true)` on multi-line text | `.environment(\.dynamicTypeSize, .accessibility5)` (precedent `LinkUserCardView+Previews.swift:202`); Settings > Accessibility > Larger Text on device |
| In flight | Field locked, button `.loading`, one request on a double tap | Network Link Conditioner "Very Bad Network"; double-tap the button |
| Success | `.success` checkmark held 500 ms, then navigation | Watch the button after a submit with Slow Animations on |
| First paint | The first frame shows the stored value, never a default that corrects | Force-quit, cold launch, screen-record at 120 Hz, scrub to frame 1 |
| Covered | A toast dispatched under a sheet, dialog or the bill is dropped, not queued | Present a sheet, trigger the toast, dismiss the sheet |

## Flipcash voice

Inferred from the literals in `Flipcash/`; no strings catalog exists, so the literal plus its path is the key. Where the house differs from generic advice, the house wins.

- Casing: Title Case for navigation titles, dialog titles, empty-state headlines and buttons; sentence case for subtitles, hints, toasts and placeholders. `"Verify Phone Number"` (`navigationTitle`, five screens); `"No Chats Yet"` (`TipConversationsScreen.swift:266`); `"Chat archived"` (`ArchivedRow.swift:49`). Drift to flag: `"No activity yet"` (`ActivityHistoryScreen.swift:45`) and `"No archived chats"` (`ArchivedChatsScreen.swift:22`) are single-line sentence-case empties with no next action.
- Person and tone: second person, plain, no exclamation marks; contractions with straight apostrophes ("Couldn't", "Isn't", "You're"); the real "…" character (12 uses, zero "..."). The app says "we" only inside a failure subtitle: `"We couldn't create your account. Please try again."` (`OnboardingViewModel.swift:150`).
- Errors: the title names what failed, the subtitle names the fix as an imperative. `"Couldn't Save Your Username"` / `"Try again"` (`DialogItem+Username.swift:21`); the catch-all `"Something Went Wrong"` / `"Please try again later"` (32 sites, `Session.swift:1235`). "Please" is the house's choice in a recovery subtitle only, as in `"Please check your connection and try again"` (`DialogItem+Username.swift:130`); never in a title or on a button.
- Rejections the user can fix are gray `.info` with the rule in the subtitle: `"Too Short"` / `"Usernames must be a minimum of \(UsernameValidator.minimumLength) characters"` (`DialogItem+Username.swift:50-53`). Money in copy is formatted, never typed: `"\(amount) Minimum Balance Required"` with `minimum.formatted(minimumFractionDigits: 0)` (`DialogItem+Username.swift:29-32`).
- Confirmation: the title is the action as a question (`"Change Username?"`, `"Remove Account?"`) or `"Are You Sure?"` with the consequence in the subtitle (`"Withdrawals are irreversible and cannot be undone once initiated"`, `WithdrawViewModel.swift:370-376`); the confirming button names the outcome in `.destructive` (`"Yes, Withdraw"`, `"Remove"`, `"Change Username"`); the second is `.cancel()` or `"Not Now"`. Bare `.destructive("Yes")` at `Session.swift:1466` is the outlier.
- Acknowledgement: one `"OK"` (`DialogAction.okay`) is the house default on an error dialog with nothing to choose. Buttons otherwise name the outcome: `"Add Money"`, `"Join Chat"`, `"Connect Your Phantom Wallet"`; `"Next"` on a setup step and `"Save"` on an edit (`UsernameEntryScreen.swift:81`).
- Empty states and toasts: a headline plus one sentence that points at the next action, `"Start a new chat, or share your profile"` (`TipConversationsScreen.swift:271`); a toast is a past-tense statement plus a one-word action, `"Chat archived"` / `"Undo"` (`ArchivedRow.swift:47-53`).
- Punctuation: a one-sentence subtitle or hint carries no period, `"This is how you'll be uniquely identified on the platform"` (`UsernameEntryScreen.swift:73`); two sentences get periods, `"Couldn't get a fresh rate. Please try again."` (seven sites).

## Flag on sight

- `if is… { ProgressView() } else { Text(` inside a `.buttonStyle(.filled)` label (R16). Live today: `PhantomEducationScreen.swift:49`, `CurrencyCreationWizardScreen.swift:746`.
- `.overlay(` + `Text(` + `Task.sleep` or `asyncAfter` toast in a screen; a `@State private var showToast` (R17).
- `ProgressView()` as a list's whole loading branch; `Spacer()` or `EmptyView()` as its whole empty branch (R3, R5).
- `if items.isEmpty {` with no loaded or loading flag in the condition (R2).
- `@State private var items: [T] = []` filled by `.task` on a screen whose store already has rows (R8).
- `router.present(` on the line after a view-model call that can block, with no `if` around it (R9).
- `.dialog(item:)` bound to the same item from a sheet and its parent (R10).
- A `Button` whose action awaits a network call with no `.disabled(` tied to the in-flight state (R15).
- `Decimal(string:`, `Double(`, or `NumberFormatter().number(from:` on a keypad string; `"$\(`, `String(format: "%.2f"`, or `.value >=` on money (R21).
- `.lineLimit(1)` on a user string with no `.truncationMode`; a fixed `.frame(width:` on a `Text` (R11, R13).
- `Button("Submit"`, `Button("OK"` offered as a choice, `.destructive("Yes")` with nothing after it, a destructive `.alert` whose only button is "OK" (R18, R24).
- `"Oops"`, `"Error"`, `"Invalid input"`, or a new `"Something Went Wrong"` where the failure has a name (R25).
- A `navigationTitle` or dialog title in sentence case; a subtitle or toast in Title Case (voice).
- `== 1 ? "` pluralization (write `"^[\(count) Contact](inflect: true)"`), `Text(verbatim:`, `Text("\(a) ") + Text(b)` (R23). Live today: `DialogItem+CashFlows.swift:17`.
- `Text("Lorem`, `"John Doe"`, `"test@"`, `"TODO"` outside a `#Preview`; `print(` in a `View`; `#if DEBUG` UI with no launch-argument gate (R26).
- An emoji character inside `Text("` (R27).
- `textError` applied with the same words as the normal state (R22).

## Before / After / Why

| Before | After | Why |
|---|---|---|
| `Button(action: save) { if isSaving { ProgressView() } else { Text("Save") } }.buttonStyle(.filled)` | `Button(action: save) { ButtonStateLabel("Save", state: buttonState) }.buttonStyle(.filled).disabled(!buttonState.isNormal)`, with `buttonState = .success` held 500 ms before `dismiss()` | The checkmark is how the app confirms a completed action; a hand-rolled spinner skips it and leaves the button tappable mid-request (R15, R16). |
| `if chats.isEmpty { Spacer() } else { List { ... } }` | `if chats.isEmpty && hasLoaded { NoChatsView() } else { List { ... } }`, where `NoChatsView` is an icon, `"No Chats Yet"`, `"Start a new chat, or share your profile"`, `.frame(maxWidth: .infinity, maxHeight: .infinity)` | A new account's first screen teaches the next action and never flashes "empty" before the fetch lands (R2, R3). |
| `.alert("Delete?", isPresented: $confirm) { Button("OK") { remove() } }` | `dialog = .alert(title: "Remove Account?", subtitle: "Make sure you have a backup of your Access Key before removing this account.") { .destructive("Remove") { remove() }; .cancel() }` | The confirming button names the outcome and the subtitle names the cost; "OK" names neither (R18, voice). |

## Needs a device

- Airplane mode after a list has loaded, then open each data-driven screen: a message and a working retry, never an endless spinner or a blank.
- Network Link Conditioner "Very Bad Network" on a submit: field locked, spinner, checkmark, one request on a double tap, button re-enabled after a failure.
- AX5 text (Settings > Accessibility > Display & Text Size > Larger Text, slider to the end): nothing clips or overlaps. The UIKit chat transcript uses fixed-size `UIFont.default` and will not scale; note it as a finding, do not fix it in a design PR.
- The longest real display name, group title, currency name and wallet address in the row, the title bar and the dialog title.
- VoiceOver: an inline error is read right after its field; a toast is announced (`ToastController.swift:72`); a dialog reads its title before its buttons.
- Cold launch after a force quit with a warm cache, screen-recorded: the first frame shows the selected currency and the stored rows, not USD and an empty list.
- A toast fired while a sheet, a dialog or the bill is up is dropped: not shown under it, not replayed after.
- The 500 ms success checkmark on a real round trip: visible, or lost behind the navigation push.
