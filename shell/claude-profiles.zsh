# claude-profiles.zsh — optional zsh shell integration for claude-profiles
#
# Adds three functions for in-shell account switching (affects every `claude`
# call in the current shell, not just one command), plus tab-completion for
# the claude-as executable.
#
# Add to ~/.zshrc:
#   source "/path/to/claude-profiles/shell/claude-profiles.zsh"
#
# Or let install.sh --with-zsh do it for you.

export CLAUDE_PROFILE_HOME="${CLAUDE_PROFILE_HOME:-$HOME/.claude-profiles}"

# Switch the current shell's default Claude account.
# Every subsequent `claude` in this terminal will use that profile's credentials.
claude-profile-use() {
  emulate -L zsh
  local name=$1
  if [[ -z $name ]]; then
    print -ru2 "usage: claude-profile-use <profile>"
    print -ru2 "profiles: ${$(claude-profiles)//$'\n'/, }"
    return 1
  fi
  local dir="$CLAUDE_PROFILE_HOME/$name"
  if [[ ! -d $dir ]]; then
    print -ru2 "claude-profile-use: unknown profile '$name'"
    print -ru2 "  create it with: claude-as --new $name"
    return 1
  fi
  export CLAUDE_CONFIG_DIR="$dir"
  print -r "switched to $name ($dir)"
}

# Unset the override — reverts the shell to the default ~/.claude account.
claude-profile-unuse() {
  emulate -L zsh
  unset CLAUDE_CONFIG_DIR
  print -r "back to default account (~/.claude)"
}

# Print the currently active profile name, or "default".
claude-profile-current() {
  emulate -L zsh
  if [[ -z ${CLAUDE_CONFIG_DIR:-} ]]; then
    print -r "default"
    return 0
  fi
  # :t is the zsh 'tail' (basename) modifier
  print -r "${CLAUDE_CONFIG_DIR:t}  (${CLAUDE_CONFIG_DIR})"
}

# Tab-completion for claude-as: first argument is a profile name.
_claude-as() {
  local -a profiles skills
  profiles=( "$CLAUDE_PROFILE_HOME"/*(/N:t) )
  skills=( "${CLAUDE_GLOBAL_SKILLS:-$HOME/.claude/skills}"/*(N:t) )

  # The skill-sharing flags take a list of skill names, so complete those
  # (plus their own options) for every word after the flag.
  case "${words[2]}" in
  --sync-skills | --unsync-skills)
    compadd -- --all --list --profile "${skills[@]}"
    return
    ;;
  esac

  _arguments \
    '(-l --list)'{-l,--list}'[list available profiles]' \
    '(-n --new)'{-n,--new}'[create and sign in to a new profile]:name:' \
    '(-p --path)'{-p,--path}'[print a profile'"'"'s config dir]:profile:($profiles)' \
    '--sync-skills[share global skills with every profile]' \
    '--unsync-skills[stop sharing the named skills]' \
    '(-h --help)'{-h,--help}'[show help]' \
    '1:profile:($profiles)' \
    '*::claude args:'
}
compdef _claude-as claude-as
