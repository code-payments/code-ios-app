---
name: design-spec
description: Turn a product idea or rough brief into a Figma spec that looks like the shipped Flipcash app — composed from the published component library and the House Standard, with every custom piece flagged as a proposal for Aiden and a spec note the dev can implement from. Use when someone says "spec this", "design this screen", "design this flow", "mock this up in Figma", "make a Figma for", "what would this look like", or pastes a feature idea that needs a screen. Draft until the Components – Flipcash library is published and complete.
argument-hint: "<what the screen or flow does, for whom, and where in the app it starts>"
---

# Design spec

You are drafting a screen or flow for Flipcash in Figma, in the house's own materials, so the result
reads as a room in the same house and the dev can implement it from library components. You are not
inventing a visual language; the House Standard and the library are the language. Where they are
silent, you propose and flag. Aiden decides.

## Load first

0. `.claude/docs/design/figma-screens.md`: the Screen Kit. Every frame is an instance of `Screen/iOS` or
   `Screen/Android`, filled through its slots, with the component ids, tokens, modes and the recipe. Where it
   conflicts with older guidance below (dark only, radii 6/12), the Screen Kit wins: it reflects the 2026-10-16
   direction.
1. `.claude/docs/design/design-standard.md`: what Flipcash is, the principles, the patterns.
2. `.claude/docs/design/components.md`: every component, when to use it, what to use instead.
3. `.claude/docs/design/lenses/layout-and-hierarchy.md` and `lenses/states-and-copy.md`.
4. The Figma library. Load the `figma:figma-use` skill, then `get_libraries` and
   `search_design_system` for "Components – Flipcash". Only published components and variables are
   available to this spec; anything else is "not available" and goes in the ⚠︎ list.
5. The screens in the main design file nearest to the job (search by screen name), so the new screen
   matches its neighbours.

## Procedure

### 1. Name the job, before any frame

Write three lines and show them: who is on this screen and what just happened; what they must do or
learn here; what they do next. If the brief does not answer these, ask one question, with a
recommended answer.

### 2. Pick the pattern

From the standard's Patterns: a push step, a sheet task, a partial-sheet choice, a dialog, a toast;
amount entry; confirmation; a list of rows; an empty state. Name the pattern and the closest existing
screen (the precedent). A flow is a sequence of patterns, one frame each.

### 3. Compose from the library

Start from a Screen instance (`figma-screens.md` §1) and put chrome in its Top bar and Bottom bar slots. Never
draw a device frame, status bar, home indicator, gesture bar or nav bar. Then apply this tree to every element,
top down:

```
Does a library component do this job?
├── as-is → place an instance, done
├── with an existing variant or property → set it
├── needs a variant that doesn't exist → use the closest; name the layer "⚠︎ needs variant: <what>"
└── nothing in the library does this
    ├── the app has a precedent (the main file, or the catalog's hand-rolled list)
    │     → compose from primitives the way the precedent does; name the group after it
    └── genuinely new → tokens only; name the group "⚠︎ custom — proposal: <name>";
          list what it would need to become a component
```

Tokens only: colour from the `v2/Color` variables, and type and radii from `v2/Platform`
(`figma-screens.md` §4). Use 16 pt gutters and one `.filled` primary per screen. No new colours, no new type
sizes, no gradients, no glass over a flat fill, no emoji as icons, and only Central icons.

### 4. Cover the states

Duplicate the frame for empty, loading, error, and long content (the longest real name and a two-line
title); for an amount screen, the insufficient-funds case too. A state you cannot design is an open
question, not a missing frame.

### 5. Write the spec note

In the frame description and in your reply: components used by code name
(`Buttons/Button style=filled` → `.buttonStyle(.filled)`), tokens, states covered, the final copy
in the house voice from the states-and-copy lens (Title Case for titles and buttons, sentence case
for subtitles, hints and toasts; buttons name the outcome), motion by preset name from the
vocabulary or "none", the ⚠︎ list, and open questions for Aiden. The dev builds from this note; if it
needs anything outside the library, the note says so.

### 6. Self-critique

Run `/critique <figma-url>` (the design critic with the frame's screenshot and design context). Fix
Blocking and Should fix in the frame; leave Taste calls in the note for Aiden.

## Hard rules

- Never invent a component when the catalog has one. Never detach or restyle a library component to
  make it fit; flag the gap instead.
- Design both appearances: a dark frame sets two modes on the Screen instance (see `figma-screens.md` §4).
  Never introduce a new colour, a new type size, a gradient, or decoration that does no work.
- Never finalise copy that moves money without the exact words of a precedent; flag it.
- One primary action per screen. Money is the largest text on a money screen.
- Every ⚠︎ is a proposal for Aiden, not a decision. The spec is done when the dev can build it from
  library components plus the ⚠︎ list.

## Output

The Figma link or links, the spec note, and three lines: the pattern and its precedent; library
instances versus ⚠︎ items; open questions.
