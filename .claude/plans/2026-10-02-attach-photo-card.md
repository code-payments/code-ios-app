# Attach flow: inline photo card and Add → chip shrink

Target: a screen recording of ChatGPT's iOS attach flow (2026-10-02). A second pass the same day
(`6413eefd`, `1da4c9a6`, `ea099222`) matched the card geometry, panel anchoring, back-to-menu,
camera controls, and All Photos to the recording.

## Decisions

- **With the keyboard up, the panel and cards draw over the keys; the composer keeps focus.** An
  earlier note here said the keyboard is out of process and nothing can draw over it. That was wrong:
  the spike's public window was clamped to 10,000,000 (the cap on app window levels), one below the
  keyboard's. The keyboard is in-process, in a `UIRemoteKeyboardWindow` at level 10,000,001 inside a
  private keyboard scene, left out of `UIApplication.windows` and every scene's `windows`. A second
  spike (iOS 27.2 device, iOS 26.6 device, iOS 27.0 simulator) reached it through the private
  `+[UIWindow allWindowsIncludingInternalWindows:onlyVisibleWindows:]`: a subview there draws over
  the keys, a `UIGlassEffect` blurs them, and the field stays first responder. A full-screen
  container there whose `hitTest` returns nil outside one rect passed a real-touch probe (iOS 27.0
  simulator, 2026-10-02): the rect takes taps above and over the keys, the app window takes taps
  outside it with focus kept, and uncovered keys still type. `keyboardWindow.convert(_:from:
  appWindow)` returns an infinite rect, since the windows are in different scenes; convert through
  the screen's coordinate space.
  - **Mechanism.** `KeyboardOverlayHost` is the only code touching private API: it resolves the
    selector with `NSSelectorFromString` after `responds(to:)`, matches the window by a class-name
    fragment, and returns nil on any miss. `AttachKeyboardOverlay` hosts the same `AttachSurface`
    the bar uses in a full-screen `AttachOverlayContainer` in that window, in the app window's
    coordinates (both windows sit at the screen origin), taking touches only on the panel and card
    frames. The menu is centred on the composer's bottom edge so its lower half sits over the keys
    (sheet_02, `.straddlesPlus`), growing out of `+`; cards stand on the screen's bottom.
  - **Rebuilds and teardown.** UIKit rebuilds the keyboard tree on focus or keyboard-type changes.
    The container re-finds its window on `didMoveToWindow(nil)` and on keyboard did-show /
    did-change-frame. It comes down when nothing is left in it, and at once on keyboard will-hide,
    focus loss, or backgrounding. The app is portrait-only, so rotation needs nothing.
  - **Cross-window hand-off.** The landing chip lives in the app window, so no shared namespace. On
    Add/capture the chip is staged hidden, reports its window frame, and the card shrinks onto a
    clear stand-in at that frame in the overlay's namespace; then the chip fades in. All Photos
    can't present from the keyboard's window, so it hands the card to the keyboard-down flow, which
    opens the full picker.
  - **Risk.** Private API: Apple can rename the class or drop the selector in any release, and App
    Review may flag the selector string (it's assembled from parts, never one literal). Every miss
    falls back, never traps.
  - **Fallback.** `AttachOverlayMode.select` picks at runtime and logs the mode: (a) keyboard window;
    (b) a `UIInputView(.keyboard)` of the keyboard's height swapped in as the field's `inputView`,
    with the overlay laid in that input view's window — the swap is not animated by the system and a
    live inputView ignores height changes, so it matches the height exactly; (c) take the keyboard
    down first, as before. A keyboard shorter than 150pt (hardware keyboard's shortcut bar) goes to
    (c). `AttachCard.closesOnKeyboardShow` is off while over the keyboard, since the (b) swap posts
    keyboard-show. `begin()` turns it off before the swap, so the gate holds by construction rather
    than because no card happens to be open yet.
- **Cards are a fixed-proportion overlay, not a keyboard-height slot.** `AttachCard` (was
  `ChatKeyboardSlot`) sizes the card to 58% of the screen height when it opens. It is an `.overlay`
  on the composer row, bottom-aligned to the row's bottom edge, out to the keyboard-up margins
  (`-compactExtraInset`). The bar's measured height stays the composer's, so the transcript doesn't
  move. The overlay is attached after the row's `opacity`/`allowsHitTesting`, or the card would
  inherit them.
- **The card rides the bar-overflow path with a touch band.** `ConversationBarModel.overflow` is
  `.none`, `.everywhere` (panel: every touch above the bar goes to the bar, so an outside tap
  dismisses), or `.band(top:)` (card: touches from the card's window-space top edge down).
  `BarOverflowReporting` hands it to `ChatScreenViewController.barOverflowTouchTop` /
  `barOverflowsTop`; `BarClipView.point(inside:)` limits the overflow region to the band. The card's
  top is measured with `onGeometryChange(.global)`, not computed from bar padding.
  `AttachPanelPlacementTests` uses the same modifier.
- **One surface, not a panel and a card.** (2026-10-03, after a device recording showed a
  card-sized glass rectangle with the menu rows fading over it on Back: the panel and the card were
  two views joined by `matchedGeometryEffect`, and both were on screen mid-morph.) `AttachSurface`
  draws one glass shape. `AttachSurfaceFrame` animates its rect and corner radius as one
  `Animatable` value, so the clip and the glass can't drift apart. The phase
  (`ConversationBarModel.attachSurfacePhase`: collapsed / menu / card / landing) picks the shape
  through `AttachSurfaceLayout.shape(for:…)`; the host passes `+`'s, the card's, and the landing
  chip's rects in its own coordinates. The bar and the keyboard overlay draw the same view, with
  `.standsOnPlus` / `.straddlesPlus` as the only difference in where the menu sits. Content layers
  sit at their resting frames inside the moving clip and cross-fade: the leaving side on
  `attachContentOut` (fast, early), the arriving side on `attachContentIn` (late).
- **Menu stands on the composer's bottom edge, keyboard down.** It is 240pt wide from `+`'s left
  edge, so it grows up and right over the field and leaves the send button clear. The card stands on
  the same edge.
- **Back is the forward morph reversed.** `returnToMenu()` closes the card and opens the panel in
  one `withAnimation`; the phase goes card → menu, the shape springs back, and the photo selection
  resets. Only Add and the shutter call `focusComposer()`.
- **Add and the shutter land the surface on the chip.** `closeCard` stages the chip and calls
  `AttachCard.beginLanding(chipID:)`; the strip reports the chip's window frame through
  `landingChipDidLayout`, and the surface springs onto it in the `.landing` phase, staying drawn the
  whole way. `endLanding()` runs without animation, so the chip replaces the surface in one frame
  (with a fade, the chip showed ~350ms after the card went). `matchedGeometryEffect` is gone from
  the strip; the chip only carries `landingChipID`.
- **Camera row: back, shutter, "…".** "…" (with a blue dot) unfolds flash and flip above itself and
  turns into ×. The flash is off/on, resolved per shot against `output.supportedFlashModes`.
  Setting a mode the output lacks raises an exception, and a flip changes what it supports.
  ChatGPT's "Scan" is out of scope: there is no document-scan feature.
- **All Photos opens the system sheet.** With `.photosPickerAccessoryVisibility(.visible, edges:
  .top)` the inline picker shows a prompt, a Photos/Collections switch, and the privacy banner, about
  40% of the card. Nothing outside the picker can switch it to Collections. So the accessory stays
  hidden, and All Photos (shown while nothing is selected, cross-fading with Add) presents
  `.photosPicker(isPresented:)` bound to the same selection.
- **Photos opens an inline card, not the system sheet.** `PhotosPicker` with
  `.photosPickerStyle(.inline)` (iOS 17+, target is 18.0) is out of process and needs no photo
  library permission, so the spec's reason for rejecting an inline grid (full library access)
  doesn't apply on iOS. The "Private Access to Photos" notice in the recording is the picker's own.
  This is an iOS-only departure from the cross-platform spec; Android keeps the system Photo Picker.

## What the recording shows

1. Tapping Photos: the panel grows into a rounded card while its rows blur out and the picker fades
   in. The card spans from just under the transcript to the bottom of the screen, covering both the
   composer row and the keyboard. The transcript stays visible above it.
2. In the card: the picker grid, a back chevron bottom-leading, and — once something is selected —
   a blue "Add N photo" pill bottom-trailing. System chrome is hidden.
3. Tapping Add: the card collapses, the keyboard rises, and the photo shrinks into a chip at the top
   of the composer, which grows to hold it.

## Constraints

- The picker is a remote view: no `matchedGeometryEffect` on it, and no way to find the selected
  cell's frame. Morph a card container; the shrink starts from the card's bounds.
- Inline selection updates live, so staging moves from "selection changed" to the Add tap.
- The shrink draws the real image, so load thumbnails as the selection changes, not at Add.
- One card mechanism for camera and photos: `AttachCard`.
- With N > 1 photos the recording shows nothing; the first chip takes the shrink and the rest use the
  existing chip insert transition.
- Reduce Motion: with one surface there are not two views to cross-fade, so the shape's change
  runs without animation (`AttachMotion.animatesGeometry` is false) and only the content and the
  surface's opacity fade.

## Content mounted with the surface

- **Photos:** the surface's one inline `PhotosPicker` mounts, hidden and at the card's size, from the
  surface's first frame, so the morph never relays it out and warming is the real instance.
  `PhotosPickerWarmer` (a second hidden picker) and the 0.5s `Task.sleep` before mounting are gone.
  Selection, preloader, and the All Photos flag live in `AttachPhotosPick` on the model, reset on
  Back and when the surface unmounts without a choice. Add hands the preloader to staging and swaps
  in a fresh one, so the in-flight loads aren't cancelled.
- **Camera:** the preview mounts with the surface only when access is already `.authorized`;
  otherwise it mounts when its card opens, which asks. `AttachWarmUp` starts the session while the
  open panel offers Camera or the camera card shows, and stops it when the panel closes.
  `ChatPhotoCamera.isRunning` is observable.
- **Readiness:** `AttachPanel.select(_:warmUp:…)` opens a card through `AttachWarmUp.whenReady`, which
  waits at most 150ms. The camera is ready once running. The remote picker has no ready signal, so
  Photos counts as ready once the picker has been mounted for `pickerLead` (300ms).
- **Measured (iOS 27 simulator, 2026-10-03, `simctl recordVideo`, 60fps frame scan for a coloured
  morph marker and the grid's saturated pixels):** the morph runs 0.317s. With the extension already
  started in the process, the grid is in the card ~0.1s before the morph ends (three opens: two with
  the keyboard up, one down). The first open in a fresh process shows the grid 0.63s after the
  morph ends, ~2.2s after the hidden mount: the out-of-process extension's cold start, which no
  readiness wait inside 150ms can cover. The simulator has no camera ("Camera unavailable" is in the
  card at morph end), so camera first-frame time is unmeasured.
