#!/bin/bash

# One GitHub snapshot as a single JSON object, through the authenticated `gh`
# CLI (no token of its own):
#
#   radar.sh [rows-per-section]
#   radar.sh mark-read              mark every notification as read
#
#   { state: ok | missing | unauthenticated | error, login, error,
#     reviews:       { total, items: [pr...] },   PRs waiting for my review
#     pulls:         { total, items: [pr...] },   PRs I opened
#     issues:        { total, items: [issue...] } issues assigned to me
#     notifications: { total, items: [n...] } }   unread notifications
#
# The GraphQL searches and the notifications REST call run in parallel; each
# refresh costs one GraphQL request plus one REST request.

set -o pipefail

rows=${1:-5}
[[ $rows =~ ^[0-9]+$ ]] || rows=5
(( rows > 50 )) && rows=50

find_gh() {
  local candidate
  for candidate in "$(command -v gh 2>/dev/null)" "$HOME/.local/share/mise/shims/gh" "$HOME/.local/bin/gh" /usr/bin/gh; do
    [[ -n $candidate && -x $candidate ]] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

GH=$(find_gh) || { printf '{"state":"missing"}\n'; exit 0; }

if ! "$GH" auth status >/dev/null 2>&1; then
  printf '{"state":"unauthenticated"}\n'
  exit 0
fi

if [[ ${1:-} == mark-read ]]; then
  "$GH" api -X PUT notifications -F read=true --silent
  exit $?
fi

read -r -d '' QUERY <<'GRAPHQL'
query($reviews: String!, $mine: String!, $issues: String!, $n: Int!) {
  viewer { login }
  reviews: search(query: $reviews, type: ISSUE, first: $n) { issueCount nodes { ...pr } }
  mine: search(query: $mine, type: ISSUE, first: $n) { issueCount nodes { ...pr } }
  issues: search(query: $issues, type: ISSUE, first: $n) {
    issueCount
    nodes { ... on Issue { number title url updatedAt repository { nameWithOwner } author { login } } }
  }
}
fragment pr on PullRequest {
  number title url isDraft updatedAt reviewDecision
  repository { nameWithOwner }
  author { login }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
}
GRAPHQL

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

"$GH" api graphql \
  -f query="$QUERY" \
  -f reviews='is:pr is:open review-requested:@me archived:false' \
  -f mine='is:pr is:open author:@me archived:false' \
  -f issues='is:issue is:open assignee:@me archived:false' \
  -F n="$rows" >"$tmp/graphql.json" 2>"$tmp/graphql.err" &
gql_pid=$!

"$GH" api "notifications?per_page=50" >"$tmp/notifications.json" 2>"$tmp/notifications.err" &
notif_pid=$!

wait "$gql_pid"; gql_rc=$?
wait "$notif_pid"; notif_rc=$?

if (( gql_rc != 0 )) || ! jq -e '.data.viewer.login' "$tmp/graphql.json" >/dev/null 2>&1; then
  message=$(jq -r '.errors[0].message // empty' "$tmp/graphql.json" 2>/dev/null)
  [[ -n $message ]] || message=$(head -c 300 "$tmp/graphql.err" | tr '\n' ' ')
  [[ -n $message ]] || message="GitHub request failed"
  jq -cn --arg m "$message" '{state: "error", error: $m}'
  exit 0
fi

(( notif_rc == 0 )) && jq -e 'type == "array"' "$tmp/notifications.json" >/dev/null 2>&1 || echo '[]' >"$tmp/notifications.json"

jq -c --arg rows "$rows" --slurpfile notifications "$tmp/notifications.json" '
  def pr_row: {
    kind: "pull",
    repo: .repository.nameWithOwner,
    number: .number,
    title: .title,
    url: .url,
    author: (.author.login // ""),
    updatedAt: .updatedAt,
    draft: (.isDraft // false),
    ci: (.commits.nodes[0].commit.statusCheckRollup.state // ""),
    review: (.reviewDecision // "")
  };
  def issue_row: {
    kind: "issue",
    repo: .repository.nameWithOwner,
    number: .number,
    title: .title,
    url: .url,
    author: (.author.login // ""),
    updatedAt: .updatedAt
  };
  # REST subject URLs point at the API; turn them into browser URLs.
  def html_url:
    (.subject.url // "") as $u
    | if $u == "" then (.repository.html_url // "")
      else $u
        | sub("^https://api.github.com/repos/"; "https://github.com/")
        | sub("/pulls/"; "/pull/")
        | sub("/commits/"; "/commit/")
      end;
  def notification_row: {
    kind: "notification",
    id: .id,
    repo: (.repository.full_name // ""),
    title: (.subject.title // ""),
    type: (.subject.type // ""),
    reason: (.reason // ""),
    url: html_url,
    updatedAt: (.updated_at // "")
  };
  ($notifications[0] // []) as $n
  | {
      state: "ok",
      login: .data.viewer.login,
      fetchedAt: (now | floor),
      reviews: { total: .data.reviews.issueCount, items: [ .data.reviews.nodes[] | select(.number != null) | pr_row ] },
      pulls: { total: .data.mine.issueCount, items: [ .data.mine.nodes[] | select(.number != null) | pr_row ] },
      issues: { total: .data.issues.issueCount, items: [ .data.issues.nodes[] | select(.number != null) | issue_row ] },
      notifications: { total: ($n | length), items: [ $n[] | select(.unread != false) | notification_row ] | .[:($rows | tonumber)] }
    }' "$tmp/graphql.json"
