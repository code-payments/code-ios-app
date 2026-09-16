# Rewriting `fastlane release`'s App Review submission (2026-09-16)

Resubmitting 2026.9.1 exposed two defects in the `release` lane, and the fix
turned up a third. The lane now drives the App Store Connect `reviewSubmissions`
flow itself instead of delegating the submit to `deliver`.

## What was broken

**1. The submit failed on a retired endpoint.** The resubmit died with
`Spaceship::AccessForbiddenError: The resource 'appStoreVersionSubmissions' does
not allow 'CREATE'. Allowed operation is: DELETE`. Apple has retired that
endpoint in favour of `reviewSubmissions`.

The brief attributed the CREATE call to `deliver`'s internals. That does not hold
for the pinned fastlane (2.227.2): its `deliver/lib/deliver/submit_for_review.rb`
already uses `create_review_submission` /
`add_app_store_version_to_review_items` / `submit_for_review`, and nothing under
`fastlane/` calls `create_app_store_version_submission` at all — the method
exists only on the spaceship model. So the observed error came from something
other than the pinned deliver path (an older fastlane on the machine that ran it
is the obvious candidate) and could not be reproduced here. The rewrite still
stands on its own: the submission logic, the in-flight guard and the release
settings are now stated in the lane, where a failed release is actually read.

**2. A resubmit silently destroyed real release notes.** `release_notes`
defaulted to `default_release_notes` and `set_whats_new` wrote it
unconditionally, before the submit. Running the lane without `notes:` on a
version that already had notes replaced them with "Bug fixes and performance
improvements." — and then failed at the submit, leaving the version with
placeholder notes and no submission.

**3. `phased:` and release-after-approval were inert.** `deliver` applies
`automatic_release:` and `phased_release:` from `upload_metadata`, which
`return`s immediately under `skip_metadata: true`. The lane passed
`skip_metadata: true`, so neither setting ever reached App Store Connect,
despite `phased:` being an advertised flag. Related: `select_build` lives only in
`Deliver::SubmitForReview`, so the first `deliver(submit_for_review: false)`
never attached the build it was handed `build_number:` for.

## What the lane does now

`deliver` is left with one job — create or select the editable version for
`version`. Everything after that is spaceship in the lane:

- `set_whats_new` fills `whatsNew` only when it is empty, unless `notes:` was
  passed. Review submission rejects an empty `whatsNew`, which is why the notes
  are set here at all (deliver skips them under `skip_metadata`).
- `set_release_behavior` sets `releaseType: AFTER_APPROVAL` and creates or
  deletes the phased release directly. **This is a live behaviour change:**
  phased release and release-after-approval are now actually configured, where
  before they were silently dropped.
- `submit_to_app_review` guards that the editable version is the one asked for,
  refuses when `get_in_progress_review_submission` returns anything, attaches the
  build (version-filtered `Build.all`, VALID + export compliance checked), reuses
  a `READY_FOR_REVIEW` submission rather than opening a second one, adds the
  version unless it is already among the submission's items, waits for the
  version to leave `PREPARE_FOR_SUBMISSION`, then submits.
- `dry_run:true` reports all of the above and writes nothing.

## Why spaceship rather than shelling out to `asc`

`asc review submit` implements the same flow and worked by hand, but using it
from the lane adds a machine dependency to the release path and a second
credential path (raw PEM in `ASC_PRIVATE_KEY` plus `ASC_BYPASS_KEYCHAIN=1`,
alongside the base64 `ASC_KEY_CONTENT` spaceship already reads). The lane speaks
spaceship everywhere else, and the guards stay reviewable in-repo.

## Verification

Read-only only — nothing was submitted. `fastlane release version:2026.9.1
dry_run:true` against the live API reported: editable version 2026.9.1
(WAITING_FOR_REVIEW), attached build 540, What's New kept as-is (1429 bytes),
would submit build 540 (VALID), and review submission
`8133ffd5-a4e7-498a-9135-282bb0e6838f` in flight — a real run would refuse.
`asc review submit --dry-run` agreed (`alreadySubmitted: true`). The write paths
— `set_release_behavior`, `select_build`, `submit_for_review` — have not run
against App Store Connect, so the first real submission is the proof.

## Loose end

`latest_build(app, build_number)`, used by `distribute`, calls `Build.all(...,
limit: 1)` with no version filter, and spaceship's `all_pages` follows `next`
links — so it can page through every build one request at a time. Not touched
here.
