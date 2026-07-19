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
    # copy to clipboard directly (don't lean on the `clip` alias, which zsh
    # bakes into the function body at parse time — detect the tool at runtime).
    if command -v clip.exe >/dev/null 2>&1; then
        print -rn -- "$f" | clip.exe && echo "(path copied)"
    elif command -v xclip >/dev/null 2>&1; then
        print -rn -- "$f" | xclip -selection clipboard && echo "(path copied)"
    fi
}

# --- cmdlog: view/toggle the per-command engagement logger ---------------------
# on|off toggles; a path argument pins the log there; no arg shows status.
cmdlog() {
    case "${1:-}" in
        off) export RT_CMDLOG_OFF=1; echo "command logging: off";;
        on)  unset RT_CMDLOG_OFF;    echo "command logging: on  -> $(_rt_logpath)";;
        "")  if [ -n "$RT_CMDLOG_OFF" ]; then echo "command logging: off"
             else echo "command logging: on  -> $(_rt_logpath)"; fi;;
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
# Uncomment and fill ONLY the lines you use, then run:  direnv allow
# (left commented, they won't clobber DOMAIN/U/P you've set in the session)
#export DOMAIN=corp.local
#export DC=10.10.11.10
#export U=user
#export P='Password1'
#export RHOST=10.10.11.42
export RT_CMDLOG="$PWD/notes/commands.log"
EOF
    echo "denv: wrote ./.envrc — edit it, then run: direnv allow"
}
