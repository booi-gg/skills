#!/usr/bin/env bash
# Post each entry of a JSON array as its OWN separate inline PR comment.
#
# Usage: post-inline-comments.sh <owner/repo> <pr> <head-sha> <comments.json> [--dry-run]
#
# comments.json: [{ "path": "src/a.ts", "line": 42, "body": "...",
#                   "side": "RIGHT", "start_line": 40 }, ...]
#   side defaults to RIGHT. start_line is optional (multi-line span).
#
# Exits non-zero if any comment failed, so a caller can branch on it.

set -uo pipefail

if [ "$#" -lt 4 ]; then
	sed -n '2,12p' "$0" >&2
	exit 64
fi

REPO=$1
PR=$2
SHA=$3
FILE=$4
DRY=${5:-}

command -v gh >/dev/null || {
	echo "gh not installed — install it (brew install gh) and run gh auth login" >&2
	exit 69
}
gh auth status >/dev/null 2>&1 || {
	echo "gh is not authenticated — run gh auth login" >&2
	exit 69
}
[ -f "$FILE" ] || {
	echo "no such file: $FILE" >&2
	exit 66
}

TOTAL=$(jq 'length' "$FILE")
PAYLOAD=$(mktemp)
ERR=$(mktemp)
trap 'rm -f "$PAYLOAD" "$ERR"' EXIT

ok=0
fail=0

for i in $(seq 0 $((TOTAL - 1))); do
	jq --arg sha "$SHA" ".[$i] + {commit_id: \$sha} | .side //= \"RIGHT\"" "$FILE" >"$PAYLOAD"
	loc=$(jq -r '"\(.path):\(.line)"' "$PAYLOAD")

	if [ "$DRY" = "--dry-run" ]; then
		echo "DRY  $loc"
		continue
	fi

	# Branch on gh's exit code — parsing the response body for a success
	# marker misreports failures as successes and vice versa.
	if id=$(gh api --method POST "/repos/$REPO/pulls/$PR/comments" --input "$PAYLOAD" --jq '.id' 2>"$ERR"); then
		echo "OK   $loc  (id=$id)"
		ok=$((ok + 1))
	else
		echo "FAIL $loc  $(tr '\n' ' ' <"$ERR" | cut -c1-240)"
		fail=$((fail + 1))
	fi
done

if [ "$DRY" = "--dry-run" ]; then
	echo "--- dry run: $TOTAL comments would be posted to $REPO#$PR at $SHA ---"
	exit 0
fi

echo "--- posted=$ok failed=$fail of $TOTAL ---"
echo "verify: gh api --paginate /repos/$REPO/pulls/$PR/comments --jq '.[] | \"\\(.path):\\(.line)\"' | sort | uniq -c | sort -rn"
[ "$fail" -eq 0 ]
