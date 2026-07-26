#!/usr/bin/env bash
# backfill-index.sh — seed the recall index from command logs already on disk.
#
# The preexec hook has been writing human-readable logs since long before
# anything read them back. This converts that history into the machine-readable
# index that shell/zsh/recall.zsh uses, so ^X^R and ghost text have material
# from the first shell rather than starting empty.
#
# Idempotent: existing index entries are preserved and the result is deduped.
# Reads only; the original logs are never modified.
#
#   tools/backfill-index.sh [--dry-run]
set -euo pipefail

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

ops="${OPS:-$HOME/ops}"
idx="${RT_CMD_INDEX:-$ops/.cmd-index}"

mapfile -t logs < <(
    find "$ops" -type f \( -name '*.log' -path '*/cmdlog/*' -o -name 'commands.log' \) 2>/dev/null | sort
)
if [ "${#logs[@]}" -eq 0 ]; then
    echo "backfill: no logs found under $ops" >&2
    exit 0
fi

# Old format:  2026-07-19 20:11:27  [~/dev]  cd dev
# New format:  2026-07-19 20:11:27 <TAB> /home/you/dev <TAB> cd dev
converted="$(
    awk -v home="$HOME" '
    match($0, /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  \[/) {
        stamp = substr($0, 1, 19)
        rest  = substr($0, 22)
        close_at = index(rest, "]  ")
        if (close_at < 2) next
        dir = substr(rest, 2, close_at - 2)
        cmd = substr(rest, close_at + 3)
        if (cmd == "") next
        gsub(/\t/, " ", cmd)
        if (substr(dir, 1, 1) == "~") dir = home substr(dir, 2)
        print stamp "\t" dir "\t" cmd
    }' "${logs[@]}"
)"

n_new=$(printf '%s\n' "$converted" | grep -c . || true)
echo "backfill: ${#logs[@]} log file(s), $n_new usable entries"

if [ "$dry" -eq 1 ]; then
    printf '%s\n' "$converted" | tail -5
    echo "backfill: dry run, nothing written"
    exit 0
fi

mkdir -p "$(dirname "$idx")"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Sorted by timestamp so the index stays chronological, which is what makes
# "most recent match" and the surrounding-commands preview meaningful.
{ [ -r "$idx" ] && cat "$idx"; printf '%s\n' "$converted"; } \
    | grep . | sort -u -t$'\t' -k1,1 -k3,3 | sort -t$'\t' -k1,1 > "$tmp"
cat "$tmp" > "$idx"
echo "backfill: index now $(wc -l < "$idx") entries -> ${idx/#$HOME/\~}"
