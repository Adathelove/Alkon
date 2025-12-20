#!/usr/bin/env bash
# Summarize GitHub account/repos using gh.
# Outputs counts, top stars, and stale repos.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/boilerplate.sh"

if ! command -v gh >/dev/null 2>&1; then
  fail "GitHub CLI (gh) is required."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  fail "gh auth status failed; run 'gh auth login'."
  exit 1
fi

owner="$(gh api user --jq .login 2>/dev/null || true)"
if [[ -z "$owner" ]]; then
  fail "Could not determine GitHub login."
  exit 1
fi
info "Using owner: $owner"

info "Fetching repositories…"
data="$(gh repo list "$owner" --limit 200 --json name,visibility,updatedAt,stargazerCount,isPrivate,sshUrl,url --jq '.')" || {
  fail "Failed to fetch repos."
  exit 1
}

total="$(printf '%s' "$data" | jq 'length')"
public="$(printf '%s' "$data" | jq '[.[] | select(.isPrivate==false)] | length')"
private="$(printf '%s' "$data" | jq '[.[] | select(.isPrivate==true)] | length')"

info "Repo counts: total=$total public=$public private=$private"

echo
info "Top 5 by stars"
printf '%s\n' "$data" | jq -r '
  sort_by(-.stargazerCount)[:5]
  | ["Stars","Name","Visibility","Updated"]
  , (.[] | [(.stargazerCount|tostring), .name, .visibility, .updatedAt[0:10]])
  | @tsv' | column -t

echo
info "Stale (>90d since update)"
printf '%s\n' "$data" | jq -r '
  def too_old(dt): (now - (90*24*3600)) as $cut | (dt | fromdateiso8601) < $cut;
  map(select(too_old(.updatedAt)))
  | ["Name","Updated","Visibility"]
  , (.[] | [.name, .updatedAt[0:10], .visibility])
  | @tsv' | column -t
