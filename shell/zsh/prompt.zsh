# ~/dots/shell/zsh/prompt.zsh — the left prompt, in neon.
#
# Ported from https://github.com/vinnydiehl/zshrc (rc.zsh), then recoloured:
# upstream leans on the terminal's `magenta` slots, which under Neowave Mocha
# are Catppuccin pastels (#cba6f7 / #f5c2e7) and read muted. The glyphs are
# pinned to 24-bit hex instead, so they stay neon under any scheme.
#
# Needs a Nerd Fonts v3 face: U+F0054 md-arrow_right, U+E725 dev-git_branch,
# U+F4DF oct-hash. Registered as a precmd *hook* rather than as precmd()
# itself, so Kali's stock precmd (terminal title + blank line between prompts)
# keeps running, and so Ctrl-P (toggle_oneline_prompt) can't strand it.
#
# Claims PS1 only; context.zsh owns RPROMPT.
# To disable: add-zsh-hook -d precmd vinny_prompt_precmd

autoload -U colors && colors

# Neon accents for the prompt glyphs. The terminal palette's magenta slots are
# Catppuccin pastels (#cba6f7 / #f5c2e7), so the icons are pinned to 24-bit hex
# instead — tweak these two values to retune, no other edits needed.
: ${VINNY_NEON_PURPLE:=#c04dff}
: ${VINNY_NEON_PINK:=#ff3ce0}

# $fg[] / $reset_color above; __git_ps1 below. Upstream gets the latter from
# the oh-my-zsh gitfast plugin; Debian/Kali ship it with git itself.
if ! typeset -f __git_ps1 >/dev/null 2>&1; then
  if [ -r /usr/lib/git-core/git-sh-prompt ]; then
    source /usr/lib/git-core/git-sh-prompt
  else
    __git_ps1() { :; }  # fallback: drop the git segment, never break the prompt
  fi
fi

vinny_prompt_precmd() {
  # Build PS1 dynamically

  # Parse error code (changes arrow cyan/red)
  local EXIT="$?"
  if [ $EXIT != 0 ]; then
    PS1="%{$fg[red]%}󰁔 (%F{$VINNY_NEON_PURPLE}$EXIT%{$fg[red]%})"
  else
    PS1="%F{$VINNY_NEON_PINK}󰁔"
  fi

  # Git (only active when in a repo, changes branch name cyan/red)
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    local git_ps1_branch_color=cyan
  else
    local git_ps1_branch_color=red
  fi
  local git_ps1=$(__git_ps1 "%%F{$VINNY_NEON_PURPLE} %%{$fg[$git_ps1_branch_color]%%}%s ")

  PS1+=" %{$fg[cyan]%}%1~ $git_ps1%F{$VINNY_NEON_PURPLE}  %{$reset_color%}"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd vinny_prompt_precmd
