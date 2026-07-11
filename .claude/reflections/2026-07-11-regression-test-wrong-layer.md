# 2026-07-11 - Regression Test at the Wrong Layer (6a4f895 → 6a522ee)

## What happened

PR #472 fixed Bugsnag 6a4f895 (chat transcript `NSInternalInconsistencyException`: reconfigure dequeued a different cell class) by folding the cell class into `ChatItem.differenceIdentifier`, and shipped `Regression_6a4f895` as proof. Two days later build 1.14.0 (454) crashed in production with the *same* UIKit assertion — new issue 6a522ee — through code the regression suite covered and kept passing.

## The misstep

The regression test asserted the **diff's shape** (`StagedChangeset` produces delete+insert for a class flip) — the layer the fix changed — not the **crash path** (applying a changeset to a live `UICollectionView`). The actual root cause lived one layer down: the flatten (#453) merged DifferenceKit's update stage (source-coordinate indices) into one `performBatchUpdates` whose `setData` had already advanced to the target array; UIKit resolves `reconfigureItems` synchronously through `cellForItemAt`, so any insert/delete above an updated row handed the reconfigure another row's element. #472 removed one trigger (class flip diffed as update) and left the mechanism.

Three test-design traps compounded it:

- `ChatViewControllerTests.update_receiptMigrationWithInsert_appliesInOneBatch` ran the buggy shape on a live window but asserted only item **counts** — silently wrong content passes. (Its insert also landed *below* the updated row, where indices don't shift.)
- Reading cells through the data-source method (`controller.collectionView(_:cellForItemAt:)`) re-dequeues against current `items` and always looks correct; only `collectionView.cellForItem(at:)` sees the misconfigured on-screen cell.
- Off-window, `reload(using:)` short-circuits to `reloadData` — an unwindowed test never exercises the batch path at all.

## Resolution

The 6a522ee fix applies reconfigures inside the single batch against the update stage's source-shaped data before advancing to the target, and its regression suite (`Regression_6a522ee9fdca5cb0d6f21174`) drives `ChatViewController.update(items:)` on a window-attached controller asserting live cells — observed RED (the literal production exception) before the fix, GREEN after.

## Lesson

A regression test must be observed failing on the unfixed code, and it must fail at the layer the user hit — the crash path — not the layer the fix touched. Assertions derived from the fix's own reasoning prove the reasoning, not the absence of the bug.
