---
name: booi-code-review
description: Multi-axis JavaScript/TypeScript/React code review run as parallel sub-agents — Standards (JS bad/awful parts, purity, naming, hygiene), Architecture (deletion test, shallow modules, hidden dependencies, Fowler smells), React (waterfalls, bundle, re-renders, rendering) and Spec (missing requirements, scope creep). Reports each axis separately. Use when the user says "/booi-code-review", "booi code review", or wants a full review of a branch, PR or uncommitted changes.
---

# Booi Code Review

Review a diff along up to four axes, each in its own sub-agent, then report them side by side. Problems only — no praise.

| Axis         | Rules                                  | Runs when                    |
| ------------ | -------------------------------------- | ---------------------------- |
| Standards    | [JS.md](JS.md) + repo standards        | always                       |
| Architecture | [ARCHITECTURE.md](ARCHITECTURE.md)     | always                       |
| React        | [REACT.md](REACT.md)                   | diff touches React code      |
| Spec         | the issue / PR / spec                  | a spec is found              |

## Process

### 1. Pin the diff

- User names a branch, PR, commit or tag → `git diff <ref>...HEAD` (three-dot, against the merge-base) and `git log <ref>..HEAD --oneline`.
- Nothing named → uncommitted changes (`git diff HEAD`).
- Confirm the ref resolves and the diff is non-empty before going further. Fail here, not inside four sub-agents.

### 2. Find the spec

In order:

1. Issue refs in commit messages (`#123`, `Closes #45`) — fetch with `gh issue view` if available.
2. The PR description (`gh pr view`), when reviewing a PR or branch.
3. A path or text the user passed.
4. A spec file under `docs/`, `specs/` or `.scratch/` matching the branch or feature.

Nothing found → ask. User says there is none → skip the Spec axis and say so in the report.

### 3. Resolve standards

Read `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `CODING_STANDARDS.md`, lint config and ADRs in `docs/adr/`. List every conflict with [JS.md](JS.md) (e.g. repo prefers `for...of`, JS.md flags loops) and ask the user which side to apply. Pass their choices to the sub-agents. Skip anything a linter already enforces.

Detect React: `.tsx`/`.jsx` files or `react` imports in the diff. Detect SSR: Next.js, Remix, RSC or a server entry → tell the React sub-agent to apply its Server section.

### 4. Spawn the axes in parallel

One sub-agent per axis, all in a single message. Each prompt includes:

- The diff command and commit list.
- The absolute path of its rules file in this skill's directory, with "read it first".
- The user's conflict choices from step 3.
- The whole **Output** section below, pasted verbatim, and: "Report problems only. Every rule file applied to every changed file. Use exactly this format. Under 500 words."

Axis-specific briefs:

- **Standards** — "Apply the rules file and the repo's documented standards (list them). Cite the rule for each finding. Repo standards override the rules file."
- **Architecture** — "Apply the rules file. Every finding is a judgement call: start its Issue with 'possible …', severity 🟡 at most. Use the vocabulary in the file. Respect ADRs."
- **React** — "Apply the rules file. Include the impact level (CRITICAL / HIGH / MEDIUM / LOW) in each finding. SSR: yes/no."
- **Spec** — "Given the spec (contents or path), report (a) requirements missing or partial, (b) behaviour not asked for — scope creep, (c) requirements implemented wrongly. Quote the spec line for each."

### 5. Aggregate

Present each axis under its own heading — `## Standards`, `## Architecture`, `## React`, `## Spec` — lightly cleaned. Don't merge or rerank across axes: code can pass one and fail another, and one axis must not mask the other.

Before presenting, fix every finding to match **Output**: missing link → add it; missing Issue/Why/Suggestion line → write it; wrong order → re-sort.

Drop exact duplicates that two axes reported for the same line; keep the one in the more specific axis.

End with one summary line per axis — counts per severity and the worst finding:

```
Standards — 🔴 1 · 🟠 3 · 🟡 8 · ⚪ 12. Worst: dev builds hit the production API.
```

No single winner across axes.

## Output

Each finding:

```
🔴 [file:line](repo/relative/path#Lline) — rule
   Issue: what is wrong, in one sentence.
   Why: 1–2 lines on the concrete risk (bug, drift, perf, readability cost), not a restatement of the rule.
   Suggestion: 1–2 lines on the concrete change. A short code snippet only when clearer than words.
```

Severity — judged for this finding, not by its rule's category:

| Icon | Level    | Meaning                                                                     |
| ---- | -------- | --------------------------------------------------------------------------- |
| 🔴   | Critical | Breaks production, security, data loss, wrong behaviour. Fix before merge. |
| 🟠   | Major    | Likely bug, real performance hit, missing spec requirement.                 |
| 🟡   | Minor    | Maintainability, architecture judgement calls, small performance cost.      |
| ⚪   | Nit      | Style, naming, typos, formatting.                                           |

- Within an axis, sort by severity (🔴 → ⚪), then by file.
- Paths relative to the repo root. Ranges use `#L10-L20`. Multiple lines → link the first, list the rest in the Issue.
- Architecture: Issue starts with "possible", severity 🟡 at most.
- React: impact goes after the rule — `— Bundle (CRITICAL)`. Impact is the rule's category; the icon is this instance.
- An axis with nothing found → "clean". A skipped axis → one line saying why.
