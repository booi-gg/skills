---
name: add-gh-comment
description: Post comments on a GitHub PR or issue with `gh` — one inline comment per issue anchored to its own line, a PR-level comment, or an issue comment. Use when asked to leave a comment on GitHub, comment on specific lines or files, or reply to a review thread. Preflights `gh` and `jq` and stops if either is missing or unauthenticated.
---

# Add GitHub comment

Posting is outward-facing and lands on other people's PR. Get the **anchor** right before posting, and **verify** after.

## 1. Preflight

Run first, every time:

```bash
command -v gh >/dev/null && command -v jq >/dev/null && gh auth status
```

**`gh` missing** — stop and say so:

> `gh` is not installed, so I can't post this. Install it (`brew install gh`), then `gh auth login`. Meanwhile here's the review to paste by hand:

Then print the comments as text. Never hand-roll a `curl` call against the GitHub API to work around a missing `gh`.

**`gh` present but unauthenticated** — stop and say so: the user runs `gh auth login` in their own terminal. Do not ask them for a token.

**`jq` missing** — stop the same way. The posting loop in step 6 needs it (`brew install jq`).

**Wrong account** — `gh auth status` prints the active login. When it isn't the account the user expects for this repo, name the login you see and ask before posting.

## 2. Find the target

Everything below needs `<repo>` and `<pr>`. Don't infer either from the directory name:

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
gh pr status --json number,title,headRefName,url
```

`gh pr status` reports the PR for the current branch. When the user named a different branch, or the current branch has no PR, look it up:

```bash
gh pr list --head <branch> --state all --json number,title,url,headRefOid
```

No PR and no number given — ask which one. Two matches — name both and ask.

## 3. Pick the shape

Three shapes. When the request doesn't name one, ask:

| Shape               | What lands                                            | Command                                                    |
| ------------------- | ----------------------------------------------------- | ---------------------------------------------------------- |
| **Inline** comments | One standalone comment per issue, each its own thread | `POST /repos/{repo}/pulls/{pr}/comments`, once per comment |
| PR-level comment    | One comment on the conversation tab, no line anchor   | `gh pr comment <pr> --body-file <file>`                    |
| Issue comment       | One comment on an issue                               | `gh issue comment <n> --body-file <file>`                  |

Default is **inline**: one comment per issue, on the file and line where that issue lives. Never fold several issues into one comment, and never post a summary review that nests them.

## 4. Write the body

Write bodies to a file and use `--body-file` — inline `--body` strings mangle backticks and newlines in zsh. Put those files and `comments.json` in your scratchpad directory, never in the user's repo; they are staging artifacts, not something to leave in a working tree.

Inline comment body — one issue, one line, references the code:

```
⚠️ [ONE-LINE DESCRIPTION, REFERENCING THE SPECIFIC CODE]
```

Anchor is off-hunk — real location in the body:

```
⚠️ [ONE-LINE DESCRIPTION] (`[path]:[line]`)
```

Nothing to flag:

```
✅ Approved
```

No preamble, no sign-off, no "here's how to fix it".

**No attribution footer.** Never append `🤖 Generated with [Claude Code]`, `Co-Authored-By: Claude`, or any variant to a comment body. That convention is for commits and PR descriptions — a comment on someone's PR carries none of it.

## 5. Anchor inline comments

Inline comments 422 unless the anchor is exact. Three things have to line up.

**The PR head SHA, not local HEAD.** The local branch drifts from the PR — unpushed commits, or commits pushed from elsewhere:

```bash
gh pr list --head <branch> --state all --json number,url,headRefOid
```

When `headRefOid` differs from `git rev-parse HEAD`, every line number computed locally is suspect. Fetch the PR head and recompute against it:

```bash
git fetch origin <branch>
git show <headRefOid>:<path> | grep -n "<pattern>"
```

Say in the summary that you re-anchored, and by how much the lines moved.

**Lines inside a hunk range.** Only lines GitHub shows in the PR diff are commentable — added, removed, and the few context lines around them. A line in an untouched region rejects with `pull_request_review_thread.line must be part of the diff`:

```bash
gh pr diff <pr> | grep -n "^@@\|^diff --git"
```

A `@@ -a,b +c,d @@` hunk makes new-side lines `c` through `c+d-1` commentable. To point at code outside every hunk, anchor to the nearest in-hunk line and reference the real location as `path:line` in the body text.

**Side and span.** `side: "RIGHT"` for the new version (the default you want), `"LEFT"` for deleted lines. For a range, add `start_line` alongside `line`; `line` is the last line of the span.

## 6. Post

Write the comment set to `comments.json` in your scratchpad — one object per comment:

```json
[
  { "path": "src/auth.ts", "line": 42, "body": "🚩 …" },
  {
    "path": "src/db.ts",
    "line": 88,
    "body": "🚩 …",
    "side": "LEFT",
    "start_line": 85
  }
]
```

`side` defaults to `RIGHT`. `start_line` is optional (multi-line span).

Preview the anchors first — always on more than ~5 comments:

```bash
jq -r '.[] | "DRY  \(.path):\(.line)"' comments.json
```

Then post. One `POST` per entry, so each lands as its own thread:

```bash
REPO=<owner/repo>
PR=<number>
SHA=<head-sha>
P=$(mktemp)
for i in $(jq 'keys[]' comments.json); do
  jq --arg s "$SHA" ".[$i] + {commit_id: \$s} | .side //= \"RIGHT\"" comments.json >"$P"
  loc=$(jq -r '"\(.path):\(.line)"' "$P")
  if id=$(gh api --method POST "/repos/$REPO/pulls/$PR/comments" --input "$P" --jq '.id' 2>&1); then
    echo "OK   $loc  (id=$id)"
  else
    echo "FAIL $loc  $(echo "$id" | tr '\n' ' ' | cut -c1-200)"
  fi
done
rm -f "$P"
```

Two things this loop is doing on purpose. It branches on `gh`'s **exit code** — grepping the response body for a success marker misreports failures as successes. And it keeps going after a failure, so one bad anchor costs you that comment instead of the whole batch. Report the `FAIL` lines; don't silently retry them.

Don't submit a review (`POST .../pulls/<pr>/reviews`). `APPROVE` and `REQUEST_CHANGES` are the user's call to make, not yours.

**Post once.** A staged API call can fire even when the user rejects the permission prompt, so never leave a superseded call staged after rewriting the comment set — verify nothing landed before posting the replacement.

## 7. Verify

Count what actually landed, every time. Filter to your own login — an unfiltered count includes other reviewers' comments and reads as a double-post:

```bash
gh api --paginate /repos/<repo>/pulls/<pr>/comments \
  --jq ".[] | select(.user.login==\"$(gh api user --jq '.login')\") | \"\(.path):\(.line)\"" |
  sort | uniq -c | sort -rn
```

A count above what you sent means something double-posted. Report the real count plainly — including when it's wrong. Removing comments from someone's PR is the user's call; tell them what's there and let them decide.

## Reply to a thread

```bash
gh api --method POST /repos/<repo>/pulls/<pr>/comments/<comment-id>/replies \
  -f body="$(cat reply.md)"
```

Replying keeps the thread; a fresh `POST .../comments` on the same line starts a second thread beside it.
