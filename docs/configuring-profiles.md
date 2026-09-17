# Configuring and using Claude Code profiles

This guide walks through everything from installation to day-to-day use.

## Requirements

- Claude Code 2.1.x or later (`claude --version`)
- macOS (Keychain-based credential isolation), or Linux with an unlocked keyring
- `~/.local/bin` on your `PATH` (already true if you installed Claude Code the standard
  way — verify with `echo $PATH | tr ':' '\n' | grep local/bin`)

## Install

### Option A — executable only (recommended for most people)

```sh
cd ~/github/claude-profiles
./install.sh
```

This symlinks `bin/claude-as` into `~/.local/bin`, which is already on your `PATH`.
No shell restart needed; `claude-as` is available immediately.

### Option B — with zsh shell integration

```sh
./install.sh --with-zsh
```

Adds the source line to `~/.zshrc`, enabling `claude-profile-use`,
`claude-profile-unuse`, `claude-profile-current`, and tab-completion.
Reload your shell: `source ~/.zshrc`.

### Verify

```sh
command -v claude-as       # should print ~/.local/bin/claude-as
claude-as --help
```

## Updating an existing install

`install.sh` symlinks `bin/claude-as` into `~/.local/bin` rather than copying it, and
`--with-zsh` adds a `source` line pointing at `shell/claude-profiles.zsh` in the repo. Both
therefore track the repo, so **pulling is the whole update**:

```sh
cd ~/github/claude-profiles
git pull                   # claude-as is a symlink into the repo — this is enough
exec zsh                   # only needed to pick up new shell functions / completions
claude-as --help           # confirm the new commands are listed
```

Re-running `./install.sh` is **not** required for an update. You only need it if:

- `~/.local/bin/claude-as` is missing or dangling (`ls -l "$(command -v claude-as)"` should
  resolve into the repo)
- your original install copied the script instead of symlinking it
- you skipped shell integration the first time and now want it: `./install.sh --with-zsh`

`install.sh` is idempotent — it re-points the symlink with `ln -sf` and detects an existing
`~/.zshrc` block by its marker comment, so running it again is always safe.

### Am I up to date?

```sh
git -C ~/github/claude-profiles status -sb        # shows drift against origin/main
git -C ~/github/claude-profiles log --oneline -1  # the commit you are running
claude-as --help | grep -q -- --sync-skills && echo "has skill sharing"
```

Updating only touches the repo and `~/.local/bin`. Profile directories, credentials, and your
shared-skills list are never modified by a pull.

> After updating, existing profiles pick up a newly added feature the next time you use it —
> for skill sharing, run `claude-as --sync-skills` once. Profiles created afterwards inherit
> shared skills automatically.

## Create your first profile

```sh
claude-as --new personal
```

This creates `~/.claude-profiles/personal/` and opens a browser tab to sign in.
After authenticating, the profile is ready.

> **Note:** if you already have a `personal/` directory from a previous setup attempt,
> `--new` detects this and goes straight to sign-in rather than failing.

To add more accounts:

```sh
claude-as --new work
claude-as --new contractor
```

## Command reference

| Goal | Command |
|---|---|
| Start on your default account | `claude` — unchanged, no env var |
| Start on a profile | `claude-as personal` |
| List profiles | `claude-as --list` |
| Create a profile and sign in | `claude-as --new personal` |
| Check which account is signed in | `claude auth status` / `claude-as personal auth status` |
| Resume the last session | `claude-as personal --resume` |
| Continue most recent conversation | `claude-as personal -c` |
| Non-interactive output | `claude-as personal -p "your prompt"` |
| Manage background agents | `claude-as personal agents` |
| Sign a profile out | `claude-as personal auth logout` |
| Print a profile's config dir | `claude-as --path personal` |
| Share a global skill with every profile | `claude-as --sync-skills pr-description` |
| Re-apply after installing a new skill | `claude-as --sync-skills` |
| List the shared skills | `claude-as --sync-skills --list` |
| Stop sharing a skill | `claude-as --unsync-skills pr-description` |
| One-off without the helper | `CLAUDE_CONFIG_DIR=~/.claude-profiles/personal claude` |

Everything after the profile name is forwarded verbatim to `claude` — any flag,
subcommand, or slash command that works with `claude` works with `claude-as`.

## Using two accounts at the same time

Open two terminal windows (or tabs):

```sh
# Window 1 — work account (default)
claude

# Window 2 — personal account
claude-as personal
```

Both sessions run concurrently and independently. Because their Keychain items differ,
both stay signed in with no token collision.

> Background agents are per-profile: `claude-as personal agents` sees only jobs started
> from the personal profile. A plain `claude agents` shows the default account's jobs.

## In-shell switching (zsh only, requires `--with-zsh`)

If you installed with shell integration:

```sh
claude-profile-use personal     # every `claude` in this terminal uses the personal account
claude-profile-current          # show which profile this shell is using
claude                          # runs as personal
claude-profile-unuse            # back to the default account
```

This is different from `claude-as`, which only affects one command. Use `claude-profile-use`
when you want a whole terminal session pinned to one account.

## What is NOT shared between profiles

Each profile is completely independent. These things are **not** shared:

- **Credentials and account** — each profile has its own Keychain item and `.claude.json`
- **Settings** — `settings.json`, MCP server config, hooks (copied manually if wanted)
- **History** — `history.jsonl`, conversation transcripts under `projects/`
- **Skills and agents** — `skills/`, `agents/`, `commands/`, `plugins/` (skills can be shared
  opt-in, see below)
- **CLAUDE.md** — global user instructions
- **Trust decisions** — each profile starts with a fresh trust state
- **Background agents** — their own daemon socket and task list

A new profile runs Claude Code onboarding once (theme, trust prompts). This is expected.

### Sharing skills across profiles

A skill you install globally into `~/.claude/skills` is invisible to every profile, because
`CLAUDE_CONFIG_DIR` scopes skill lookup to `<profile>/skills`. `--sync-skills` fixes that: it
keeps a list of skills you have chosen to share and symlinks each one into every profile.

```sh
claude-as --sync-skills pr-description archify   # share these, everywhere
claude-as --sync-skills                          # re-apply after installing a new skill
claude-as --sync-skills --all                    # share everything in ~/.claude/skills
claude-as --sync-skills --list                   # show what is shared
claude-as --unsync-skills archify                # stop sharing one
```

The list lives in `~/.claude-profiles/.global-skills` and is shared by all profiles. New
profiles inherit it at `claude-as --new` time, so you only have to choose once. To apply the
list to a single profile, use `claude-as --sync-skills --profile personal`.

Because each skill is linked individually, nothing else in `<profile>/skills` is disturbed —
in particular, Claude Code's own managed `synced/` directory and any skill you wrote just for
that profile are left alone. A profile-local skill always wins: if `<profile>/skills/<name>`
already exists as a real directory, it is reported and skipped rather than replaced.

> Do not symlink the whole `~/.claude/skills` directory over `<profile>/skills`. That shadows
> the `synced/` bucket Claude Code manages inside it.

Skills are linked, not copied, so editing a global skill takes effect in every profile at once.
Removing a global skill leaves a dangling link behind; `claude-as --sync-skills` reports it and
`claude-as --unsync-skills <name>` cleans it up.

To share other config, symlink it yourself — for example:

```sh
ln -s ~/.claude/CLAUDE.md ~/.claude-profiles/personal/CLAUDE.md
```

## Troubleshooting

**Profile keeps asking me to sign in every time**

The profile directory might be missing its `.credentials.json` or the Keychain item was
deleted. Re-authenticate:

```sh
claude-as personal auth login
```

**`claude agents` shows nothing after I started a job with `claude-as personal`**

Background agents are per-profile socket. Use the same profile to manage them:

```sh
claude-as personal agents
```

A plain `claude agents` talks to the default account's daemon.

**Tab-completion for profile names isn't working**

Ensure shell integration is sourced. Check:

```sh
which _claude-as 2>/dev/null || echo "completion not loaded"
```

If it prints nothing, source the file:

```sh
source ~/github/claude-profiles/shell/claude-profiles.zsh
```

Or re-run `./install.sh --with-zsh`.

**How do I confirm which account a session is using?**

Inside any Claude Code session, run `/status` — it shows the signed-in email. Or from
the shell:

```sh
claude auth status                      # default account
claude-as personal auth status          # personal profile
```

**I renamed or moved the profile directory**

The Keychain item is hashed from the original path. After moving, sign out the profile
at its old path (if accessible), delete the Keychain item manually (see
`docs/uninstalling.md` → "Orphan Keychain recovery"), and then log into the new path:

```sh
CLAUDE_CONFIG_DIR=/new/path claude auth login
```
