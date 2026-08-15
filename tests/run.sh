#!/usr/bin/env bash
# tests/run.sh — lint + functional tests for claude-profiles
#
# No extra dependencies required: uses shellcheck/shfmt if available,
# zsh for syntax-checking the zsh file, and a stub claude for functional tests.
#
# Usage:
#   ./tests/run.sh      from the repo root or the tests/ directory

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

PASS=0
FAIL=0

ok() {
  printf '  ✓ %s\n' "$1"
  PASS=$((PASS + 1))
}
fail() {
  printf '  ✗ %s\n' "$1"
  FAIL=$((FAIL + 1))
}

# ── lint ──────────────────────────────────────────────────────────────────────

printf '=== lint\n'

BASH_FILES=(
  "$REPO_DIR/bin/claude-as"
  "$REPO_DIR/install.sh"
  "$REPO_DIR/uninstall.sh"
  "$REPO_DIR/tests/run.sh"
)

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "${BASH_FILES[@]}"; then
    ok "shellcheck"
  else
    fail "shellcheck"
  fi
else
  printf '  (shellcheck not found — skipping)\n'
fi

if command -v shfmt >/dev/null 2>&1; then
  if shfmt -i 2 -d "${BASH_FILES[@]}" >/dev/null 2>&1; then
    ok "shfmt"
  else
    fail "shfmt (run: shfmt -i 2 -w bin/claude-as install.sh uninstall.sh tests/run.sh)"
  fi
else
  printf '  (shfmt not found — skipping)\n'
fi

if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$REPO_DIR/shell/claude-profiles.zsh" 2>/dev/null; then
    ok "zsh -n shell/claude-profiles.zsh"
  else
    fail "zsh -n shell/claude-profiles.zsh"
  fi
else
  printf '  (zsh not found — skipping)\n'
fi

if command -v actionlint >/dev/null 2>&1; then
  if actionlint "$REPO_DIR/.github/workflows/ci.yml" 2>/dev/null; then
    ok "actionlint ci.yml"
  else
    fail "actionlint ci.yml"
  fi
else
  printf '  (actionlint not found — skipping)\n'
fi

if command -v zizmor >/dev/null 2>&1; then
  if zizmor "$REPO_DIR/.github/workflows/" >/dev/null 2>&1; then
    ok "zizmor"
  else
    fail "zizmor"
  fi
else
  printf '  (zizmor not found — skipping)\n'
fi

# ── functional tests ──────────────────────────────────────────────────────────

printf '\n=== functional\n'

# Temporary workspace for the entire test run
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A stub claude that records its invocation environment
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/claude" <<'EOF'
#!/bin/sh
printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR:-}"
printf 'ARGS=%s\n' "$*"
EOF
chmod +x "$STUB_BIN/claude"

PROFILE_HOME="$TMP/profiles"
mkdir -p "$PROFILE_HOME"

CLAUDE_AS="$REPO_DIR/bin/claude-as"

# Run claude-as with the stub claude in PATH and an isolated profile home
run() {
  env PATH="$STUB_BIN:$PATH" CLAUDE_PROFILE_HOME="$PROFILE_HOME" "$CLAUDE_AS" "$@"
}

# ── --list ────────────────────────────────────────────────────────────────────

actual="$(run --list 2>/dev/null)"
if [[ -z "$actual" ]]; then
  ok "--list empty home: no stdout output"
else
  fail "--list empty home: unexpected output: $actual"
fi

exit_code=0
run --list >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 0 ]]; then
  ok "--list empty home: exits 0"
else
  fail "--list empty home: expected exit 0, got $exit_code"
fi

# ── unknown / invalid profiles ────────────────────────────────────────────────

exit_code=0
err="$(run bogus 2>&1)" || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  ok "unknown profile: exits non-zero"
else
  fail "unknown profile: expected non-zero exit"
fi
if [[ "$err" == *"bogus"* ]]; then
  ok "unknown profile: error message names the profile"
else
  fail "unknown profile: error should mention 'bogus', got: $err"
fi

for bad in "../etc" "foo/bar" "foo bar"; do
  exit_code=0
  run "$bad" 2>/dev/null || exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    ok "invalid name '$bad': rejected"
  else
    fail "invalid name '$bad': should have been rejected"
  fi
done

# ── running a valid profile ───────────────────────────────────────────────────

mkdir -p "$PROFILE_HOME/work"

output="$(run work 2>/dev/null)"
if [[ "$output" == *"CLAUDE_CONFIG_DIR=$PROFILE_HOME/work"* ]]; then
  ok "profile 'work': CLAUDE_CONFIG_DIR passed correctly"
else
  fail "profile 'work': unexpected output: $output"
fi

# ── argv forwarding ───────────────────────────────────────────────────────────

output="$(run work auth status 2>/dev/null)"
if [[ "$output" == *"ARGS=auth status"* ]]; then
  ok "argv forwarding: 'auth status'"
else
  fail "argv forwarding: expected 'ARGS=auth status', got: $output"
fi

output="$(run work --resume 2>/dev/null)"
if [[ "$output" == *"ARGS=--resume"* ]]; then
  ok "argv forwarding: '--resume'"
else
  fail "argv forwarding: expected 'ARGS=--resume', got: $output"
fi

# ── shell is not polluted ─────────────────────────────────────────────────────

unset CLAUDE_CONFIG_DIR 2>/dev/null || true
run work >/dev/null 2>&1
if [[ -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
  ok "shell not polluted: CLAUDE_CONFIG_DIR unset after run"
else
  fail "shell not polluted: CLAUDE_CONFIG_DIR='$CLAUDE_CONFIG_DIR' after run"
fi

# ── --list with profiles ──────────────────────────────────────────────────────

mkdir -p "$PROFILE_HOME/personal"
output="$(run --list 2>/dev/null)"
if [[ "$output" == *"personal"* ]] && [[ "$output" == *"work"* ]]; then
  ok "--list with profiles: shows names"
else
  fail "--list with profiles: expected personal and work, got: $output"
fi

# ── --path ────────────────────────────────────────────────────────────────────

output="$(run --path work 2>/dev/null)"
if [[ "$output" == "$PROFILE_HOME/work" ]]; then
  ok "--path: prints config dir"
else
  fail "--path: expected $PROFILE_HOME/work, got: $output"
fi

exit_code=0
run --path nosuch 2>/dev/null || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  ok "--path unknown profile: exits non-zero"
else
  fail "--path unknown profile: expected non-zero exit"
fi

# ── summary ───────────────────────────────────────────────────────────────────

printf '\n=== results: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
