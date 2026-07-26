# ~/dots/shell/zsh/recall.zsh — read the command ledger back.
#
# The preexec hook in shell/zshrc has always written a timestamped, box-tagged
# record of every command. Nothing read it. This does, two ways:
#
#   ^X^R                  fzf over the whole ledger, previewing the commands you
#                         ran either side of the hit — the sequence, not the line
#   ghost text            zsh-autosuggestions completes from past engagements,
#                         not just this session's history
#
# Ranking never uses tool names. A denylist of "noise commands" goes stale the
# moment you install something, so entries are judged on shape (does it take
# arguments) and place (was it run under $OPS) — properties that hold for tools
# that do not exist yet.

autoload -Uz add-zsh-hook

: ${RT_CMD_INDEX:=${OPS:-$HOME/ops}/.cmd-index}
: ${RT_CMD_INDEX_MAX:=20000}
export RT_CMD_INDEX                    # bin/rt-recall-* read it from the environment

typeset -ga _rt_recall_mem=()

# --- the trivia rule -----------------------------------------------------------
# A closed, shape-defined set: too short, no arguments at all, or a bare
# navigation builtin. Nothing here names a tool, so `nxc`, `strings`,
# `proxychains`, `aws` and anything you install next are all signal by default.
#
# Mirrored in awk in bin/rt-recall-rows for the picker; tools/selftest.zsh
# asserts the two implementations agree on a shared fixture list.
_rt_trivial() {
    local c=${1##[[:space:]]#}
    (( ${#c} < 4 )) && return 0
    [[ $c != *[[:space:]]* ]] && return 0
    case ${${(z)c}[1]} in
        (cd|ls|ll|la|l|pwd|clear|exit|fg|bg|jobs) return 0 ;;
    esac
    return 1
}

# --- writing -------------------------------------------------------------------
# Called from _rt_cmdlog in shell/zshrc. Everything is recorded; the trivia rule
# only affects presentation, so nothing is ever unrecoverable.
_rt_index_add() {
    local cmd=${1//$'\t'/ } dir=$PWD stamp
    [[ -z ${cmd//[[:space:]]/} ]] && return
    stamp=$(strftime '%F %T' $EPOCHSECONDS 2>/dev/null) || stamp=$(date '+%F %T')
    mkdir -p "${RT_CMD_INDEX:h}" 2>/dev/null || return
    print -r -- "$stamp	$dir	$cmd" >> "$RT_CMD_INDEX"
    _rt_trivial "$cmd" || _rt_recall_mem+=("$cmd")
}

# --- reading -------------------------------------------------------------------
_rt_recall_seed() {
    [[ -r $RT_CMD_INDEX ]] || return
    local -a lines
    lines=( ${(f)"$(tail -n $RT_CMD_INDEX_MAX -- $RT_CMD_INDEX 2>/dev/null)"} )
    # Trim the file when it has outgrown the cap, so startup cost stays flat.
    if (( ${#lines} >= RT_CMD_INDEX_MAX )); then
        print -rl -- $lines > $RT_CMD_INDEX.tmp && mv $RT_CMD_INDEX.tmp $RT_CMD_INDEX
    fi
    local l c
    _rt_recall_mem=()
    for l in $lines; do
        c=${l#*$'\t'}; c=${c#*$'\t'}
        _rt_trivial "$c" || _rt_recall_mem+=("$c")
    done
}
_rt_recall_seed

# --- autosuggestions -----------------------------------------------------------
# Runs per keystroke, so it touches the in-memory array only — never the disk.
_zsh_autosuggest_strategy_cmdlog() {
    (( ${#1} >= 3 )) || return
    local -a hits
    hits=( ${(M)_rt_recall_mem:#${(b)1}*} )
    (( ${#hits} )) && typeset -g suggestion=${hits[-1]}   # last = most recent
}

if (( ${+ZSH_AUTOSUGGEST_STRATEGY} )); then
    ZSH_AUTOSUGGEST_STRATEGY=( history cmdlog completion )
else
    typeset -ga ZSH_AUTOSUGGEST_STRATEGY=( history cmdlog completion )
fi

# --- the picker ----------------------------------------------------------------
# Rendering lives in bin/rt-recall-rows and bin/rt-recall-context so that fzf's
# reload binding — which runs under sh — can call them too.
rt-recall() {
    if ! command -v fzf >/dev/null; then
        zle -M "recall: fzf not installed (tools/install-tools.sh)"; return
    fi
    if [[ ! -s $RT_CMD_INDEX ]]; then
        zle -M "recall: ledger is empty — it fills as you work (${RT_CMD_INDEX/#$HOME/~})"; return
    fi

    local sel
    sel=$(rt-recall-rows | fzf \
            --delimiter=$'\t' --with-nth=3.. --nth=4.. \
            --query="$BUFFER" --prompt='recall> ' --no-sort --ansi \
            --height=70% --layout=reverse --border \
            --preview='rt-recall-context {1}' --preview-window='down:45%:wrap' \
            --header='enter edit · ctrl-a include trivia' \
            --bind='ctrl-a:reload(rt-recall-rows --all)' \
        ) || { zle reset-prompt; return }

    if [[ -n $sel ]]; then
        local -a f; f=( "${(@s:	:)sel}" )
        BUFFER=${f[5]}
        CURSOR=${#BUFFER}
    fi
    zle reset-prompt
}
zle -N rt-recall
bindkey '^X^R' rt-recall
