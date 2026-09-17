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

# A fake global skills tree mirroring a real ~/.claude/skills: real dirs, a
# relative symlink into a sibling tree (the two-hop chain), a bare .md skill,
# a dotfile that must be ignored, and a dangling link.
GLOBAL="$TMP/global/.claude/skills"
AGENTS="$TMP/global/.agents/skills"
mkdir -p "$GLOBAL/capacity-planning" "$AGENTS/archify"
printf 'archify\n' >"$AGENTS/archify/SKILL.md"
printf 'capacity\n' >"$GLOBAL/capacity-planning/SKILL.md"
ln -s ../../.agents/skills/archify "$GLOBAL/archify"
printf 'feedback\n' >"$GLOBAL/feedback-analyzer.md"
printf 'junk\n' >"$GLOBAL/.DS_Store"
ln -s /nonexistent/gone "$GLOBAL/broken"

MANIFEST="$PROFILE_HOME/.global-skills"

CLAUDE_AS="$REPO_DIR/bin/claude-as"

# Run claude-as with the stub claude in PATH and an isolated profile home
run() {
  env PATH="$STUB_BIN:$PATH" CLAUDE_PROFILE_HOME="$PROFILE_HOME" \
    CLAUDE_GLOBAL_SKILLS="$GLOBAL" "$CLAUDE_AS" "$@"
}

# Same, with an overridden global skills dir (for normalization tests)
run_with_global() {
  local g="$1"
  shift
  env PATH="$STUB_BIN:$PATH" CLAUDE_PROFILE_HOME="$PROFILE_HOME" \
    CLAUDE_GLOBAL_SKILLS="$g" "$CLAUDE_AS" "$@"
}

# Forget every shared skill and every link the tool made
reset_skills() {
  rm -f "$MANIFEST"
  rm -rf "$PROFILE_HOME"/*/skills
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

# ── --sync-skills ─────────────────────────────────────────────────────────────

# --list before any manifest exists
output="$(run --sync-skills --list 2>/dev/null)"
exit_code=0
run --sync-skills --list >/dev/null 2>&1 || exit_code=$?
if [[ -z "$output" ]] && [[ $exit_code -eq 0 ]]; then
  ok "--sync-skills --list: empty and exits 0 with no manifest"
else
  fail "--sync-skills --list: expected empty/exit 0, got '$output' exit $exit_code"
fi

# Sharing one skill links it into every profile
run --sync-skills archify >/dev/null 2>&1
if [[ -L "$PROFILE_HOME/work/skills/archify" ]] &&
  [[ -L "$PROFILE_HOME/personal/skills/archify" ]]; then
  ok "--sync-skills: links the skill into every profile"
else
  fail "--sync-skills: expected symlinks in work and personal"
fi

if [[ "$(run --sync-skills --list 2>/dev/null)" == "archify" ]]; then
  ok "--sync-skills: manifest records the skill"
else
  fail "--sync-skills: manifest should contain 'archify'"
fi

# The two-hop chain must resolve: profile -> global -> ../../.agents/skills
if [[ -f "$PROFILE_HOME/work/skills/archify/SKILL.md" ]]; then
  ok "--sync-skills: symlink-to-symlink chain resolves"
else
  fail "--sync-skills: could not read through the chain to SKILL.md"
fi

# Re-running is idempotent and must not nest inside the global tree
exit_code=0
run --sync-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 0 ]] && [[ -L "$PROFILE_HOME/work/skills/archify" ]]; then
  ok "--sync-skills: re-run is idempotent and exits 0"
else
  fail "--sync-skills: re-run should exit 0 and keep the symlink, exit $exit_code"
fi
if [[ ! -e "$GLOBAL/archify/archify" ]]; then
  ok "--sync-skills: does not write inside the global skills tree"
else
  fail "--sync-skills: created \$GLOBAL/archify/archify (ln -sf footgun)"
fi

# A bare .md skill resolves from its stem
run --sync-skills feedback-analyzer >/dev/null 2>&1
if [[ -L "$PROFILE_HOME/work/skills/feedback-analyzer.md" ]] &&
  [[ -f "$PROFILE_HOME/work/skills/feedback-analyzer.md" ]]; then
  ok "--sync-skills: resolves 'feedback-analyzer' to feedback-analyzer.md"
else
  fail "--sync-skills: .md skill was not linked"
fi

# A trailing slash on CLAUDE_GLOBAL_SKILLS must not cause endless relinking
before="$(readlink "$PROFILE_HOME/work/skills/archify")"
exit_code=0
run_with_global "$GLOBAL/" --sync-skills >/dev/null 2>&1 || exit_code=$?
after="$(readlink "$PROFILE_HOME/work/skills/archify")"
if [[ $exit_code -eq 0 ]] && [[ "$before" == "$after" ]]; then
  ok "trailing-slash CLAUDE_GLOBAL_SKILLS: still idempotent"
else
  fail "trailing-slash CLAUDE_GLOBAL_SKILLS: link churned '$before' -> '$after'"
fi

exit_code=0
run_with_global "relative/path" --sync-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  ok "relative CLAUDE_GLOBAL_SKILLS: rejected"
else
  fail "relative CLAUDE_GLOBAL_SKILLS: should have been rejected"
fi

exit_code=0
run_with_global "$TMP/no-such-skills" --sync-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  ok "missing CLAUDE_GLOBAL_SKILLS: exits non-zero"
else
  fail "missing CLAUDE_GLOBAL_SKILLS: should have exited non-zero"
fi

# Unknown skill names are a partial failure (2), not a usage error (1)
exit_code=0
err="$(run --sync-skills no-such-skill 2>&1)" || exit_code=$?
if [[ $exit_code -eq 2 ]] && [[ "$err" == *"no-such-skill"* ]]; then
  ok "--sync-skills unknown skill: exits 2 and names it"
else
  fail "--sync-skills unknown skill: expected exit 2 naming it, got $exit_code: $err"
fi

# The same name twice must be enrolled once
run --sync-skills capacity-planning capacity-planning >/dev/null 2>&1
count="$(run --sync-skills --list 2>/dev/null | grep -c '^capacity-planning$' || true)"
if [[ "$count" -eq 1 ]]; then
  ok "--sync-skills duplicate name: enrolled once"
else
  fail "--sync-skills duplicate name: expected 1 manifest entry, got $count"
fi

# Manifest is sorted and deduplicated
output="$(run --sync-skills --list 2>/dev/null)"
if [[ "$output" == "$(printf '%s\n' "$output" | sort -u)" ]]; then
  ok "--sync-skills: manifest is sorted and deduplicated"
else
  fail "--sync-skills: manifest not sorted/deduped: $output"
fi

# A dangling symlink at the target is repaired, not reported as a conflict
rm -f "$PROFILE_HOME/work/skills/archify"
ln -s /nonexistent/stale "$PROFILE_HOME/work/skills/archify"
exit_code=0
run --sync-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 0 ]] &&
  [[ "$(readlink "$PROFILE_HOME/work/skills/archify")" == "$GLOBAL/archify" ]]; then
  ok "--sync-skills: repairs a dangling target symlink"
else
  fail "--sync-skills: dangling target not repaired (exit $exit_code)"
fi

# --all enrolls real entries and ignores dotfiles
reset_skills
run --sync-skills --all >/dev/null 2>&1
output="$(run --sync-skills --list 2>/dev/null)"
if [[ "$output" == *"archify"* ]] && [[ "$output" == *"capacity-planning"* ]] &&
  [[ "$output" == *"feedback-analyzer.md"* ]]; then
  ok "--sync-skills --all: enrolls every real skill"
else
  fail "--sync-skills --all: missing entries, got: $output"
fi
if [[ "$output" != *"DS_Store"* ]]; then
  ok "--sync-skills --all: ignores dotfiles"
else
  fail "--sync-skills --all: should not enroll .DS_Store"
fi

# A profile's own skill directory is never replaced
reset_skills
mkdir -p "$PROFILE_HOME/personal/skills/capacity-planning"
printf 'mine\n' >"$PROFILE_HOME/personal/skills/capacity-planning/SKILL.md"
exit_code=0
err="$(run --sync-skills capacity-planning 2>&1)" || exit_code=$?
if [[ $exit_code -eq 2 ]] && [[ ! -L "$PROFILE_HOME/personal/skills/capacity-planning" ]] &&
  [[ "$(cat "$PROFILE_HOME/personal/skills/capacity-planning/SKILL.md")" == "mine" ]]; then
  ok "--sync-skills conflict: profile-local skill kept intact, exits 2"
else
  fail "--sync-skills conflict: local skill not preserved (exit $exit_code)"
fi
if [[ -L "$PROFILE_HOME/work/skills/capacity-planning" ]]; then
  ok "--sync-skills conflict: other profiles still processed"
else
  fail "--sync-skills conflict: work should still have been linked"
fi
rm -rf "$PROFILE_HOME/personal/skills/capacity-planning"

# The Claude-Code-managed synced/ bucket must survive
mkdir -p "$PROFILE_HOME/work/skills/synced"
printf 'keep\n' >"$PROFILE_HOME/work/skills/synced/keepme"
run --sync-skills >/dev/null 2>&1
if [[ -f "$PROFILE_HOME/work/skills/synced/keepme" ]]; then
  ok "--sync-skills: leaves the managed synced/ bucket alone"
else
  fail "--sync-skills: clobbered skills/synced/"
fi

exit_code=0
run --sync-skills synced >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -ne 0 ]]; then
  ok "--sync-skills synced: reserved name rejected"
else
  fail "--sync-skills synced: should be rejected"
fi

# A profile whose skills path is a regular file is reported, others continue
mkdir -p "$PROFILE_HOME/broken-profile"
printf 'not a dir\n' >"$PROFILE_HOME/broken-profile/skills"
exit_code=0
run --sync-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 2 ]] && [[ -L "$PROFILE_HOME/work/skills/capacity-planning" ]]; then
  ok "skills path is a file: reported, other profiles still processed"
else
  fail "skills path is a file: expected exit 2 and work still linked, got $exit_code"
fi
rm -rf "$PROFILE_HOME/broken-profile"

# --profile scopes application to one profile
reset_skills
run --sync-skills archify >/dev/null 2>&1
rm -rf "$PROFILE_HOME"/*/skills
run --sync-skills --profile work >/dev/null 2>&1
if [[ -L "$PROFILE_HOME/work/skills/archify" ]] &&
  [[ ! -e "$PROFILE_HOME/personal/skills/archify" ]]; then
  ok "--sync-skills --profile: applies to that profile only"
else
  fail "--sync-skills --profile: scoping failed"
fi

for bad_args in "--profile nosuch" "--all archify" "--list --all"; do
  exit_code=0
  # shellcheck disable=SC2086
  run --sync-skills $bad_args >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 1 ]]; then
    ok "--sync-skills $bad_args: usage error (exit 1)"
  else
    fail "--sync-skills $bad_args: expected exit 1, got $exit_code"
  fi
done

exit_code=0
run --sync-skills archify --profile work >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 1 ]]; then
  ok "--sync-skills <name> --profile: rejected (manifest is global)"
else
  fail "--sync-skills <name> --profile: expected exit 1, got $exit_code"
fi

for bad in "../etc" "foo/bar" "foo bar" ".hidden"; do
  exit_code=0
  run --sync-skills "$bad" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 1 ]]; then
    ok "invalid skill name '$bad': rejected"
  else
    fail "invalid skill name '$bad': expected exit 1, got $exit_code"
  fi
done

# With no profiles at all the manifest is still saved
EMPTY_HOME="$TMP/empty-profiles"
mkdir -p "$EMPTY_HOME"
exit_code=0
env PATH="$STUB_BIN:$PATH" CLAUDE_PROFILE_HOME="$EMPTY_HOME" \
  CLAUDE_GLOBAL_SKILLS="$GLOBAL" "$CLAUDE_AS" --sync-skills archify >/dev/null 2>&1 ||
  exit_code=$?
if [[ $exit_code -eq 0 ]] && [[ -f "$EMPTY_HOME/.global-skills" ]]; then
  ok "--sync-skills with no profiles: manifest saved, exits 0"
else
  fail "--sync-skills with no profiles: expected exit 0 and a manifest, got $exit_code"
fi

# A new profile inherits the shared skills
reset_skills
run --sync-skills archify >/dev/null 2>&1
run --new fresh >/dev/null 2>&1
if [[ -L "$PROFILE_HOME/fresh/skills/archify" ]]; then
  ok "--new: inherits the shared skills"
else
  fail "--new: new profile did not inherit shared skills"
fi

exit_code=0
run --new .global-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -ne 0 ]] && [[ -f "$MANIFEST" ]]; then
  ok "--new .global-skills: leading-dot profile name rejected"
else
  fail "--new .global-skills: should be rejected without touching the manifest"
fi

# ── --unsync-skills ───────────────────────────────────────────────────────────

reset_skills
run --sync-skills archify capacity-planning >/dev/null 2>&1
run --unsync-skills archify >/dev/null 2>&1
if [[ ! -e "$PROFILE_HOME/work/skills/archify" ]] &&
  [[ -L "$PROFILE_HOME/work/skills/capacity-planning" ]]; then
  ok "--unsync-skills: removes only the named skill"
else
  fail "--unsync-skills: wrong links removed"
fi
if [[ "$(run --sync-skills --list 2>/dev/null)" == "capacity-planning" ]]; then
  ok "--unsync-skills: drops the entry from the manifest"
else
  fail "--unsync-skills: manifest should only contain capacity-planning"
fi

# A profile-local directory and a foreign symlink are both left alone
mkdir -p "$PROFILE_HOME/personal/skills"
rm -rf "$PROFILE_HOME/personal/skills/capacity-planning"
mkdir -p "$PROFILE_HOME/personal/skills/capacity-planning"
printf 'mine\n' >"$PROFILE_HOME/personal/skills/capacity-planning/SKILL.md"
ln -s "$TMP/elsewhere" "$PROFILE_HOME/work/skills/foreign"
run --sync-skills foreign >/dev/null 2>&1 || true
exit_code=0
run --unsync-skills capacity-planning >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 2 ]] &&
  [[ -f "$PROFILE_HOME/personal/skills/capacity-planning/SKILL.md" ]]; then
  ok "--unsync-skills: leaves a profile-local directory alone, exits 2"
else
  fail "--unsync-skills: local directory not preserved (exit $exit_code)"
fi
if [[ -L "$PROFILE_HOME/work/skills/foreign" ]]; then
  ok "--unsync-skills: leaves a foreign symlink alone"
else
  fail "--unsync-skills: removed a symlink it did not create"
fi

# synced/ survives unsharing too
mkdir -p "$PROFILE_HOME/work/skills/synced"
printf 'keep\n' >"$PROFILE_HOME/work/skills/synced/keepme"
run --unsync-skills --all >/dev/null 2>&1 || true
if [[ -f "$PROFILE_HOME/work/skills/synced/keepme" ]]; then
  ok "--unsync-skills --all: leaves the managed synced/ bucket alone"
else
  fail "--unsync-skills --all: clobbered skills/synced/"
fi
if [[ -z "$(run --sync-skills --list 2>/dev/null)" ]]; then
  ok "--unsync-skills --all: clears the manifest"
else
  fail "--unsync-skills --all: manifest should be empty"
fi
if [[ ! -e "$MANIFEST" ]]; then
  ok "--unsync-skills --all: removes the manifest file"
else
  fail "--unsync-skills --all: left an empty manifest behind"
fi

exit_code=0
run --unsync-skills >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 1 ]]; then
  ok "--unsync-skills with no arguments: usage error"
else
  fail "--unsync-skills with no arguments: expected exit 1, got $exit_code"
fi

exit_code=0
run --unsync-skills --all archify >/dev/null 2>&1 || exit_code=$?
if [[ $exit_code -eq 1 ]]; then
  ok "--unsync-skills --all with names: usage error"
else
  fail "--unsync-skills --all with names: expected exit 1, got $exit_code"
fi

reset_skills

# ── summary ───────────────────────────────────────────────────────────────────

printf '\n=== results: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
