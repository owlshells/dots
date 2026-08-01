#!/usr/bin/env bash
# tools/install-test.sh — exercise install.sh against a throwaway $HOME.
#
# install.sh is the only thing here that writes outside the repo, it has three
# separate hook paths, and it claims to be idempotent and to back up anything
# real it finds. None of that was ever checked.
#
# It refers to $HOME and nothing else outside the checkout, so overriding HOME
# sandboxes it completely -- as long as XDG_* are cleared too, since those would
# otherwise point the kitty fragment at the real ~/.local/share. Nothing here
# touches your actual dotfiles.
#
#   bash tools/install-test.sh
set -uo pipefail

here="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
install="$here/install.sh"
[ -x "$install" ] || { echo "install-test: $install not executable" >&2; exit 1; }

t_run=0; t_fail=0
sect() { printf '\n── %s ──\n' "$*"; }
ok()   { t_run=$((t_run+1))
         if [ "$1" = "$2" ]; then printf '  ok    %s\n' "$3"
         else printf '  FAIL  %s\n          got:  %s\n          want: %s\n' "$3" "$1" "$2"; t_fail=1; fi }
yes_() { t_run=$((t_run+1))
         if [ "$1" = 0 ]; then printf '  ok    %s\n' "$2"
         else printf '  FAIL  %s\n' "$2"; t_fail=1; fi }

MARKER='# >>> red-team dotfiles >>>'

# A fresh sandboxed HOME with a ~/.zshrc, since the zsh hook needs one to append
# to and otherwise reports "not using zsh?" and does nothing.
new_home() {
    SANDBOX="$(mktemp -d)"
    printf '# stock kali zshrc\nPROMPT="%%~ "\n' > "$SANDBOX/.zshrc"
}
run_install() { ( HOME="$SANDBOX" XDG_DATA_HOME= XDG_CONFIG_HOME= "$install" "$@" ) }

# ------------------------------------------------------------------------------
sect "a fresh install"
new_home
out="$(run_install 2>&1)"; rc=$?
ok "$rc" "0" "exits 0"
ok "$(readlink -f "$SANDBOX/.bash_aliases")" "$here/shell/bash_aliases" \
   "~/.bash_aliases links into the checkout"
ok "$(readlink -f "$SANDBOX/.tmux.conf")" "$here/tmux/tmux.conf" \
   "~/.tmux.conf links into the checkout"
ok "$(grep -cF "$MARKER" "$SANDBOX/.zshrc")" "1" "the zshrc hook is appended once"
yes_ "$([ -d "$SANDBOX/ops/tmux-logs" ]; echo $?)" "~/ops/tmux-logs is created"
# The hook must source the repo, not a copy of it.
yes_ "$(grep -qF "$here/shell/zshrc" "$SANDBOX/.zshrc"; echo $?)" \
     "the hook sources this checkout's shell/zshrc"

sect "running it again changes nothing"
before="$(find "$SANDBOX" -maxdepth 1 | sort; cat "$SANDBOX/.zshrc")"
out2="$(run_install 2>&1)"; rc=$?
ok "$rc" "0" "exits 0 the second time"
ok "$(grep -cF "$MARKER" "$SANDBOX/.zshrc")" "1" "the marker is still there exactly once"
after="$(find "$SANDBOX" -maxdepth 1 | sort; cat "$SANDBOX/.zshrc")"
ok "$after" "$before" "nothing in \$HOME changed"
yes_ "$(printf '%s' "$out2" | grep -q '^ok  ' ; echo $?)" "it reports the links as already ok"
rm -rf "$SANDBOX"

sect "a real file in the way is backed up, not clobbered"
new_home
printf 'alias mine=important\n' > "$SANDBOX/.bash_aliases"
run_install >/dev/null 2>&1
ok "$(readlink -f "$SANDBOX/.bash_aliases")" "$here/shell/bash_aliases" \
   "the symlink replaced it"
saved="$(find "$SANDBOX/.dotfiles-backup" -name '.bash_aliases' -type f 2>/dev/null | head -1)"
yes_ "$([ -n "$saved" ]; echo $?)" "the original is in ~/.dotfiles-backup/"
ok "$(cat "$saved" 2>/dev/null)" "alias mine=important" "and its contents are intact"
# The pre-existing .zshrc is copied before being appended to.
yes_ "$([ -f "$SANDBOX/.dotfiles-backup"/*/.zshrc ] 2>/dev/null; echo $?)" \
     "the original .zshrc is backed up too"
rm -rf "$SANDBOX"

sect "--no-tmux"
new_home
run_install --no-tmux >/dev/null 2>&1
yes_ "$([ ! -e "$SANDBOX/.tmux.conf" ]; echo $?)" "~/.tmux.conf is left alone"
ok "$(readlink -f "$SANDBOX/.bash_aliases")" "$here/shell/bash_aliases" \
   "but the bash hook still lands"
rm -rf "$SANDBOX"

sect "the wallpaper"
# feh is what the hook keys on, so a box without it must be a clean skip rather
# than a stray ~/.fehbg -- that is what keeps this a no-op on every headless box
# without install.sh needing to know which box it is on.
new_home
# No feh on PATH here -- run_install does not add one.
out="$(run_install 2>&1)"
yes_ "$(printf '%s' "$out" | grep -q 'skip  wallpaper (no feh'; echo $?)" \
     "no feh on the box -> clean skip"
yes_ "$([ ! -e "$SANDBOX/.fehbg" ]; echo $?)" "and no ~/.fehbg left behind"
rm -rf "$SANDBOX"

new_home
fakebin="$SANDBOX/bin"; mkdir -p "$fakebin"
printf '#!/bin/sh\nexit 0\n' > "$fakebin/feh"; chmod +x "$fakebin/feh"
out="$( HOME="$SANDBOX" XDG_DATA_HOME= XDG_CONFIG_HOME= PATH="$fakebin:$PATH" "$install" 2>&1 )"
yes_ "$([ -x "$SANDBOX/.fehbg" ]; echo $?)" "with feh present, ~/.fehbg is written and executable"
yes_ "$(grep -q "$here/terminal/wallpaper.png" "$SANDBOX/.fehbg"; echo $?)" \
     "and points at the checkout's wallpaper"
# A background you chose yourself must survive a re-run.
printf '#!/bin/sh\nfeh --bg-fill /my/own.png\n' > "$SANDBOX/.fehbg"; chmod +x "$SANDBOX/.fehbg"
out="$( HOME="$SANDBOX" XDG_DATA_HOME= XDG_CONFIG_HOME= PATH="$fakebin:$PATH" "$install" 2>&1 )"
yes_ "$(grep -q '/my/own.png' "$SANDBOX/.fehbg"; echo $?)" "a background you set yourself is not overruled"
rm -rf "$SANDBOX"

sect "--no-terminal and --help"
new_home
out="$(run_install --no-terminal 2>&1)"; rc=$?
ok "$rc" "0" "--no-terminal exits 0"
yes_ "$(printf '%s' "$out" | grep -q 'skip  owl'; echo $?)" "and says it skipped the owl"
yes_ "$(printf '%s' "$out" | grep -q 'skip  wallpaper (--no-terminal'; echo $?)" \
     "and skipped the wallpaper too"
out="$(run_install --help 2>&1)"; rc=$?
ok "$rc" "0" "--help exits 0"
yes_ "$(printf '%s' "$out" | grep -q 'no-tmux'; echo $?)" "and documents the flags"
rm -rf "$SANDBOX"

sect "an unknown option is refused"
new_home
out="$(run_install --wat 2>&1)"; rc=$?
ok "$rc" "1" "exits 1"
yes_ "$(printf '%s' "$out" | grep -q "unknown option"; echo $?)" "and says which"
yes_ "$([ ! -e "$SANDBOX/.bash_aliases" ]; echo $?)" "and wrote nothing first"
rm -rf "$SANDBOX"

sect "no ~/.zshrc at all"
new_home; rm -f "$SANDBOX/.zshrc"
out="$(run_install 2>&1)"; rc=$?
ok "$rc" "0" "still exits 0"
yes_ "$(printf '%s' "$out" | grep -q 'skip  no ~/.zshrc'; echo $?)" "and says it skipped the zsh hook"
ok "$(readlink -f "$SANDBOX/.bash_aliases")" "$here/shell/bash_aliases" "bash is still hooked"
rm -rf "$SANDBOX"

printf '\n'
if [ "$t_fail" -ne 0 ]; then printf 'FAILED  (%s checks)\n' "$t_run"; else printf 'all pass (%s checks)\n' "$t_run"; fi
exit "$t_fail"
