#!/bin/bash
set -e

SKILLS_DIR="$(cd "$(dirname "$0")" && pwd)"

TARGETS=()
[ -d "${HOME}/.claude" ]  && TARGETS+=("${HOME}/.claude/skills")
[ -d "${HOME}/.agents" ]  && TARGETS+=("${HOME}/.agents/skills")

# If neither exists, default to ~/.claude/skills
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=("${HOME}/.claude/skills")
fi

# ── helpers ────────────────────────────────────────────────────────────────

install_skill() {
  local src="$1" dest="$2" name="$3"

  if [ -d "$dest" ]; then
    printf "conflict: '%s' already exists in %s. [r]eplace / [s]kip? " "$name" "$(dirname "$dest")"
    read -r choice </dev/tty
    case "$choice" in
      r|R)
        rm -rf "$dest"
        cp -r "$src" "$dest"
        echo "replaced: $name → $dest"
        ;;
      *)
        echo "skipped:  $name"
        ;;
    esac
  else
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    echo "installed: $name → $dest"
  fi
}

update_skill() {
  local src="$1" dest="$2" name="$3"

  if [ ! -d "$dest" ]; then
    echo "not found: $name in $(dirname "$dest") — skipping"
    return
  fi

  rm -rf "$dest"
  cp -r "$src" "$dest"
  echo "updated: $name → $dest"
}

# ── commands ───────────────────────────────────────────────────────────────

cmd_install() {
  for target in "${TARGETS[@]}"; do
    mkdir -p "$target"
    echo "── installing into $target"
    for skill in "$SKILLS_DIR"/*/; do
      [ -d "$skill" ] || continue
      name="$(basename "$skill")"
      install_skill "$skill" "$target/$name" "$name"
    done
  done
  echo "done"
}

cmd_update() {
  local only="$1"

  for target in "${TARGETS[@]}"; do
    echo "── updating in $target"

    if [ -n "$only" ]; then
      src="$SKILLS_DIR/$only"
      if [ ! -d "$src" ]; then
        echo "error: skill '$only' not found in repo"
        exit 1
      fi
      update_skill "$src" "$target/$only" "$only"
    else
      for skill in "$SKILLS_DIR"/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        update_skill "$skill" "$target/$name" "$name"
      done
    fi
  done
  echo "done"
}

cmd_list() {
  echo "skills in repo:"
  for skill in "$SKILLS_DIR"/*/; do
    [ -d "$skill" ] && echo "  $(basename "$skill")"
  done
}

cmd_help() {
  cat <<EOF
usage: skills.sh <command> [args]

commands:
  install              install all skills (prompts on conflict)
  update [skill-name]  overwrite skill(s) from repo into installed locations
  list                 list skills available in this repo
  help                 show this message

targets (whichever dirs exist on your machine):
$(for t in "${TARGETS[@]}"; do echo "  $t"; done)
EOF
}

# ── dispatch ───────────────────────────────────────────────────────────────

case "${1:-help}" in
  install) cmd_install ;;
  update)  cmd_update "${2:-}" ;;
  list)    cmd_list ;;
  help|--help|-h) cmd_help ;;
  *) echo "unknown command: $1"; cmd_help; exit 1 ;;
esac
