# Design notes — how and why `CLAUDE_CONFIG_DIR` works for account profiles

This document explains the mechanism behind claude-profiles, the research used to verify
it, and the design decisions made along the way. It is written for someone coming to this
repo fresh, not as a setup guide — see `configuring-profiles.md` for that.

## The problem

Claude Code (as of 2.1.x) has no `--profile` flag and no multi-account switcher. The
`claude auth` subcommand exposes only `login`, `logout`, and `status`. On a typical macOS
install:

- Credentials live in a single macOS Keychain item, service `Claude Code-credentials`,
  account `$USER`.
- Global configuration (`oauthAccount`, install settings, etc.) lives in `~/.claude.json`.
- Running `claude auth login` when already authenticated overwrites both — there is no
  "add account" path.

## The mechanism: `CLAUDE_CONFIG_DIR`

Setting `CLAUDE_CONFIG_DIR` redirects all of Claude Code's per-user state to a different
directory. This is how the isolation is actually implemented inside the binary (read from
the shipped executable, not assumed from documentation):

### 1. Credentials / Keychain

```js
// The macOS Keychain service name is derived from the config dir:
function keychainServiceName(scope = "") {
  const redirected = !process.env.CLAUDE_CONFIG_DIR
  const hash = redirected ? "" : `-${sha256(resolve(configDir)).hex.slice(0, 8)}`
  return `Claude Code${OAUTH_FILE_SUFFIX}${scope}${hash}`
}
```

The default account produces `Claude Code-credentials` (no hash suffix).
A profile at `~/.claude-profiles/personal` produces
`Claude Code-credentials-<8 hex chars of sha256(resolved path)>`.

**Each config dir → its own Keychain item. Two accounts can be signed in simultaneously.**

### 2. Global config

```js
// With CLAUDE_CONFIG_DIR set, the global config file is inside that dir.
const globalConfig = path.join(configDir, ".claude.json")
// Default (var unset): ~/.claude.json
```

`oauthAccount`, `userID`, and all install-time preferences are stored here. Profiles are
fully independent.

### 3. Background-agent daemon

```js
// Both daemon config and socket directory are derived from configDir.
const daemonConfig = path.join(configDir, "daemon.json")
const socketDir = path.join("/tmp", `cc-daemon-${uid}`, sha256(resolve(configDir)).slice(0, 8))
```

Two profiles running concurrently each get their own daemon supervisor. `claude agents`
only sees jobs started under the same `CLAUDE_CONFIG_DIR`. This means you must manage
agents under the same profile that launched them — `claude-as work agents`, not just
`claude agents`.

### 4. IDE integration

The IDE lockfile scanner also checks `~/.claude/ide` when `CLAUDE_CONFIG_DIR` is set, so
IDE integration works normally.

## Isolation scope

Each profile directory (`CLAUDE_CONFIG_DIR`) is isolated in:

- **Credentials** — Keychain item, `.credentials.json`
- **Identity** — `.claude.json` → `oauthAccount`, `organizationUuid`, `userID`
- **Config** — `settings.json`, MCP server config, hooks
- **History** — `history.jsonl`, `projects/`
- **Skills and agents** — `skills/`, `agents/`, `commands/`, `plugins/`
- **Background agents** — separate daemon socket, separate `tasks/`

There is no implicit sharing. A new profile starts completely empty and runs onboarding
once (theme selection, trust prompts). To share skills or config, symlink them manually —
see `configuring-profiles.md`.

## Why `exec env VAR=value claude`, not `export VAR`

The `claude-as` executable uses:

```bash
exec env CLAUDE_CONFIG_DIR="$dir" claude "$@"
```

- `exec` replaces the script process — there is no wrapper process sitting between you
  and claude.
- `env VAR=value` scopes the variable to that one child process. The parent shell's
  environment is untouched; a subsequent plain `claude` in the same terminal still uses
  `~/.claude`.

The alternative, `export CLAUDE_CONFIG_DIR="$dir" && claude`, would pollute the calling
shell. `claude-profile-use` in `shell/claude-profiles.zsh` does the persistent-export
thing deliberately, for people who want every `claude` in that terminal session to use the
profile.

## What was NOT used: `CLAUDE_SECURESTORAGE_CONFIG_DIR`

There is a second, narrower environment variable that overrides only the credential store
and the Keychain service hash:

```js
function credentialsDir() {
  const v = process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR
  return v !== undefined ? (v || join(homedir(), ".claude")) : configDir()
}
```

Setting only this variable would swap Keychain items while leaving one shared `~/.claude`
and one shared `~/.claude.json`. The problem: `oauthAccount` lives in `~/.claude.json`,
so it would be overwritten on every sign-in, and project history, trust decisions and MCP
auth state would be commingled across accounts. `CLAUDE_CONFIG_DIR` is the right primitive
for true account separation; `CLAUDE_SECURESTORAGE_CONFIG_DIR` is for container/host
environments that mount credentials separately from config.

## Naming: why `claude-as`

The command was originally drafted as `ccp` ("claude code profile"). That name was
rejected: it is an opaque three-letter abbreviation, it visually collides with `cp` and
`scp`, and it gives no hint that it switches accounts. `claude-as personal` reads as what
it does. Both names are free on a standard macOS system; `cc` is not (`/usr/bin/cc`).

## Related project

`ukogan/claude-account-switcher` solves the same problem using the same mechanism. It
ships a richer interactive interface (a `claude-profile` function with `current`,
`create`, `list`, `switch`, and `delete` subcommands) and a `~/.zsh_functions` install
approach. This repo is a simpler, docs-first alternative.

## Verification commands

These commands confirm the mechanism directly, without running a real sign-in:

**Keychain service name for a profile:**
```sh
dir="$HOME/.claude-profiles/personal"
hash=$(printf '%s' "$dir" | shasum -a 256 | cut -c1-8)
echo "service: Claude Code-credentials-$hash"
```

**Confirm two Keychain items after logging into a profile:**
```sh
security find-generic-password -s "Claude Code-credentials" >/dev/null && echo "default ok"
security find-generic-password -s "Claude Code-credentials-$hash" >/dev/null && echo "profile ok"
```

**Confirm which account is active in each:**
```sh
claude auth status
claude-as personal auth status
```

**Confirm per-profile daemon sockets:**
```sh
ls /tmp/cc-daemon-$(id -u)/
# should show two directories after starting sessions in both profiles
```
