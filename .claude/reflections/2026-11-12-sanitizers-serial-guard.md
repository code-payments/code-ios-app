# 2026-11-12 - Sanitizers plan "fixed" after 6 green runs, still parallel (fix/tsan-test-stall)

## What happened
The Sanitizers plan failed on 45-60s main-actor stalls. Setting `FlipcashTests` to
`"parallelizable": false` gave 6 of 6 green runs, and the outcome was written up as done. Two
more runs then failed. `FlipcashCoreTests` had no `parallelizable` key and still ran in
parallel. A 5ms wall-clock perf assertion (`Regression_6a008a1`) tipped over under TSan. And a
real `ConversationStore` bug showed up: a feed requested before a streamed roster update rolled
`rosterSummary.version` back, so `ConversationMembershipTests` waited its full 90s.

## The misstep
The guard test only rejected `parallelizable == true`. A missing key means parallel, so the
guard passed while the second target stayed parallel. Six passes of a gate whose baseline was
2 of 8 was read as proof; with failures spread over many tests, a short streak proves little.

## Resolution
Both targets now set `false`, and `SanitizersPlanTests` requires `== false`. The perf test
compares against one key derivation timed in the same run. `ConversationStore` keeps a newer
stored roster summary across feed merges (`ConversationRosterTests.olderFeedKeepsNewerRosterSummary`).

## Lesson
A config guard asserts the required value explicitly, never the absence of the bad one, because
defaults are invisible. Don't call a flaky gate fixed from a short green streak. Check every
target's effective setting in the log (e.g. interleaved starts) before counting runs.

## Landed on
Check: `FlipcashTests/SanitizersPlanTests.swift` (requires `parallelizable == false` on every target).
