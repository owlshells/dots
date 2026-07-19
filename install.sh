#!/usr/bin/env bash
# install.sh — symlink dotfiles into place. Idempotent; backs up anything real.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

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
link "$DOTFILES/tmux/tmux.conf"     "$HOME/.tmux.conf"

# Make bin scripts executable
chmod +x "$DOTFILES"/bin/* 2>/dev/null || true

# Ops dirs
mkdir -p "$HOME/ops/tmux-logs"

echo
echo "done. open a new shell or run:  source ~/.bashrc"
[ -d "$BACKUP" ] && echo "originals saved in: $BACKUP"
