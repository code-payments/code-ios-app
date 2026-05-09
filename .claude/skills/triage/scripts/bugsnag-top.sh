#!/usr/bin/env bash
# bugsnag-top.sh — fetch the top open production issue from Bugsnag (last 7 days).
# Emits one JSON object to stdout on success.
#
# Exit codes:
#   0  success — issue found, JSON on stdout
#   2  missing/invalid argument or BUGSNAG_TOKEN unset
#   3  token rejected by Bugsnag (401)
#   4  Bugsnag API unreachable after one retry
#   5  no qualifying issues (or --skip exceeds available results)

set -euo pipefail

PROJECT_ID="6824c89e398a98001fdaa7ec"
ORG_SLUG="1000710770-ontario-inc"
PROJECT_SLUG="flipcash-ios"
BROWSER_BASE="https://app.bugsnag.com/$ORG_SLUG/$PROJECT_SLUG/errors"
API_BASE="https://api.bugsnag.com/projects/$PROJECT_ID"

# Resolve repo root: script lives at .claude/skills/triage/scripts/bugsnag-top.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Source .env if BUGSNAG_TOKEN is not already set
if [ -z "${BUGSNAG_TOKEN:-}" ] && [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$REPO_ROOT/.env"
  set +a
fi

if [ -z "${BUGSNAG_TOKEN:-}" ]; then
  echo "BUGSNAG_TOKEN not set. Add to .env or ~/.zshenv." >&2
  exit 2
fi

# Parse --skip <N> | --id <bugsnag_error_id_or_url>
SKIP=0
FORCED_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip)
      SKIP="${2:-}"
      if ! [[ "$SKIP" =~ ^[0-9]+$ ]]; then
        echo "--skip requires a non-negative integer" >&2
        exit 2
      fi
      shift 2
      ;;
    --id)
      FORCED_ID="${2:-}"
      if [ -z "$FORCED_ID" ]; then
        echo "--id requires a Bugsnag error id (24-char hex) or a Bugsnag error URL" >&2
        exit 2
      fi
      # If the user pasted a URL, extract the trailing id
      FORCED_ID="${FORCED_ID##*/}"
      if ! [[ "$FORCED_ID" =~ ^[0-9a-f]{24}$ ]]; then
        echo "--id value '$FORCED_ID' is not a 24-char hex Bugsnag error id" >&2
        exit 2
      fi
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -n "$FORCED_ID" ] && [ "$SKIP" -ne 0 ]; then
  echo "--id and --skip are mutually exclusive. --skip walks the ranked list; --id targets one issue directly." >&2
  exit 2
fi

if [ -n "$FORCED_ID" ]; then
  # Targeted lookup — bypass the filtered query so the user can triage anything
  # (closed, fixed, ignored, non-prod, older than 7d) by id.
  URL="$API_BASE/errors/$FORCED_ID"
else
  # Bugsnag requires URL-encoded bracket characters in filter params
  QUERY="sort=events&direction=desc&per_page=1&offset=$SKIP"
  QUERY="$QUERY&filters%5Berror.status%5D%5B%5D%5Btype%5D=eq"
  QUERY="$QUERY&filters%5Berror.status%5D%5B%5D%5Bvalue%5D=open"
  QUERY="$QUERY&filters%5Brelease_stage%5D%5B%5D%5Btype%5D=eq"
  QUERY="$QUERY&filters%5Brelease_stage%5D%5B%5D%5Bvalue%5D=production"
  QUERY="$QUERY&filters%5Bevent.since%5D%5B%5D%5Btype%5D=eq"
  QUERY="$QUERY&filters%5Bevent.since%5D%5B%5D%5Bvalue%5D=7d"

  URL="$API_BASE/errors?$QUERY"
fi

# Calls $1 (a function name that prints `<body>\n<http_code>`), retries once on
# transient failures, and sets globals HTTP_CODE / BODY for the caller. Caller
# is responsible for HTTP_CODE-specific handling (401, 404, etc).
fetch_with_retry() {
  local fn="$1"
  local raw
  raw=$($fn || echo $'\n0')
  HTTP_CODE=$(printf '%s' "$raw" | tail -n1)
  BODY=$(printf '%s' "$raw" | sed '$d')
  if [ -z "$HTTP_CODE" ] || ! [[ "$HTTP_CODE" =~ ^[0-9]+$ ]] || [ "$HTTP_CODE" -ge 500 ]; then
    sleep 2
    raw=$($fn || echo $'\n0')
    HTTP_CODE=$(printf '%s' "$raw" | tail -n1)
    BODY=$(printf '%s' "$raw" | sed '$d')
  fi
}

# Print a generic "API unreachable" message plus a truncated body for debugging
# unexpected status codes (403, 422, gateway errors, etc.).
report_unreachable_and_exit() {
  local label="$1"
  echo "$label" >&2
  if [ -n "$BODY" ]; then
    echo "Response body (truncated to 500 chars):" >&2
    echo "$BODY" | head -c 500 >&2
    echo >&2
  fi
  exit 4
}

fetch_errors() {
  curl -sS \
    -H "Authorization: token $BUGSNAG_TOKEN" \
    -H "X-Version: 2" \
    -w "\n%{http_code}" \
    "$URL"
}

fetch_with_retry fetch_errors

if [ "$HTTP_CODE" = "401" ]; then
  echo "Bugsnag rejected the token (401). Check it hasn't expired or been revoked." >&2
  exit 3
fi

if [ "$HTTP_CODE" = "404" ] && [ -n "$FORCED_ID" ]; then
  echo "Bugsnag has no error with id $FORCED_ID. Double-check the id (24-char hex) or the URL." >&2
  exit 5
fi

if [ "$HTTP_CODE" != "200" ]; then
  report_unreachable_and_exit "Bugsnag API unreachable: HTTP $HTTP_CODE. Try again later."
fi

# The list endpoint returns an array; the by-id endpoint returns a single object.
# Wrap the single-object case so downstream jq stays uniform.
if [ -n "$FORCED_ID" ]; then
  BODY="[$BODY]"
fi

# Guard: response should be a JSON array (after the wrap above). Fail loudly if
# Bugsnag's response shape ever changes (e.g., {"errors": [...]}).
if ! echo "$BODY" | jq -e 'type == "array"' >/dev/null; then
  report_unreachable_and_exit "Unexpected Bugsnag response shape (not a JSON array). API may have changed."
fi
COUNT=$(echo "$BODY" | jq 'length')
if [ "$COUNT" -eq 0 ]; then
  if [ "$SKIP" -gt 0 ]; then
    echo "Only $SKIP open production issues this week, --skip $SKIP skipped past all of them." >&2
  else
    echo "No open production issues with events in the last 7 days. Nothing to triage today." >&2
  fi
  exit 5
fi

# Save the errors response — the helper overwrites $BODY on each fetch and we
# still need this for the final JSON emit below.
ERRORS_BODY="$BODY"
ERROR_ID=$(echo "$ERRORS_BODY" | jq -r '.[0].id')

# Resolve the latest event id for the surfaced issue so the SKILL can fetch the
# full report. Without retry here a transient 5xx would hand the SKILL an empty
# event id and a /events/ URL ending in a bare slash.
fetch_latest_event() {
  curl -sS \
    -H "Authorization: token $BUGSNAG_TOKEN" \
    -H "X-Version: 2" \
    -w "\n%{http_code}" \
    "$API_BASE/errors/$ERROR_ID/events?per_page=1"
}

fetch_with_retry fetch_latest_event

if [ "$HTTP_CODE" != "200" ]; then
  report_unreachable_and_exit "Bugsnag events fetch failed for error $ERROR_ID: HTTP $HTTP_CODE."
fi

LATEST_EVENT_ID=$(echo "$BODY" | jq -r '.[0].id // empty')

if [ -z "$LATEST_EVENT_ID" ]; then
  echo "Bugsnag returned no events for error $ERROR_ID — cannot proceed without a latest event to investigate." >&2
  exit 4
fi

# Emit the consolidated JSON (operating on the saved errors response)
echo "$ERRORS_BODY" | jq \
  --arg browser_base "$BROWSER_BASE" \
  --arg latest_event_id "$LATEST_EVENT_ID" \
  --arg api_base "$API_BASE" \
  '.[0] | {
    id,
    short_id: (.id[0:7]),
    error_class,
    message,
    events,
    users,
    first_seen: .first_seen_unfiltered,
    last_seen,
    release_stages,
    introduced_in_release: (.introduced_in_releases[0].build_label // null),
    grouping_hint: (.grouping_fields.custom // null),
    html_url: ($browser_base + "/" + .id),
    latest_event_id: $latest_event_id,
    latest_event_url: ($api_base + "/events/" + $latest_event_id)
  }'
