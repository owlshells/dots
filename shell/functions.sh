# ~/dots/shell/functions.sh — engagement workflow helpers
#
# For use on authorized engagements, CTFs, and lab work only. These are
# convenience wrappers around standard tooling — nothing here targets anything
# you don't point it at yourself.
#
# What is left here does work a command could not do for itself: scaffolds a
# directory, picks the best available tool, holds state across commands.
#
# What used to be here and is not any more — revshell, tunnel, dl, crack,
# upgrade-shell, and all of ad.sh — was recall: a name to memorise so you did
# not have to memorise a command. That job now belongs to arsenal-ng, Kali's
# packaged command library, on ^X^S. It has the same {{placeholder}} grammar,
# several times the content, and somebody else maintains it.

# --- lhost: your attack IP (prefers VPN tun0, falls back to eth0) --------------
# Usage: lhost            -> prints and exports $LHOST
#        lhost eth0       -> force an interface
lhost() {
    local ifc="${1:-}"
    local ip=""
    if [ -n "$ifc" ]; then
        ip=$(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    else
        for ifc in tun0 tun1 eth0 wlan0; do
            ip=$(ip -4 -o addr show "$ifc" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
            [ -n "$ip" ] && break
        done
    fi
    if [ -z "$ip" ]; then
        echo "lhost: no address found" >&2; return 1
    fi
    export LHOST="$ip"
    echo "$LHOST"
}

# --- target: set the box you're working and scaffold a working dir -------------
# Usage: target 10.10.11.42 [name]
#        target                 -> show current $RHOST / workdir
target() {
    if [ -z "$1" ]; then
        echo "RHOST=${RHOST:-<unset>}  name=${TARGET_NAME:-<unset>}  dir=${TARGET_DIR:-<unset>}"
        return 0
    fi
    # Validate before creating anything. `target RHOST=10.0.0.1` used to be
    # accepted verbatim and would happily mkdir ~/ops/RHOST=10.0.0.1.
    case "$1" in
        *=*|*/*|.*|"")
            echo "target: '$1' is not an address or hostname" >&2
            echo "usage: target <ip|hostname> [name]" >&2
            return 1 ;;
    esac
    export RHOST="$1"
    export TARGET_NAME="${2:-$1}"
    export TARGET_DIR="$OPS/$TARGET_NAME"
    export RT_CMDLOG="$TARGET_DIR/notes/commands.log"   # zsh preexec logs here
    mkdir -p "$TARGET_DIR"/{scans,loot,exploit,notes,www}
    # Arm the scope guard with the box you just named. Widen it with `scope add`;
    # until a scope file exists the guard has nothing to enforce and stays quiet.
    [ -f "$TARGET_DIR/scope.txt" ] || printf '# scope for %s — widen with `scope add <cidr>`\n%s\n' \
        "$TARGET_NAME" "$RHOST" > "$TARGET_DIR/scope.txt"
    [ -f "$TARGET_DIR/notes/README.md" ] || cat > "$TARGET_DIR/notes/README.md" <<EOF
# $TARGET_NAME ($RHOST)

- Started: $(date -Iseconds)
- LHOST: ${LHOST:-run \`lhost\`}

## Recon
## Foothold
## Privesc
## Loot
EOF
    cd "$TARGET_DIR" || return 1
    echo "target set: $TARGET_NAME ($RHOST) -> $TARGET_DIR"
}

# --- serve: HTTP file server in cwd, prints the reachable URL -------------------
# Usage: serve [port]   (default 8000)
serve() {
    local port="${1:-8000}"
    [ -n "$LHOST" ] || lhost >/dev/null
    echo "serving $(pwd) on http://${LHOST:-0.0.0.0}:${port}/"
    python3 -m http.server "$port"
}

# --- smbserve: quick anonymous SMB share (impacket) ----------------------------
# Usage: smbserve [share] [dir]   (default share=share, dir=cwd)
smbserve() {
    local share="${1:-share}" dir="${2:-$(pwd)}"
    [ -n "$LHOST" ] || lhost >/dev/null
    echo "SMB share //${LHOST}/${share} -> ${dir}  (Ctrl-C to stop)"
    impacket-smbserver -smb2support "$share" "$dir"
}

# --- listen: upgraded reverse-shell catcher ------------------------------------
# Prefers penelope (maintained, auto-TTY-upgrade + session logging), then
# rlwrap+nc, then plain nc. Usage: listen [port] (4444)
# Advanced post-ex is Mythic's job — this tier just catches and upgrades.
listen() {
    local port="${1:-4444}"
    if command -v penelope >/dev/null; then
        echo "[penelope] listening on :$port  (auto TTY upgrade + session logging)"
        penelope -p "$port"
    elif command -v rlwrap >/dev/null; then
        echo "[rlwrap nc] listening on :$port"
        rlwrap nc -lvnp "$port"
    else
        echo "[nc] listening on :$port  (install penelope/rlwrap for a better shell)"
        nc -lvnp "$port"
    fi
}

# --- scan: staged nmap into ./scans (fast top ports, then full on found ports) -
# Usage: scan [ip]   (defaults to $RHOST)
scan() {
    local ip="${1:-$RHOST}"
    [ -n "$ip" ] || { echo "scan: no target (set RHOST or pass an IP)" >&2; return 1; }
    local out="${TARGET_DIR:-.}/scans"; mkdir -p "$out"
    echo "[*] fast scan $ip ..."
    nmap -Pn -T4 --min-rate 1000 -p- -oN "$out/allports.nmap" "$ip"
    local p
    p=$(grep -oP '^\d+(?=/tcp\s+open)' "$out/allports.nmap" | paste -sd, -)
    [ -z "$p" ] && { echo "[!] no open TCP ports found"; return 0; }
    echo "[*] service/script scan on: $p"
    nmap -Pn -sCV -p"$p" -oN "$out/services.nmap" "$ip"
    echo "[+] results in $out/"
}

# --- fuzz: ffuf directory fuzz with a sane default wordlist ---------------------
# Usage: fuzz http://host/FUZZ [extra ffuf args...]
fuzz() {
    [ -n "$1" ] || { echo "fuzz: usage: fuzz http://host/FUZZ [args]" >&2; return 1; }
    local wl="$SECLISTS/Discovery/Web-Content/directory-list-2.3-medium.txt"
    [ -f "$wl" ] || wl="$WORDLISTS/dirb/common.txt"
    ffuf -u "$1" -w "$wl" - ic -c "${@:2}"
}

# --- b64 / ub64 / urlenc: quick encoders ---------------------------------------
b64()    { if [ -n "$1" ]; then printf '%s' "$1" | base64 -w0; echo; else base64 -w0; fi; }
ub64()   { if [ -n "$1" ]; then printf '%s' "$1" | base64 -d;  echo; else base64 -d; fi; }
urlenc() { python3 -c 'import sys,urllib.parse as u;print(u.quote(sys.argv[1] if len(sys.argv)>1 else sys.stdin.read().strip()))' "$@"; }

# --- mythic: drive mythic-cli from anywhere ------------------------------------
# Usage: mythic <start|stop|status|...>   (wraps sudo ./mythic-cli in $MYTHIC_DIR)
#        mythic creds   -> print the admin login
mythic() {
    local dir="${MYTHIC_DIR:-$HOME/opt/Mythic}"
    [ -x "$dir/mythic-cli" ] || { echo "mythic-cli not built — run: $RT_DOTFILES/tools/mythic-setup.sh"; return 1; }
    if [ "$1" = "creds" ]; then
        echo "url:  https://127.0.0.1:7443"
        echo "user: mythic_admin"
        local p; p=$(sudo grep -E '^MYTHIC_ADMIN_PASSWORD=' "$dir/.env" 2>/dev/null | cut -d= -f2-)
        if [ -n "$p" ]; then echo "pass: $p"; else echo "pass: (not in .env — retrieve from your password manager)"; fi
        return
    fi
    ( cd "$dir" && sudo ./mythic-cli "$@" )
}

# --- note: append a timestamped line to the current target's notes -------------
note() {
    local f="${TARGET_DIR:-.}/notes/README.md"
    [ -d "$(dirname "$f")" ] || f="./notes.md"
    printf -- '- `%s` %s\n' "$(date +%H:%M)" "$*" >> "$f"
    echo "-> $f"
}
