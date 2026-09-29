# Chat: custom long-press menu (WhatsApp-style lift)

## Goal
Long-pressing a bubble slides **that bubble** (not the transcript) to a spot with the reaction strip
above it and the menu below it, then slides it back into its row as the same bubble. The transcript
behind stays still and blurred.

## Why UIKit's context menu can't do it
Findings from the 2026-09-28/29 device investigation (bmc-iphone):
- **Targeted preview (in-place lift):** UIKit picks the menu's side and places the lift itself. There's
  no public way to force the menu below. A bubble near the bottom always gets the menu above.
- **Transcript pre-scroll before the lift:** UIKit still put the menu above after a 20pt scroll. It
  appears to pick the side with more room, not the one that fits. The scroll back on dismiss also
  raced the fly-home and showed the bubble twice.
- **`previewProvider` controller:** UIKit does move only the bubble and puts the menu below. But the
  preview is a copy (image) cross-faded in and out, so it looks different from the live bubble and
  doesn't slide home as the same view. `snapshotView` copies go blank because UIKit hides the source.
  UIKit also draws the preview through a portal, so its frame has to be found by size on screen.
- **Inset mode:** never switch `contentInsetAdjustmentBehavior` while the menu is up. `.never` changes
  the safe area handed to rows, and SwiftUI-hosted cards under the nav bar (the group invite card)
  re-lay out onto their own pills. Hold the bottom inset instead (`holdBottomInset`, shipped with the
  interim fix).

## Shape
A `ChatMessageMenuOverlay` presented over the screen (a window above the keyboard, like
`reactionStripWindow` today), owned by `ChatScreenViewController`.

1. **Trigger:** replace `UIContextMenuInteraction` on bubbles with a long-press recognizer (0.35s,
   matching the system). The double-tap path (`presentStripOnly`) already does most of this.
2. **Lift:** hide the real bubble, add a live copy at the bubble's exact window frame. Build the copy
   by configuring a fresh cell/bubble view with the same message, not a snapshot, so it stays sharp
   and matches exactly (animations, attachments, fonts).
3. **Placement:** target y puts the strip (`ReactionStripView.height` + `bubbleGap`) above the bubble
   and the menu below it, within the safe area. Tall bubbles: clamp and scale down, as WhatsApp does.
   Keep the bubble's own horizontal position.
4. **Menu:** our own view listing `message.actions` (`MessageCapability`), destructive styling for
   Delete. No system extras (Ask Siri, etc.).
5. **Backdrop:** blur + dim the screen behind, tap to dismiss. Composer and keyboard follow the
   existing `handOffComposerFocusAroundContextMenu` logic.
6. **Dismiss:** animate the copy back to the row's *current* frame (read it again at dismiss time,
   since a pushed transcript may have moved it; `afterContextMenu` queueing still applies), then show
   the real bubble and remove the copy in the same frame.
7. **Haptics:** light impact on lift, selection feedback on menu hover if we support drag-to-select.
8. **Accessibility:** keep `accessibilityCustomActions` on the bubble so VoiceOver users never need
   the overlay. The overlay is a modal container (`accessibilityViewIsModal`) with an escape gesture.

## What goes away
- `UIContextMenuInteraction` delegate methods in `ChatViewController` (config, highlight/dismiss
  previews, `willEndContextMenuInteraction`), `stripRoomPreview`, `liftCopy`, `hiddenLiftSource`.
- `contextMenuFrame(in:titles:)` / `liftedPreviewFrame` view-tree searches in the screen.
- `freezeInset`/`holdBottomInset`, if the overlay keeps the keyboard untouched.

## Tests
- Placement math as a pure function (bubble frame, safe area, strip/menu heights → target frame),
  covered by Swift Testing cases: top, bottom, tall bubble, keyboard up.
- Device check: top card with pills, bottom bubble, tall bubble, keyboard up, transcript push during
  the menu, VoiceOver.

## Android
Check whether Android's menu has the same same-side problem before mirroring.
