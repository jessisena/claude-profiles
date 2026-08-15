#!/usr/bin/env bash
# install.sh — install claude-as into ~/.local/bin
#
# Usage:
#   ./install.sh             symlink claude-as, print the shell integration line
#   ./install.sh --with-zsh  also append shell integration to ~/.zshrc
#   ./install.sh --help

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN_TARGET="$BIN_DIR/claude-as"
ZSH_RC="$HOME/.zshrc"
ZSH_MARKER="# >>> claude-profiles >>>"
ZSH_END_MARKER="# <<< claude-profiles <<<"
WITH_ZSH=0

# ── args ──────────────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
  --with-zsh) WITH_ZSH=1 ;;
  --help | -h)
    cat <<EOF
usage: install.sh [--with-zsh]

  (default)    symlink bin/claude-as into ~/.local/bin and print the
               optional source line for shell integration.

  --with-zsh   also append shell integration to ~/.zshrc so that
               claude-profile-use, claude-profile-unuse,
               claude-profile-current, and tab-completion are available.

  --help       show this help
EOF
    exit 0
    ;;
  *)
    printf 'unknown option: %s\n' "$arg" >&2
    exit 1
    ;;
  esac
done

# ── step 1: symlink the executable ───────────────────────────────────────────

mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/bin/claude-as" "$BIN_TARGET"
chmod +x "$REPO_DIR/bin/claude-as"
printf '✓ installed claude-as → %s\n' "$BIN_TARGET"

# Warn if ~/.local/bin is not on PATH
case ":${PATH}:" in
*":$BIN_DIR:"*) ;;
*)
  # $PATH and $HOME below are intentionally literal (shown as text for the user to copy).
  # shellcheck disable=SC2016
  printf '\nwarning: %s is not in $PATH\n' "$BIN_DIR"
  printf '  add to your ~/.zshrc:\n'
  # shellcheck disable=SC2016
  printf '    export PATH="$HOME/.local/bin:$PATH"\n\n'
  ;;
esac

# ── step 2: shell integration ─────────────────────────────────────────────────

SOURCE_LINE="source \"$REPO_DIR/shell/claude-profiles.zsh\""

if [[ $WITH_ZSH -eq 1 ]]; then
  if [[ -f "$ZSH_RC" ]] && grep -qF "$ZSH_MARKER" "$ZSH_RC" 2>/dev/null; then
    printf '✓ ~/.zshrc already has shell integration (skipped)\n'
  else
    {
      printf '\n%s\n' "$ZSH_MARKER"
      printf '%s\n' "$SOURCE_LINE"
      printf '%s\n' "$ZSH_END_MARKER"
    } >>"$ZSH_RC"
    printf '✓ added shell integration to ~/.zshrc\n'
    printf '  reload with: source ~/.zshrc\n'
  fi
else
  printf '\nShell integration is optional — adds claude-profile-use, tab-completion, etc.\n'
  printf 'To enable, add to ~/.zshrc:\n'
  printf '  %s\n' "$SOURCE_LINE"
  printf '\nOr re-run:\n'
  printf '  %s --with-zsh\n' "$0"
fi

# ── done ──────────────────────────────────────────────────────────────────────

printf '\nCreate your first profile:\n'
printf '  claude-as --new <name>\n'
printf '\nList profiles:\n'
printf '  claude-as --list\n'
