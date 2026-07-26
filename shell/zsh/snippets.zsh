# ~/dots/shell/zsh/snippets.zsh — where the memorised verbs went.
#
# `revshell`, `tunnel`, `dl`, `upgrade-shell`, `crack` and all of ad.sh used to
# be functions. Each one was a name you had to remember in order to avoid
# remembering a command — and the ledger then recorded the wrapper instead of
# the command, which is the wrong way round for both learning and reporting.
#
# ^X^S searches the same content and puts the real command in the buffer with
# the session's values filled in. Nothing runs until you press enter, so you
# read and edit it first, and what gets logged is what you actually ran.

: ${RT_SNIPPETS:=${RT_DOTFILES:-$HOME/dots}/snippets}
export RT_SNIPPETS

# --- fill --------------------------------------------------------------------
# Unset variables keep their {{NAME}} placeholder rather than collapsing to an
# empty string: a visible hole is a prompt to fill it, an invisible one is a
# command that silently does the wrong thing.
_rt_snippet_fill() {
    local s=$1 k v
    local -A map=(
        LHOST  "${LHOST-}"        RHOST  "${RHOST-}"
        DOMAIN "${DOMAIN-}"       DC     "${DC-}"
        U      "${U-}"            P      "${P-}"
        PORT   "${PORT:-4444}"    HASH   "${HASH-}"
        FILE   "${FILE-}"         SUBNET "${SUBNET-}"
    )
    for k v in "${(@kv)map}"; do
        [[ -n $v ]] && s=${s//\{\{$k\}\}/$v}
    done
    print -r -- "$s"
}

# --- picker --------------------------------------------------------------------
rt-snippets() {
    if ! command -v fzf >/dev/null; then
        zle -M "snippets: fzf not installed (tools/install-tools.sh)"; return
    fi
    # Reverse shells and transfers are worthless without it, and working it out
    # is exactly the kind of errand this layer is supposed to run for you.
    [[ -n $LHOST ]] || lhost >/dev/null 2>&1

    local sel
    sel=$(rt-snippet-list | fzf \
            --delimiter=$'\t' --nth=1,2 --query="$BUFFER" \
            --prompt='snippet> ' --no-sort --height=70% --layout=reverse --border \
            --preview='printf "%s\n" {3} | fold -s -w ${FZF_PREVIEW_COLUMNS:-80}' \
            --preview-window='down:30%:wrap' \
            --header='enter inserts into the buffer · nothing runs until you press it again' \
        ) || { zle reset-prompt; return }

    if [[ -n $sel ]]; then
        local -a f; f=( "${(@s:	:)sel}" )
        BUFFER=$(_rt_snippet_fill "${f[3]}")
        CURSOR=${#BUFFER}
    fi
    zle reset-prompt
}
zle -N rt-snippets
bindkey '^X^S' rt-snippets

# --- payload picker, promoted from function to widget --------------------------
# `payload` (shell/zsh.sh) still works as a command; this puts the chosen path
# straight into the line you are already typing.
rt-payload() {
    local p
    p=$(payload 2>/dev/null | tail -1) || { zle reset-prompt; return }
    if [[ -n $p && -e $p ]]; then
        LBUFFER+="$p"
    fi
    zle reset-prompt
}
zle -N rt-payload
bindkey '^X^P' rt-payload
