---
name: critique
description: Review a UI, motion, or copy change against the House Standard through the design critic — a PR number, a branch, a screen name, a Figma frame, or the current diff — and report ranked findings, the taste calls that belong to Aiden, and what was checked and found sound. Use when someone says "critique", "design review", "does this look right", "review this against the standard", "check this screen", before marking a design PR ready, or when a walkthrough needs an area judged.
argument-hint: "[<PR#> | <branch> | <ScreenName> | <figma-url> | this]"
---

# Critique

The deliverable is one review from the `design-critic` agent, printed in chat, plus an offer to post
it where it belongs. This skill never edits code and never posts without an explicit yes.

## 1. Resolve the target

Repo: the remote that points at `code-payments/code-ios-app` (`git remote -v`). Main is that remote's
`main` (`upstream/main` on a fork, `origin/main` in the client's checkout).

| Argument | Bundle for the critic |
|---|---|
| `<PR#>` | `gh pr view <n> -R code-payments/code-ios-app --json title,body,baseRefName,headRefName,files` and `gh pr diff <n> -R code-payments/code-ios-app`. No checkout needed; the critic reads changed files from the diff plus the current tree for context. |
| `<branch>` | `git diff $(git merge-base <branch> <main>)...<branch>` and the changed-file list. |
| `<ScreenName>` | Run the `design-surveyor` first; the critic gets the surveyor's document and the file list. |
| `<figma-url>` | Load `figma:figma-design-to-code` (the prerequisite), then `get_screenshot` and `get_design_context` for the node. The critic judges the frame against the standard and `components.md`: library components used versus invented. |
| `this` or nothing | The working tree: `git diff`, `git diff --cached`, and untracked Swift files, against the branch's base. |

Attach any screenshots or recordings the user gave (paths), and one line stating what the change
claims to do (the PR title and body, or the user's words).

## 2. Pick the lenses

Name them in the brief:

- `motion.md` when the diff touches `withAnimation`, `.spring(`, `.transition(`, `ChatMotion`,
  `UIView.animate`, `CASpringAnimation`, or `matchedGeometryEffect`.
- `layout-and-hierarchy.md` for any change under `Flipcash/Core/Screens` or
  `FlipcashUI/Sources/FlipcashUI/Views`.
- `states-and-copy.md` for a new screen or flow, a `Loadable`, a `ButtonState`, a toast, a dialog,
  or any string change.
- A Figma frame gets the layout and states lenses.

## 3. Run the critic

One `design-critic` agent with the bundle, the lens list, and the claim. For a PR that touches more
than eight screens, split by screen folder, run the agents in parallel, then merge their sections,
keeping every finding's `path:line` and de-duplicating Checked sound.

## 4. Report

Print the critic's review as written; its headings are the contract. Then one line per action
available:

- **A PR:** "Post this as a comment on #n?" On an explicit yes, write the review to a temp file and
  run `gh pr comment <n> -R code-payments/code-ios-app --body-file <tmp>`, with a first line
  `Design critique against the House Standard (.claude/docs/design/design-standard.md)`. Never post
  without the yes.
- **Your own branch before "ship it":** fold Blocking and Should fix into the work; list Taste calls
  for Aiden in the PR body as "decided by Aiden: …" once he has.
- **Standard gaps:** offer to append them to `.claude/docs/design/design-decisions.md` as open items.

## Hard rules

- No edits to source, tests, or config from this skill.
- No comment, review, or state change on GitHub without an explicit yes in chat.
- The critic's verdict is reported as written. Do not soften "Blocked".
