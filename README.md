# Booi's Agent Skills

[![skills.sh](https://skills.sh/b/booi-gg/skills)](https://skills.sh/booi-gg/skills)

Agent skills I use every day to make building software easier.

Inspired by [Matt Pocock's work](https://github.com/mattpocock) and structured
for the open source [skills.sh](https://skills.sh/) ecosystem.

## Install

Use the official [`skills` CLI](https://github.com/vercel-labs/skills), as
recommended by [skills.sh](https://skills.sh/):

```bash
npx skills add booi-gg/skills
```

For any compatible repository, use:

```bash
npx skills add <owner/repo>
```

The CLI discovers every skill under [`skills/`](./skills/) and lets you choose
which skills to install and which supported agents should receive them.

> The command is `npx skills` (plural). `npx skill` resolves to a different,
> unrelated npm package.

## Repository structure

```text
skills/
  <skill-name>/
    SKILL.md
```

Each skill has its own directory and a `SKILL.md` with the required `name` and
`description` frontmatter. This repository does not need its own `package.json`:
the maintained CLI installs skills directly from the GitHub repository.
