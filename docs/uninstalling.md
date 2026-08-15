# Uninstalling claude-profiles

This guide explains how to remove the tooling at two levels: removing the commands while
leaving your accounts intact, or a full teardown that restores the machine to exactly its
pre-profiles state.

## What this uninstaller does NOT touch

Regardless of the option you choose, the following are **never modified or deleted**:

- `~/.claude` — your default account directory
- `~/.claude.json` — your default account global config and identity
- The `Claude Code-credentials` macOS Keychain item (default account)
- The Claude Code installation itself (`~/.local/bin/claude`, `~/.local/share/claude/`)

---

## Tier 1 — remove the tooling, keep the accounts

```sh
./uninstall.sh
```

This removes:
- The `~/.local/bin/claude-as` symlink
- The `# >>> claude-profiles >>>` ... `# <<< claude-profiles <<<` block from `~/.zshrc`
  (only if it was added by `install.sh --with-zsh`)

Your profile directories stay intact. Every account you've signed into remains signed in.
You can still use them directly with the long form:

```sh
CLAUDE_CONFIG_DIR=~/.claude-profiles/personal claude
```

---

## Tier 2 — full teardown

```sh
./uninstall.sh --purge
```

This does everything in Tier 1, plus:

1. Signs each profile out (removes its Keychain item through the supported path)
2. Stops any per-profile background daemons
3. Moves the entire `~/.claude-profiles/` directory to the macOS Trash

Order matters: sign out *before* deleting. Deleting the directory first leaves an orphan
Keychain item that is invisible in `~/` and only findable by hash — see the recovery
section below if this happens.

`trash` must be installed (`brew install trash`). The script refuses to run `--purge`
without it to avoid `rm -rf` on a directory containing account data.

---

## Manual teardown (same steps, by hand)

If you prefer not to use the script:

### Step 1 — sign each profile out

```sh
claude-as --list
# for each profile name:
claude-as <name> auth logout
```

`logout` removes that profile's Keychain item. Confirm it's gone:

```sh
dir=~/.claude-profiles/<name>
h=$(printf '%s' "$dir" | shasum -a 256 | cut -c1-8)
security find-generic-password -s "Claude Code-credentials-$h" 2>&1
# expect: "could not be found in the keychain"
```

### Step 2 — stop per-profile daemons

```sh
claude-as <name> daemon stop --any
```

The socket directory under `/tmp/cc-daemon-$(id -u)/` disappears. A reboot also clears
it — it is `/tmp`.

### Step 3 — remove the profile data

```sh
trash ~/.claude-profiles
```

Never use `rm -rf` on this directory; Trash is recoverable.

### Step 4 — remove this repo

```sh
trash ~/github/claude-profiles
```

### Step 5 — remove the symlink

```sh
rm ~/.local/bin/claude-as
```

### Step 6 — remove the ~/.zshrc block (if added)

Open `~/.zshrc` and remove the lines between and including:

```
# >>> claude-profiles >>>
...
# <<< claude-profiles <<<
```

---

## Orphan Keychain recovery

If you deleted a profile directory before signing out, the Keychain item is stranded.
The service name is deterministic, so you can reconstruct it:

```sh
# Replace this with the path the profile directory HAD before deletion
dir="$HOME/.claude-profiles/personal"
h=$(printf '%s' "$dir" | shasum -a 256 | cut -c1-8)

# Confirm the item exists
security find-generic-password -s "Claude Code-credentials-$h" -a "$USER"

# Delete it
security delete-generic-password -s "Claude Code-credentials-$h" -a "$USER"
```

Each profile has exactly one Keychain item. The hash covers the full resolved path, so
`~/.claude-profiles/personal` and `/Users/<you>/.claude-profiles/personal` may
produce different hashes if one is a symlink. Use the same form you passed to
`CLAUDE_CONFIG_DIR`.

---

## Verify you're clean

Run these after a full teardown:

```sh
command -v claude-as          # expect: nothing
ls ~/.claude-profiles         # expect: No such file or directory
rg -n claude-profiles ~/.zshrc  # expect: no matches
claude auth status            # expect: your original default account
```

The last command is the most important. Your default `~/.claude` account should be
completely untouched and reporting the same email it did before you installed this tool.
