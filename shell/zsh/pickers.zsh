# ~/dots/shell/zsh/pickers.zsh — the ^X pickers.
#
#   ^X^S   arsenal-ng, the command library
#   ^X^P   payload / wordlist paths
#
# ^X^S used to open a hand-written snippets/*.txt corpus maintained in this
# repo. arsenal-ng (packaged by Kali) does the same job better and is somebody
# else's job to maintain: the identical {{placeholder}} grammar, plus defaults
# ({{lport|4444}}), a persistent variable store, 200+ cheat sheets including a
# whole impacket tree, and command injection straight into the terminal.
#
# Keeping our own 74 entries meant maintaining a worse copy of a package that
# arrives through apt. The snippets are in git history if they are ever wanted.

# --- session state -> arsenal's variable store ---------------------------------
# arsenal-ng keeps variables in a flat JSON map at
# ~/.config/arsenal-ng/variables.json (confirmed by writing one and watching its
# debug.log report "Loaded 3 variable(s)"). It is TUI-only with no CLI, so the
# way to seed it from the shell is to write that file.
#
# This is what `target 10.10.11.42 boxy` buys you: every {{target}} in 2830
# cheats is already filled by the time you open the picker.
#
# The password is NOT written by default. Everything else here is context; $P is
# a credential, and persisting it to a file that outlives the session is exactly
# the habit shell/zsh/redact.zsh exists to break. Opt in with
# RT_ARSENAL_SYNC_PASSWORD=1 if you would rather have the convenience.
: ${RT_ARSENAL_VARS:=$HOME/.config/arsenal-ng/variables.json}

_rt_arsenal_sync() {
    command -v python3 >/dev/null || return
    local -A map=(
        target    "${RHOST-}"     target_ip "${RHOST-}"
        domain    "${DOMAIN-}"    dc_ip     "${DC-}"
        username  "${U-}"         user      "${U-}"
        lhost     "${LHOST-}"
    )
    (( ${RT_ARSENAL_SYNC_PASSWORD:-0} )) && map[password]="${P-}"

    local -a pairs; local k
    for k in ${(k)map}; do
        [[ -n ${map[$k]} ]] && pairs+=( "$k=${map[$k]}" )
    done
    (( ${#pairs} )) || return

    mkdir -p "${RT_ARSENAL_VARS:h}" 2>/dev/null || return
    # Merge rather than overwrite: variables you set inside the TUI survive.
    RT_VARS_FILE=$RT_ARSENAL_VARS python3 - "${pairs[@]}" <<'PY' 2>/dev/null
import json, os, sys
path = os.environ["RT_VARS_FILE"]
try:
    with open(path) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
for arg in sys.argv[1:]:
    k, _, v = arg.partition("=")
    data[k] = v
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}

# Launching a full-screen TUI from inside a widget means handing the terminal
# over properly. push-input stashes whatever you were typing, the program runs
# as an ordinary foreground command -- so arsenal's own /dev/tty command
# injection behaves exactly as designed -- and your line comes back after.
rt-arsenal() {
    if ! command -v arsenal-ng >/dev/null; then
        zle -M "arsenal-ng not installed: sudo apt install arsenal-ng"
        return
    fi
    _rt_arsenal_sync
    zle push-input
    BUFFER="arsenal-ng"
    zle accept-line
}
zle -N rt-arsenal
bindkey '^X^S' rt-arsenal

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
