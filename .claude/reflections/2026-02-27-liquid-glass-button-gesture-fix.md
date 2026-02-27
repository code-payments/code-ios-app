# Liquid Glass Button Gesture Fix

**Date:** 2026-02-27

## The Bug

Liquid Glass buttons animated on tap but the action closure never fired on iOS 26.

## Root Cause

`.glassEffect(.regular.interactive())` was applied as a **ViewModifier on the Button view** (via `GlassEffectModifier`). The `.interactive()` modifier adds its own gesture recognizer for press/drag feedback, which — at the same view level as Button's tap gesture — caused gesture exclusivity to swallow taps.

## The Fix

Move `.interactive()` inside a **ButtonStyle** where it's applied to `configuration.label`. SwiftUI's button gesture wraps around the styled label, so both gesture systems coexist: Button owns the tap, `.interactive()` owns the glass animation.

Consolidated two parallel glass implementations (`GlassEffectModifier` + `LiquidGlassButtonStyle`) into a single `LiquidGlassCompatibleButtonStyle` parameterized by shape (`.capsule` / `.circle`).

## Lessons

1. **Understand WHY something is broken before removing it.** `.interactive()` wasn't the problem — its placement was. Removing it fixes the gesture conflict but kills the visual feedback.
2. **ViewModifier vs ButtonStyle matters for gestures.** `.glassEffect(.interactive())` as a ViewModifier on a Button competes with Button's tap gesture. Inside a ButtonStyle's `makeBody` on `configuration.label`, it doesn't.
3. **Don't create private copies of public utilities.** If a shared abstraction exists and is used, rename or refactor it — don't duplicate it as a private struct.
