---
name: add-gh-comment
description: Post comments on a GitHub PR or issue with `gh` — one inline comment per issue anchored to its own line, a PR-level comment, or an issue comment. Use when asked to leave a comment on GitHub, comment on specific lines or files, or reply to a review thread. Preflights `gh` and stops if it is missing or unauthenticated.
---

# Add GitHub comment

Posting is outward-facing and lands on other people's PR. Get the **anchor** right before posting, and **verify** after.

## 1. Preflight

Run first, every time:

```bash
command -v gh >/dev/null && gh auth status
```

**`gh` missing** — stop and say so:

> `gh` is not installed, so I can't post this. Install it (`brew install gh`), then `gh auth login`. Meanwhile here's the review to paste by hand:

Then print the comments as text. Never hand-roll a `curl` call against the GitHub API to work around a missing `gh`.

**`gh` present but unauthenticated** — stop and say so: the user runs `gh auth login` in their own terminal. Do not ask them for a token.

**Wrong account** — `gh auth status` prints the active login. When it isn't the account the user expects for this repo, name the login you see and ask before posting.

## 2. Pick the shape

Three shapes. When the request doesn't name one, ask:

| Shape | What lands | Command |
| --- | --- | --- |
| **Inline** comments | One standalone comment per issue, each its own thread | `POST /repos/{repo}/pulls/{pr}/comments`, once per comment |
| PR-level comment | One comment on the conversation tab, no line anchor | `gh pr comment <pr> --body-file <file>` |
| Issue comment | One comment on an issue | `gh issue comment <n> --body-file <file>` |

Default is **inline**: one comment per issue, on the file and line where that issue lives. Never fold several issues into one comment, and never post a summary review that nests them.

Write bodies to a file and use `--body-file`. Inline `--body` strings mangle backticks and newlines in zsh.

## Response Format

Inline comment body — one issue, one line, references the code:

```
🚩 [ONE-LINE DESCRIPTION, REFERENCING THE SPECIFIC CODE]
```

Anchor is off-hunk — real location in the body:

```
🚩 [ONE-LINE DESCRIPTION] (`[path]:[line]`)
```

Nothing to flag:

```
✅ Approved
```

No preamble, no sign-off, no "here's how to fix it".

## 3. Anchor inline comments

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

## 4. Post

Build a JSON array of `{path, line, body}` objects, then:

```bash
scripts/post-inline-comments.sh <owner/repo> <pr> <head-sha> comments.json --dry-run
scripts/post-inline-comments.sh <owner/repo> <pr> <head-sha> comments.json
```

The script posts each entry as its own separate comment and reports per-comment success from `gh`'s exit code. Dry-run first on anything over ~5 comments.

Don't submit a review (`POST .../pulls/<pr>/reviews`). `APPROVE` and `REQUEST_CHANGES` are the user's call to make, not yours.

**Post once.** A staged API call can fire even when the user rejects the permission prompt, so never leave a superseded call staged after rewriting the comment set — verify nothing landed before posting the replacement.

## 5. Verify

Count what actually landed, every time:

```bash
gh api --paginate /repos/<repo>/pulls/<pr>/comments \
  --jq '.[] | select(.user.login=="<login>") | "\(.path):\(.line)"' | sort | uniq -c | sort -rn
```

A count above what you sent means something double-posted. Report the real count plainly — including when it's wrong. Removing comments from someone's PR is the user's call; tell them what's there and let them decide.

## Reply to a thread

```bash
gh api --method POST /repos/<repo>/pulls/<pr>/comments/<comment-id>/replies \
  -f body="$(cat reply.md)"
```

Replying keeps the thread; a fresh `POST .../comments` on the same line starts a second thread beside it.
