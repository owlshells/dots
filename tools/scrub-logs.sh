#!/usr/bin/env bash
# scrub-logs.sh — retro-redact credentials from ledgers already on disk.
#
# Redaction happens on write from now on, but anything logged before that is
# still sitting in cleartext: the recall index, every box's notes/commands.log,
# and the daily global logs. This rewrites them through bin/rt-redact.
#
# Keeps a .prescrub copy of anything it changes. Those copies still contain the
# cleartext -- that is the point of not deleting them for you.
#
#   tools/scrub-logs.sh [--dry-run]
set -euo pipefail

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

here="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
redact="$here/bin/rt-redact"
[ -x "$redact" ] || { echo "scrub: $redact not executable" >&2; exit 1; }

ops="${OPS:-$HOME/ops}"
idx="${RT_CMD_INDEX:-$ops/.cmd-index}"

# The human log is "stamp  [dir]  command". Lines that do NOT match that are
# continuation lines of a multi-line command -- and the first version of this
# script duplicated every one of them, because its prefix-extracting sed
# printed the whole line when the pattern did not match. There are 131 of them
# in a single day's log here, so this is the common case, not an edge case.
LOGRE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}  \[[^]]*\]  '

split_prefix() {  # prefix, or empty when the line is a continuation
    sed -E "s/(${LOGRE}).*/\\1/; t; s/^.*$//" "$1"
}
split_command() { # command, or the whole line when it is a continuation
    sed -E "s/${LOGRE}//" "$1"
}

rejoin() {        # prefixes file, bodies file -> stdout
    awk 'NR==FNR { p[FNR]=$0; next } { print p[FNR] $0 }' "$1" "$2"
}

mapfile -t targets < <({
    [ -f "$idx" ] && printf '%s\n' "$idx"
    find "$ops" -type f \( -name 'commands.log' -o -path '*/cmdlog/*.log' \) 2>/dev/null
} | sort -u)

(( ${#targets[@]} )) || { echo "scrub: nothing to scrub under $ops"; exit 0; }

changed=0
for f in "${targets[@]}"; do
    tmp=$(mktemp); pre=$(mktemp); body=$(mktemp)
    trap 'rm -f "$tmp" "$pre" "$body"' EXIT

    case "$f" in
        *.cmd-index)   # TSV: stamp \t dir \t command
            cut -f1,2 "$f" | sed 's/$/\t/' > "$pre"
            cut -f3-  "$f" | "$redact"     > "$body"
            ;;
        *)
            split_prefix  "$f"              > "$pre"
            split_command "$f" | "$redact"  > "$body"
            ;;
    esac
    rejoin "$pre" "$body" > "$tmp"

    # Safety invariant: a rewritten line must either be unchanged or contain the
    # redaction mark. Anything else means the split/rejoin mangled it, and the
    # right response is to touch nothing. This is the check whose absence let
    # the first version write "idid" and "wsl.exe --versionwsl.exe --version".
    if ! awk 'NR==FNR { a[FNR]=$0; n=FNR; next }
              { if ($0 != a[FNR] && index($0, "{{redacted}}") == 0) { print FNR": "$0; bad=1 } }
              END { exit (bad ? 1 : 0) }' "$f" "$tmp" > /tmp/scrub-bad.$$ 2>&1; then
        echo "scrub: REFUSING to write ${f/#$HOME/\~} -- rewrite altered lines without redacting them:" >&2
        head -3 /tmp/scrub-bad.$$ | sed 's/^/    /' >&2
        rm -f /tmp/scrub-bad.$$ "$tmp" "$pre" "$body"
        exit 1
    fi
    rm -f /tmp/scrub-bad.$$
    if [ "$(wc -l < "$f")" != "$(wc -l < "$tmp")" ]; then
        echo "scrub: REFUSING to write ${f/#$HOME/\~} -- line count changed" >&2
        rm -f "$tmp" "$pre" "$body"; exit 1
    fi

    if cmp -s "$f" "$tmp"; then
        rm -f "$tmp" "$pre" "$body"; continue
    fi
    n=$({ diff "$f" "$tmp" || true; } | grep -c '^>' || true)
    changed=$((changed + 1))
    if (( dry )); then
        echo "would scrub $n line(s) in ${f/#$HOME/\~}"
        # `|| true`: diff exits 1 when files differ, which under `set -e` plus
        # pipefail silently killed the whole run after the first file.
        { diff "$f" "$tmp" || true; } | grep '^>' | head -3 | sed 's/^/    /'
    else
        cp "$f" "$f.prescrub"
        cat "$tmp" > "$f"
        echo "scrubbed $n line(s) in ${f/#$HOME/\~}  (original: $(basename "$f").prescrub)"
    fi
    rm -f "$tmp" "$pre" "$body"
done

if (( changed == 0 )); then
    echo "scrub: ${#targets[@]} file(s) checked, nothing needed redacting"
elif (( dry )); then
    echo "scrub: dry run, nothing written"
else
    echo "scrub: $changed file(s) rewritten. The .prescrub copies still hold the"
    echo "       cleartext -- delete them once you are satisfied."
fi
