#!/usr/bin/env bash
# uninstall.sh — remove claude-as tooling
#
# Usage:
#   ./uninstall.sh           remove the symlink and ~/.zshrc block; leave profiles
#   ./uninstall.sh --purge   also sign out and trash all profile directories
#   ./uninstall.sh --help
#
# What is NEVER touched:
#   ~/.claude           your default account directory
#   ~/.claude.json      your default account config
#   The default "Claude Code-credentials" Keychain item
#   The Claude Code installation itself

set -euo pipefail

PROFILE_HOME="${CLAUDE_PROFILE_HOME:-$HOME/.claude-profiles}"
BIN_TARGET="$HOME/.local/bin/claude-as"
ZSH_RC="$HOME/.zshrc"
ZSH_MARKER="# >>> claude-profiles >>>"
ZSH_END_MARKER="# <<< claude-profiles <<<"
PURGE=0

# ── args ──────────────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
  --purge) PURGE=1 ;;
  --help | -h)
    cat <<EOF
usage: uninstall.sh [--purge]

  (default)  remove the claude-as symlink from ~/.local/bin and the
             shell-integration block from ~/.zshrc.
             Profile directories are left untouched — accounts stay
             signed in and can still be reached with:
               CLAUDE_CONFIG_DIR=~/.claude-profiles/<name> claude

  --purge    also sign each profile out (removes Keychain items), stop
             per-profile background daemons, and trash the entire
             profile directory. See docs/uninstalling.md for details.

  --help     show this help

NEVER touched by this script:
  ~/.claude               default account directory
  ~/.claude.json          default account global config
  Claude Code-credentials macOS Keychain item (default account)
  The Claude Code installation
EOF
    exit 0
    ;;
  *)
    printf 'unknown option: %s\n' "$arg" >&2
    exit 1
    ;;
  esac
done

# ── safety check ──────────────────────────────────────────────────────────────

# Refuse to operate if CLAUDE_PROFILE_HOME points at the default account dir.
if [[ -d "$PROFILE_HOME" && -d "$HOME/.claude" ]]; then
  real_profile="$(cd "$PROFILE_HOME" && pwd -P)"
  real_default="$(cd "$HOME/.claude" && pwd -P)"
  if [[ "$real_profile" == "$real_default" ]]; then
    printf 'error: CLAUDE_PROFILE_HOME resolves to %s\n' "$real_profile" >&2
    printf '  that is your default account directory — refusing to operate\n' >&2
    printf '  unset CLAUDE_PROFILE_HOME and try again\n' >&2
    exit 1
  fi
fi

# ── step 1: remove symlink ────────────────────────────────────────────────────

if [[ -L "$BIN_TARGET" ]]; then
  rm "$BIN_TARGET"
  printf '✓ removed %s\n' "$BIN_TARGET"
elif [[ -e "$BIN_TARGET" ]]; then
  printf 'warning: %s exists but is not a symlink — not removing\n' "$BIN_TARGET" >&2
else
  printf '(claude-as not found in ~/.local/bin)\n'
fi

# ── step 2: remove ~/.zshrc block ─────────────────────────────────────────────

if [[ -f "$ZSH_RC" ]] && grep -qF "$ZSH_MARKER" "$ZSH_RC" 2>/dev/null; then
  tmp="$(mktemp)"
  awk -v start="$ZSH_MARKER" -v end="$ZSH_END_MARKER" \
    'index($0,start){skip=1;next} index($0,end){skip=0;next} !skip{print}' \
    "$ZSH_RC" >"$tmp"
  mv "$tmp" "$ZSH_RC"
  printf '✓ removed shell-integration block from ~/.zshrc\n'
else
  printf '(no shell-integration block in ~/.zshrc)\n'
fi

# ── step 3: purge profiles (--purge only) ─────────────────────────────────────

if [[ $PURGE -eq 1 ]]; then
  printf '\n-- purge mode --\n'

  if [[ ! -d "$PROFILE_HOME" ]]; then
    printf '(no profile directory at %s)\n' "$PROFILE_HOME"
  else
    # Require trash — never use rm -rf on a directory full of user data.
    if ! command -v trash >/dev/null 2>&1; then
      printf 'error: "trash" command not found\n' >&2
      printf '  install it (e.g. brew install trash) or manually remove:\n' >&2
      printf '  Sign out first: claude-as <name> auth logout\n' >&2
      printf '  Then delete:    rm -rf "%s"\n' "$PROFILE_HOME" >&2
      exit 1
    fi

    # Require claude for the auth logout step.
    if ! command -v claude >/dev/null 2>&1; then
      printf 'warning: claude not found in PATH — cannot sign out profiles\n' >&2
      printf '  Keychain items will be orphaned. See docs/uninstalling.md for recovery.\n' >&2
    else
      for d in "$PROFILE_HOME"/*/; do
        [[ -d "$d" ]] || continue
        name="${d%/}"
        name="${name##*/}"

        printf '\n[%s] signing out...\n' "$name"
        if CLAUDE_CONFIG_DIR="$d" claude auth logout 2>/dev/null; then
          printf '[%s] ✓ signed out (Keychain item removed)\n' "$name"
        else
          printf '[%s] warning: sign-out returned non-zero (may already be signed out)\n' "$name"
        fi

        printf '[%s] stopping background daemon...\n' "$name"
        if CLAUDE_CONFIG_DIR="$d" claude daemon stop --any 2>/dev/null; then
          printf '[%s] ✓ daemon stopped\n' "$name"
        else
          printf '[%s] (no daemon running)\n' "$name"
        fi
      done
    fi

    printf '\nMoving profile directory to Trash...\n'
    trash "$PROFILE_HOME"
    printf '✓ %s → Trash\n' "$PROFILE_HOME"
  fi

  printf '\nVerify everything is clean:\n'
  printf '  command -v claude-as          # should print nothing\n'
  printf '  ls ~/.claude-profiles         # should say No such file or directory\n'
  printf '  rg -n claude-profiles ~/.zshrc  # should return no matches\n'
  printf '  claude auth status            # should still show your default account\n'
fi

printf '\nDone.\n'
