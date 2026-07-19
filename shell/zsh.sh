# ~/dotfiles/shell/zsh.sh — zsh-only engagement helpers.
# Loaded from shell/zshrc after the shared modules. Uses zsh features
# (array ${#..}, ${..:h}) so it is not sourced under bash.

# --- payload: fuzzy-browse local payload/wordlist collections with preview -----
# fzf over PayloadsAllTheThings + SecLists; prints the chosen path (and copies
# it to the clipboard on WSL). Set $PAYLOADS to add your own collection.
# Usage: payload [initial query]
payload() {
    command -v fzf >/dev/null || { echo "payload: fzf not installed (run tools/install-tools.sh)"; return 1; }
    local -a dirs; local d
    for d in "${PAYLOADS:-$HOME/PayloadsAllTheThings}" \
             /usr/share/payloadsallthethings \
             "${SECLISTS:-/usr/share/seclists}"; do
        [ -d "$d" ] && dirs+=("$d")
    done
    [ ${#dirs} -gt 0 ] || { echo "payload: no payload dirs (install seclists or clone PayloadsAllTheThings)"; return 1; }
    local prev='(batcat --color=always {} 2>/dev/null || bat --color=always {} 2>/dev/null || cat {}) | head -400'
    local f
    f=$(find "${dirs[@]}" -type f 2>/dev/null \
        | fzf --query="${1:-}" --prompt='payload> ' \
              --preview="$prev" --preview-window=right:60%:wrap) || return
    [ -n "$f" ] || return
    print -r -- "$f"
    command -v clip >/dev/null && print -rn -- "$f" | clip && echo "(path copied)"
}

# --- cmdlog: view/toggle the per-command engagement logger ---------------------
# on|off toggles; a path argument pins the log there; no arg shows status.
cmdlog() {
    case "${1:-}" in
        off) export RT_CMDLOG_OFF=1; echo "command logging: off";;
        on)  unset RT_CMDLOG_OFF;    echo "command logging: on  -> ${RT_CMDLOG:-$OPS/cmdlog/$(date +%F).log}";;
        "")  if [ -n "$RT_CMDLOG_OFF" ]; then echo "command logging: off"
             else echo "command logging: on  -> ${RT_CMDLOG:-$OPS/cmdlog/$(date +%F).log}"; fi;;
        *)   export RT_CMDLOG="$1"; unset RT_CMDLOG_OFF; echo "command log -> $RT_CMDLOG";;
    esac
}

# --- denv: drop a direnv .envrc template in the current dir --------------------
# Persists per-engagement env (creds, RHOST) that auto-loads on cd once you
# run `direnv allow`. Complements `target`, which sets RHOST/dirs for the session.
denv() {
    command -v direnv >/dev/null || echo "denv: note — direnv not installed; .envrc won't auto-load until it is"
    if [ -e ./.envrc ]; then echo "denv: ./.envrc already exists"; return 1; fi
    cat > ./.envrc <<'EOF'
# direnv per-engagement env — auto-loads on cd into this dir.
# Fill in what applies, then run:  direnv allow
export DOMAIN=
export DC=
export U=
export P=
# export RHOST=
export RT_CMDLOG="$PWD/notes/commands.log"
EOF
    echo "denv: wrote ./.envrc — edit it, then run: direnv allow"
}
