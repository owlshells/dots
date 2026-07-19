# ~/dotfiles/shell/exports.sh — environment for engagement work

# --- History: keep more, timestamped, de-duped ---
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTTIMEFORMAT='%F %T  '
export HISTCONTROL=ignoreboth:erasedups
shopt -s histappend 2>/dev/null

# --- Editor / pager ---
export EDITOR="${EDITOR:-vim}"
export PAGER="${PAGER:-less}"
export LESS="-R"

# --- Wordlists & SecLists (auto-detect common install paths) ---
export WORDLISTS="/usr/share/wordlists"
for _sl in /usr/share/seclists /usr/share/wordlists/seclists "$HOME/SecLists"; do
    [ -d "$_sl" ] && export SECLISTS="$_sl" && break
done
unset _sl

# --- PATH additions (user-local + go tools) ---
for _p in "$HOME/.local/bin" "$HOME/go/bin"; do
    [ -d "$_p" ] && case ":$PATH:" in *":$_p:"*) ;; *) export PATH="$_p:$PATH";; esac
done
unset _p

# --- Engagement working dir root ---
# Per-target dirs are created by the `target` function under this root.
export OPS="${OPS:-$HOME/ops}"
