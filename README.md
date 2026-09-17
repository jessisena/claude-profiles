# claude-profiles

Switch between Claude Code accounts with one command.

```sh
claude-as personal        # open claude as your personal account
claude-as work            # open claude as your work account
claude                    # open claude as the default (unchanged)
```

Built on `CLAUDE_CONFIG_DIR`, the isolation primitive in Claude Code itself. Each profile
gets its own Keychain item, config, history, skills, and background-agent supervisor.
The default `~/.claude` is never touched.

## Quickstart

```sh
# 1. Install
cd ~/github/claude-profiles
./install.sh

# 2. Create a profile and sign in
claude-as --new personal

# 3. Start using it
claude-as personal
claude-as personal auth status
claude-as personal agents
```

## Install options

| Command                   | What it does                                                                    |
| ------------------------- | ------------------------------------------------------------------------------- |
| `./install.sh`            | Symlink `claude-as` into `~/.local/bin` — works immediately, no shell restart   |
| `./install.sh --with-zsh` | Also add shell integration to `~/.zshrc` (tab completion, `claude-profile-use`) |
| `./uninstall.sh`          | Remove the symlink and `~/.zshrc` block; leave accounts intact                  |
| `./uninstall.sh --purge`  | Full teardown — sign out, stop daemons, trash profile dirs                      |

## Switching accounts

```sh
claude-as --list                        # see all profiles
claude-as --new personal                # create and sign in
claude-as personal                      # run as personal
claude-as personal auth status          # check account
claude-as personal auth logout          # sign out
```

Every argument after the profile name is forwarded verbatim to `claude`.

Two profiles can run in parallel — each has its own Keychain item and daemon socket.

## Sharing global skills

Skills in `~/.claude/skills` are invisible to profiles. Pick the ones you want everywhere:

```sh
claude-as --sync-skills pr-description  # share it with every profile
claude-as --sync-skills                 # re-apply after installing a new skill
claude-as --sync-skills --all           # share everything
claude-as --sync-skills --list          # show what is shared
claude-as --unsync-skills pr-description
```

Each skill is linked individually, so profile-local skills and Claude Code's managed
`synced/` directory are never touched. New profiles inherit the list automatically.

## Updating

`claude-as` is symlinked into `~/.local/bin`, so a pull is the whole update:

```sh
cd ~/github/claude-profiles && git pull
exec zsh                                # only to refresh completions
```

Re-running `./install.sh` is not needed. See
[docs/configuring-profiles.md](docs/configuring-profiles.md#updating-an-existing-install).

## Shell-level switching (zsh, optional)

After `./install.sh --with-zsh`:

```sh
claude-profile-use personal    # pin this terminal to one account
claude                         # runs as personal
claude-profile-unuse           # back to default
claude-profile-current         # show active profile
```

## Override the profiles directory

```sh
CLAUDE_PROFILE_HOME=/work/projects/profiles claude-as client-a
```

Default: `~/.claude-profiles/`

## Documentation

- **[docs/configuring-profiles.md](docs/configuring-profiles.md)** — setup, all commands, sharing config, troubleshooting
- **[docs/uninstalling.md](docs/uninstalling.md)** — teardown guide, orphan Keychain recovery
- **[docs/plan.md](docs/plan.md)** — how `CLAUDE_CONFIG_DIR` actually works (verified from the Claude Code binary), design decisions

## License

[MIT](LICENSE) — Copyright (c) 2026 Jessica Sena
