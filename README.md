# booi-gg Agent Skills

[![skills.sh](https://skills.sh/b/booi-gg/skills)](https://skills.sh/booi-gg/skills)

Reusable agent skills maintained by [booi-gg](https://github.com/booi-gg) to
make building software easier.

Inspired by [Matt Pocock's work](https://github.com/mattpocock) and structured
for the open source [skills.sh](https://skills.sh/) ecosystem.

## Install

Use the official [`skills` CLI](https://github.com/vercel-labs/skills), as
recommended by [skills.sh](https://skills.sh/):

```bash
npx skills add booi-gg/skills
```

This opens an interactive selector for choosing skills and target agents.

Install one skill directly:

```bash
npx skills add booi-gg/skills --skill <skill-name>
```

Example:

```bash
npx skills add booi-gg/skills --skill evaluate-saas-idea
```

Use any skill name from the catalog below.

Install every skill to all supported agents:

```bash
npx skills add booi-gg/skills --all
```

The CLI discovers every skill under [`skills/`](./skills/) and lets you choose
which skills to install and which supported agents should receive them.

> The command is `npx skills` (plural). `npx skill` resolves to a different,
> unrelated npm package.

## Available skills

- [`caveman`](./skills/caveman/) — communicate with maximum brevity.
- [`design-an-interface`](./skills/design-an-interface/) — compare radically different module interfaces.
- [`evaluate-saas-idea`](./skills/evaluate-saas-idea/) — evaluate SaaS ideas like an objective startup investor.
- [`grill-me`](./skills/grill-me/) — stress-test plans through focused questions.
- [`improve-codebase-architecture`](./skills/improve-codebase-architecture/) — find deep-module refactoring opportunities.
- [`lwb`](./skills/lwb/) — teach one engineering concept while building.
- [`obsidian-vault`](./skills/obsidian-vault/) — search and manage an Obsidian vault.
- [`request-refactor-plan`](./skills/request-refactor-plan/) — turn refactor discussions into actionable plans.
- [`tdd`](./skills/tdd/) — build through red-green-refactor.
- [`to-issues`](./skills/to-issues/) — split plans into independently deliverable issues.
- [`to-prd`](./skills/to-prd/) — turn conversation context into a product requirements document.
- [`write-a-skill`](./skills/write-a-skill/) — create reusable agent skills.
- [`zoom-out`](./skills/zoom-out/) — map unfamiliar code from a higher-level view.

## Repository structure

```text
skills/
  <skill-name>/
    SKILL.md
```

Each skill has its own directory and a `SKILL.md` with the required `name` and
`description` frontmatter. This repository does not need its own `package.json`:
the maintained CLI installs skills directly from the GitHub repository.
