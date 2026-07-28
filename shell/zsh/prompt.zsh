# ~/dots/shell/zsh/prompt.zsh — the left prompt.
#
# Ported from https://github.com/vinnydiehl/zshrc (rc.zsh), then recoloured.
# Upstream leans on the terminal's `magenta` slots, which vary by scheme; the
# colours here are pinned to 24-bit hex instead, so the prompt looks the same
# under any theme.
#
# Three hues, plus grey and the alert. Nothing else belongs in this file.
#
# Wants a Nerd Fonts v3 face, but does not require one — see the glyph block.
# Registered as a precmd *hook* rather than as precmd() itself, so Kali's stock
# precmd (terminal title + blank line between prompts) keeps running, and so
# Ctrl-P (toggle_oneline_prompt) can't strand it.
#
# Claims PS1 only; context.zsh owns RPROMPT.
# To disable: add-zsh-hook -d precmd vinny_prompt_precmd

autoload -U colors && colors

# --- glyphs -------------------------------------------------------------------
# The three icons live in the Nerd Fonts private use area (U+F0054 md-arrow_right,
# U+E725 dev-git_branch, U+F4DF oct-hash), so a box without a patched face draws
# three tofu boxes instead of a prompt. That is not hypothetical: the deploy
# scripts install fonts-powerline, which covers U+E0A0-E0D4 and nothing near
# these, so a freshly built box has no font that can render them.
#
# Hence VINNY_ASCII=1, which swaps in plain characters that exist everywhere.
# It is an explicit opt-in rather than a probe because the only reliable test is
# fc-list, and paying a fork on every interactive shell to answer a question that
# never changes for a given box is the wrong trade. Whoever builds the box knows
# the answer already; the deploy scripts set it.
if [[ -n ${VINNY_ASCII:-} ]]; then
    : ${VINNY_G_ARROW:=>}
    : ${VINNY_G_BRANCH:=@}
    : ${VINNY_G_HASH:=#}
else
    : ${VINNY_G_ARROW:=$'\U000F0054'}
    : ${VINNY_G_BRANCH:=$'\ue725'}
    : ${VINNY_G_HASH:=$'\uf4df'}
fi

# --- palette ------------------------------------------------------------------
# All three glyphs share one colour, so they read as a set rather than as three
# separate decorations. Lavender is the only hue-distinct member of the palette,
# which makes it the one that can carry that job.
: ${VINNY_ICON:=#B2A1C0}

# The text. These two are near-twins — desaturated blue-greys about 10 degrees
# apart — so they must never sit adjacent or they look like a near-miss instead
# of a choice. They don't: the lavender branch glyph always falls between them.
# The lighter one takes the path, which is read constantly; the darker one takes
# the branch, which is glanced at.
: ${VINNY_PATH:=#88A9B5}
: ${VINNY_BRANCH:=#83A0A4}

# Exceptions. The two states worth interrupting for — a dirty tree and a
# non-zero exit — stay red, the one colour that already means "wrong" without
# having to be learned. Pinned bright rather than left to the theme: this
# scheme's own reds are Catppuccin pastels (#f38ba8 / #eba0ac) which go soft
# against a palette this muted, and an alert is the last thing that should
# whisper. A true red with no hue lean — it is the one element here that is not
# trying to belong, which is the point. Grey de-emphasises the error parens so
# the exit code itself is what the eye lands on.
: ${VINNY_ALERT:=#FF2D2D}
: ${VINNY_DIM:=242}

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

  # Parse error code (arrow goes red, and the code appears beside it)
  local EXIT="$?"
  if [ $EXIT != 0 ]; then
    PS1="%F{$VINNY_ALERT}${VINNY_G_ARROW} %F{$VINNY_DIM}(%F{$VINNY_ALERT}$EXIT%F{$VINNY_DIM})"
  else
    PS1="%F{$VINNY_ICON}${VINNY_G_ARROW}"
  fi

  # Git (only active when in a repo, branch name goes red when the tree is dirty)
  if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    local git_ps1_branch_color=$VINNY_BRANCH
  else
    local git_ps1_branch_color=$VINNY_ALERT
  fi
  local git_ps1=$(__git_ps1 "%%F{$VINNY_ICON}${VINNY_G_BRANCH} %%F{$git_ps1_branch_color}%s ")

  PS1+=" %F{$VINNY_PATH}%1~ $git_ps1%F{$VINNY_ICON}${VINNY_G_HASH}  %{$reset_color%}"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd vinny_prompt_precmd
