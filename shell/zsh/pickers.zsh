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

# Launching a full-screen TUI from inside a widget means handing the terminal
# over properly. push-input stashes whatever you were typing, the program runs
# as an ordinary foreground command -- so arsenal's own /dev/tty command
# injection behaves exactly as designed -- and your line comes back after.
rt-arsenal() {
    if ! command -v arsenal-ng >/dev/null; then
        zle -M "arsenal-ng not installed: sudo apt install arsenal-ng"
        return
    fi
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
