#!/usr/bin/env bash
# install.sh — symlink dots into place. Idempotent; backs up anything real.
#
#   --no-tmux   leave ~/.tmux.conf alone
#
# --no-tmux exists for hosts whose tmux config is owned by something else and is
# purpose-built for that host — kali-deploy-remote writes a headless SSH config
# (auto-attach, multi-window) that is a better fit there than this repo's. Note
# that without it the symlink would also mean any tool doing `cat > ~/.tmux.conf`
# writes straight into this repo.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

NO_TMUX=0
while [ $# -gt 0 ]; do
    case "$1" in
        --no-tmux) NO_TMUX=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "install.sh: unknown option '$1'" >&2; exit 1 ;;
    esac
    shift
done

link() {
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo "ok    $dst"
        return
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP"
        mv "$dst" "$BACKUP/"
        echo "backup $dst -> $BACKUP/"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "link  $dst -> $src"
}

# ~/.bash_aliases is the hook Kali's stock .bashrc already sources.
link "$DOTFILES/shell/bash_aliases" "$HOME/.bash_aliases"
if [ "$NO_TMUX" -eq 1 ]; then
    echo "skip  ~/.tmux.conf (--no-tmux)"
else
    link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
fi

# zsh has no stock drop-in Kali auto-sources, so append a guarded hook to
# ~/.zshrc (non-destructive — Kali keeps its prompt/plugins; we add ours after).
hook_zsh() {
    local rc="$HOME/.zshrc" marker="# >>> red-team dotfiles >>>"
    [ -f "$rc" ] || { echo "skip  no ~/.zshrc (not using zsh?)"; return; }
    if grep -qF "$marker" "$rc"; then
        echo "ok    ~/.zshrc hook already present"
        return
    fi
    mkdir -p "$BACKUP"; cp "$rc" "$BACKUP/.zshrc"
    cat >> "$rc" <<EOF

$marker
[ -r "$DOTFILES/shell/zshrc" ] && source "$DOTFILES/shell/zshrc"
# <<< red-team dotfiles <<<
EOF
    echo "hook  appended red-team block to ~/.zshrc (backup in $BACKUP/)"
}
hook_zsh

# Make bin scripts executable
chmod +x "$DOTFILES"/bin/* 2>/dev/null || true

# Ops dirs
mkdir -p "$HOME/ops/tmux-logs"

echo
echo "done. open a new shell or run:  source ~/.bashrc"
[ -d "$BACKUP" ] && echo "originals saved in: $BACKUP"
