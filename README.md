# Agent Skills I Use For Ez life

My agent skills that I use everyday to make my life easier,
call it vibe, lazy, I don't care.

Inspired by, Copied From
https://github.com/mattpocock

## Install

Run this script to copy all skills into `~/.claude/skills/` (falling back to `~/.agents/skills/` if that's what you use):

```bash
#!/bin/bash
set -e

SKILLS_DIR="$(pwd)"
TARGET="${HOME}/.claude/skills"

# Fallback to ~/.agents/skills if ~/.claude doesn't exist
if [ ! -d "${HOME}/.claude" ] && [ -d "${HOME}/.agents" ]; then
  TARGET="${HOME}/.agents/skills"
fi

mkdir -p "$TARGET"

for skill in "$SKILLS_DIR"/*/; do
  name="$(basename "$skill")"
  dest="$TARGET/$name"

  if [ -d "$dest" ]; then
    printf "conflict: '%s' already exists. [r]eplace / [s]kip? " "$name"
    read -r choice </dev/tty
    case "$choice" in
      r|R)
        rm -rf "$dest"
        cp -r "$skill" "$dest"
        echo "replaced: $name"
        ;;
      *)
        echo "skipped: $name"
        ;;
    esac
  else
    cp -r "$skill" "$dest"
    echo "installed: $name"
  fi
done

echo "done → $TARGET"
```

Clone the repo, `cd` into it, then run the script.
