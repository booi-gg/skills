# Booi's Agent Skills

[![skills.sh](https://skills.sh/b/booi-gg/skills)](https://skills.sh/booi-gg/skills)

Agent skills I use every day to make building software easier.

Inspired by [Matt Pocock's work](https://github.com/mattpocock) and structured
for the open source [skills.sh](https://skills.sh/) ecosystem.

## Install with npx

Use the official, maintained `skills` CLI:

```bash
npx skills add booi-gg/skills
```

The CLI discovers every skill under [`skills/`](./skills/) and lets you choose
which ones to install and which supported agents should receive them.

> Use `skills` (plural). `npx skill` is a different, unrelated npm package and
> is not the installer recommended by skills.sh.

## Local checkout

The legacy helper remains available when working from a cloned checkout:

```bash
./skills.sh list
./skills.sh install
./skills.sh update
./skills.sh update caveman
```

It writes to `~/.claude/skills/` and `~/.agents/skills/`, whichever exist on
your machine.

## Repository layout

```text
skills/
  <skill-name>/
    SKILL.md
```

Each skill has its own directory and a `SKILL.md` with the required `name` and
`description` frontmatter.
