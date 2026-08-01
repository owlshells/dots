#!/usr/bin/env zsh
# tools/selftest.zsh — pure-logic checks for the ambient layer.
#
# Runs against a throwaway $OPS so it needs no engagement, no network and no
# root. Everything with side effects (widgets, hooks, fzf) is out of scope here;
# this covers the arithmetic and parsing that is easy to get subtly wrong.
#
#   zsh tools/selftest.zsh

emulate -L zsh
setopt no_unset warn_create_global 2>/dev/null

typeset -g RT_DOTFILES=${0:A:h:h}
typeset -g _t_fail=0 _t_run=0

t()  { print -r -- ""; print -r -- "── $* ──"; }
ok() { (( _t_run++ )); [[ $1 == $2 ]] && print -r -- "  ok    $3" \
        || { print -r -- "  FAIL  $3"; print -r -- "          got:  ${(qq)1}"
             print -r -- "          want: ${(qq)2}"; _t_fail=1 }; }
rc() { (( _t_run++ )); [[ $1 == $2 ]] && print -r -- "  ok    $3" \
        || { print -r -- "  FAIL  $3 (rc=$1 want $2)"; _t_fail=1 }; }
has(){ (( _t_run++ )); [[ $1 == *$2* ]] && print -r -- "  ok    $3" \
        || { print -r -- "  FAIL  $3"; print -r -- "          got: ${(qq)1}"
             print -r -- "          want substring: ${(qq)2}"; _t_fail=1 }; }

typeset -g OPS=$(mktemp -d) TARGET_DIR="" RHOST="" TARGET_NAME=""
trap "rm -rf $OPS" EXIT

source $RT_DOTFILES/shell/zsh/context.zsh
source $RT_DOTFILES/shell/zsh/guard.zsh

# Pin the network view so results do not depend on the host's interfaces.
_pin_net() { _rt_vpn_iface=$1; _rt_local_nets=(172.30.1.5/20); _rt_net_checked=$EPOCHSECONDS }
_rt_net_refresh() { : }          # neutralise the real probe for the whole run

t "ipv4 arithmetic"
ok "$(_rt_ip2int 0.0.0.0)"          0          "0.0.0.0"
ok "$(_rt_ip2int 255.255.255.255)"  4294967295 "255.255.255.255"
ok "$(_rt_ip2int 10.10.11.42)"      168430378  "10.10.11.42"
_rt_ip2int 10.10.11     &>/dev/null; rc $? 1 "reject three octets"
_rt_ip2int 10.10.11.256 &>/dev/null; rc $? 1 "reject octet > 255"
_rt_ip2int corp.local   &>/dev/null; rc $? 1 "reject hostname"

t "cidr containment"
_rt_in_cidr 10.10.11.42  10.10.11.0/24 ; rc $? 0 "inside /24"
_rt_in_cidr 10.10.12.42  10.10.11.0/24 ; rc $? 1 "outside /24"
_rt_in_cidr 10.10.11.0   10.10.11.0/24 ; rc $? 0 "network address"
_rt_in_cidr 10.10.11.255 10.10.11.0/24 ; rc $? 0 "broadcast address"
_rt_in_cidr 10.10.11.42  10.10.11.42   ; rc $? 0 "bare ip behaves as /32"
_rt_in_cidr 10.10.11.43  10.10.11.42   ; rc $? 1 "bare ip /32 rejects neighbour"
_rt_in_cidr 1.2.3.4      0.0.0.0/0     ; rc $? 0 "/0 matches everything"
_rt_in_cidr 11.0.0.1     10.0.0.0/8    ; rc $? 1 "just past a /8"
_rt_in_cidr 10.10.11.42  10.10.11.0/33 ; rc $? 1 "reject prefix > 32"

t "rfc1918"
_rt_is_rfc1918 172.16.0.1  ; rc $? 0 "172.16 lower bound"
_rt_is_rfc1918 172.31.255.1; rc $? 0 "172.31 upper bound"
_rt_is_rfc1918 172.32.0.1  ; rc $? 1 "172.32 is public"
_rt_is_rfc1918 8.8.8.8     ; rc $? 1 "public address"

t "guard: inert until configured"
_pin_net ""
ok "$(_rt_guard_check 'nmap -p- 10.10.99.7')" "" "no scope, no target = silent"

t "guard: scope"
TARGET_DIR=$OPS/boxy; mkdir -p $TARGET_DIR
print -rl -- '# engagement scope' '10.10.11.0/24' '10.10.10.5' > $TARGET_DIR/scope.txt
_pin_net tun0
ok  "$(_rt_guard_check 'nxc smb 10.10.11.42 -u svc')" "" "in scope is silent"
ok  "$(_rt_guard_check 'nxc smb 10.10.10.5')"         "" "bare-ip scope entry"
has "$(_rt_guard_check 'nmap -p- 10.10.99.7')" "out of scope: 10.10.99.7" "out of scope warns"
has "$(_rt_guard_check 'nmap -p- 10.10.99.0/24')" "10.10.99.0/24" "reports the cidr as written"
ok  "$(_rt_guard_check 'curl 127.0.0.1:8080')"   "" "loopback exempt"
ok  "$(_rt_guard_check 'ssh 172.30.1.9')"        "" "attached subnet exempt"
ok  "$(_rt_guard_check 'ls -la')"                "" "no addresses, no check"
ok  "$(_rt_guard_check '')"                      "" "empty buffer"

t "guard: public traffic is not a scope violation"
ok "$(_rt_guard_check 'curl https://8.8.8.8')"        "" "public dns"
ok "$(_rt_guard_check 'wget http://151.101.1.140/x')" "" "public mirror"
print -rl -- '203.0.113.0/24' > $TARGET_DIR/scope.txt
ok  "$(_rt_guard_check 'curl https://8.8.8.8')" "" "still quiet on unrelated public"
has "$(_rt_guard_check 'nmap 203.0.114.9')" "out of scope" "public scope catches its own /8"
ok  "$(_rt_guard_check 'nmap 203.0.113.9')" "" "public scope allows in-range"

t "guard: vpn"
print -rl -- '10.10.11.0/24' > $TARGET_DIR/scope.txt
_pin_net ""
has "$(_rt_guard_check 'nxc smb 10.10.11.42')" "no vpn" "private target, tunnel down"
ok  "$(_rt_guard_check 'curl https://8.8.8.8')" "" "public target needs no tunnel"
_pin_net tun0
ok  "$(_rt_guard_check 'nxc smb 10.10.11.42')" "" "tunnel up, quiet"

t "guard: address extraction from real command shapes"
_pin_net tun0
has "$(_rt_guard_check 'impacket-secretsdump corp/svc:Pw1@10.10.99.7')" \
    "10.10.99.7" "impacket target spec"
has "$(_rt_guard_check 'proxychains nxc smb 10.10.99.7 -u a -p b')" \
    "10.10.99.7" "behind proxychains"
has "$(_rt_guard_check 'curl http://10.10.99.7:8080/a.php?x=1')" \
    "10.10.99.7" "url with port and query"
ok  "$(_rt_guard_check 'hashcat -m 1000 h.txt rockyou.txt')" "" "version-like text is not an address"

# ==============================================================================
# recall
# ==============================================================================
path=( $RT_DOTFILES/bin $path )
typeset -gx RT_CMD_INDEX=$OPS/.cmd-index
source $RT_DOTFILES/shell/zsh/recall.zsh

# Fixture: an engagement sequence, some ~ noise, a repeat across two places.
_ix() { print -r -- "$1	$2	$3" >> $RT_CMD_INDEX }
: > $RT_CMD_INDEX
_ix '2026-07-20 09:00:01' "$HOME"      'ls'
_ix '2026-07-20 09:00:02' "$HOME"      'claude'
_ix '2026-07-20 09:01:00' "$OPS/boxy"  'nmap -Pn -p- 10.10.11.42'
_ix '2026-07-20 09:02:00' "$OPS/boxy"  'nxc smb 10.10.11.42 -u guest -p ""'
_ix '2026-07-20 09:03:00' "$OPS/boxy"  'impacket-GetNPUsers corp/:@10.10.11.10 -no-pass'
_ix '2026-07-21 11:00:00' "$HOME/dev"  'cd ASID'
_ix '2026-07-21 11:00:05' "$HOME/dev"  'aws s3api get-bucket-policy --bucket loot-x'
_ix '2026-07-21 11:02:00' "$OPS/forge" 'proxychains nxc smb 10.10.12.5 -u svc -H aad3b'
_ix '2026-07-22 08:00:00' "$HOME"      'nxc smb 10.10.11.42 -u guest -p ""'

t "recall: the trivia rule is shape-based, not a tool denylist"
for c in 'nxc smb 10.10.11.42' 'strings -n8 /tmp/a.bin' 'proxychains nxc smb 10.1.1.1' \
         'aws s3 ls' 'impacket-psexec corp/a:b@1.2.3.4' 'mythic status' \
         'somefuturetool --flag x'; do
    _rt_trivial "$c"; rc $? 1 "signal: ${c%% *}"
done
for c in 'ls' 'ls -la' 'cd ASID' 'clear' 'pwd' 'claude' 'exit'; do
    _rt_trivial "$c"; rc $? 0 "trivia: $c"
done

t "recall: zsh and awk trivia rules agree"
# The picker filters in awk, ghost text filters in zsh. They must not diverge.
typeset -a _shown _all_shown
_shown=(     ${(f)"$(rt-recall-rows      | cut -f5)"} )
_all_shown=( ${(f)"$(rt-recall-rows --all | cut -f5)"} )
for c in $_all_shown; do
    local in_awk=1 in_zsh=1
    (( ${_shown[(I)$c]} )) || in_awk=0
    _rt_trivial "$c" && in_zsh=0
    ok "$in_awk" "$in_zsh" "agree on: $c"
done

t "recall: ranking"
ok "$(rt-recall-rows | sed -n 1p | cut -f3)" "forge" "newest engagement box first"
ok "$(rt-recall-rows | cut -f3 | sort -u | tr '\n' ' ')" "- boxy forge " "all boxes present"
has "$(rt-recall-rows | cut -f3,5 | sed -n 3p)" "boxy" "repeated command credited to the engagement, not ~"
ok "$(rt-recall-rows | grep -c 'nxc smb 10.10.11.42')" "1" "deduped across locations"
ok "$(rt-recall-rows | grep -c 'cd ASID')" "0" "trivia hidden by default"
ok "$(rt-recall-rows --all | grep -c 'cd ASID')" "1" "trivia reachable via ctrl-a"

t "recall: surrounding-command preview"
typeset -g _L=$(rt-recall-rows | awk -F'\t' '$5 ~ /nxc smb 10.10.11.42/ {print $1}')
typeset -g _ctx=$(rt-recall-context $_L 2 | sed 's/\x1b\[[0-9;]*m//g')
has "$_ctx" "nmap -Pn -p- 10.10.11.42"   "shows the command before"
has "$_ctx" "impacket-GetNPUsers"        "shows the command after"
has "$_ctx" "▸"                          "marks the hit"

t "recall: ghost text"
_rt_recall_seed
typeset -g suggestion=""
_zsh_autosuggest_strategy_cmdlog 'nx'
ok "$suggestion" "" "silent under 3 characters"
suggestion=""
_zsh_autosuggest_strategy_cmdlog 'nxc'
ok "$suggestion" 'nxc smb 10.10.11.42 -u guest -p ""' "completes from the ledger"
suggestion=""
_zsh_autosuggest_strategy_cmdlog 'impacket-Get'
has "$suggestion" "GetNPUsers" "completes a long tool name"
suggestion=""
_zsh_autosuggest_strategy_cmdlog 'cd '
ok "$suggestion" "" "never suggests trivia"
suggestion=""
_zsh_autosuggest_strategy_cmdlog 'zzz-nothing'
ok "$suggestion" "" "no match, no suggestion"
suggestion=""
_zsh_autosuggest_strategy_cmdlog 'aws s3api get-bucket-policy --bucket'
has "$suggestion" "loot-x" "matches deep into a long aws command"

t "recall: index writes"
: > $RT_CMD_INDEX; _rt_recall_mem=()
cd $OPS
_rt_index_add 'nxc smb 10.10.11.42 -u a'
_rt_index_add '	padded	with	tabs	'
_rt_index_add '   '
ok "$(wc -l < $RT_CMD_INDEX)" "2" "blank commands are not recorded"
ok "$(awk -F'\t' 'NR==2{print NF}' $RT_CMD_INDEX)" "3" "tabs in a command cannot break the format"
ok "${_rt_recall_mem[1]}" 'nxc smb 10.10.11.42 -u a' "in-memory ghost-text corpus updated live"
cd - >/dev/null

# ==============================================================================
# host index
# ==============================================================================
typeset -gx RT_HOSTS_INDEX=$OPS/.hosts-index

t "hosts: harvest from nmap output"
rt-host-harvest $RT_DOTFILES/tools/fixtures/services.nmap
typeset -g _h="$(<$RT_HOSTS_INDEX)"
has "$_h" "10.10.11.42	boxy.htb"       "hostname from the scan report line"
has "$_h" "10.10.11.42	admin.boxy.htb" "vhost from an http redirect"
has "$_h" "10.10.11.42	shop.boxy.htb"  "name from a tls commonName"
has "$_h" "10.10.11.42	api.boxy.htb"   "second name from the same SAN line"
has "$_h" "10.10.11.10	dc01.corp.local" "fqdn from smb-os-discovery"
has "$_h" "10.10.11.10	corp.local"      "ad domain name"
ok  "$(grep -c . $RT_HOSTS_INDEX)" "7" "nothing else was scraped"
rt-host-harvest $RT_DOTFILES/tools/fixtures/services.nmap
ok  "$(grep -c . $RT_HOSTS_INDEX)" "7" "re-harvesting is idempotent"
ok  "$(grep -c '^[0-9.]*	[0-9.]*$' $RT_HOSTS_INDEX)" "0" "addresses are never stored as names"

# ==============================================================================
# guard: the parts that need the host index, so they run after it is populated
# ==============================================================================
t "guard: a scope entry it cannot evaluate is a diagnostic, not a verdict"
# A hostname in scope.txt used to make every address on the line read as out of
# scope. `target boxy.htb` seeded exactly that, so the guard condemned the box
# you had just loaded -- and a warning that cries wolf is one you learn to
# dismiss, which is the failure this whole module is built to avoid.
TARGET_DIR=$OPS/boxy
print -rl -- 'boxy.htb' > $TARGET_DIR/scope.txt
_pin_net tun0
ok "$(_rt_guard_check 'nmap -p- 10.10.11.42')" "" "an unusable scope file condemns nothing"
ok "$(_rt_scope_entries $TARGET_DIR/scope.txt)" "" "and offers no usable entries"
_rt_scope_load $TARGET_DIR/scope.txt
ok "${_rt_scope_bad[1]}" "boxy.htb" "the entry is recorded as unusable"
# Reported out of band, once per version of the file -- not on every line.
_rt_scope_notified=""
has "$(_rt_scope_nudge)" "1 unusable entry" "the nudge reports it"
has "$(_rt_scope_nudge)" ""                 "and not a second time for the same file"

print -rl -- '10.10.11.0/24' 'boxy.htb' > $TARGET_DIR/scope.txt
ok  "$(_rt_guard_check 'nmap 10.10.11.42')" "" "a usable entry still admits what it covers"
has "$(_rt_guard_check 'nmap 10.10.99.7')" "out of scope" "and still enforces against what it does not"

t "guard: hostnames, resolved through the scan-derived host index"
# Only names the index knows are considered, so an unknown name cannot produce a
# warning -- and no DNS lookup happens on the accept-line path.
print -rl -- '10.10.11.40/30' > $TARGET_DIR/scope.txt
_rt_hostmap_stamp=""
ok  "$(_rt_guard_check 'nmap -p- boxy.htb')"  "" "an in-scope name is silent"
has "$(_rt_guard_check 'nmap -p- dc01.corp.local')" "dc01.corp.local (10.10.11.10)" \
    "an out-of-scope name warns, and names the address"
has "$(_rt_guard_check 'curl http://dc01.corp.local:8080/x?a=1')" "dc01.corp.local" \
    "found inside a url with a port and a query"
has "$(_rt_guard_check 'ssh svc@dc01.corp.local')" "dc01.corp.local" "and after a user@ prefix"
ok  "$(_rt_guard_check 'curl https://github.com/x')" "" "a name absent from the index is ignored"
ok  "$(_rt_guard_check 'vim notes.md')"              "" "a dotted filename is not a hostname"

# ==============================================================================
# redaction
# ==============================================================================
typeset -g LHOST="" RHOST="" DOMAIN="" DC="" U="" P="" HASH="" FILE="" SUBNET="" PORT=""
source $RT_DOTFILES/shell/zsh/redact.zsh

t "redaction: what must survive"
# Over-redaction is its own failure: a ledger that eats nmap's port list is a
# ledger you stop trusting, and then you turn the whole thing off.
typeset -A _keep=(
    'nmap -Pn -p- 10.10.11.42'                    'nmap -Pn -p- 10.10.11.42'
    'nmap -Pn -sCV -p 445,139,3389 10.10.11.42'   'nmap -Pn -sCV -p 445,139,3389 10.10.11.42'
    'nmap -p 1-65535 10.10.11.42'                 'nmap -p 1-65535 10.10.11.42'
    'ssh -L 8081:10.10.11.5:80 -N svc@10.10.11.42' 'ssh -L 8081:10.10.11.5:80 -N svc@10.10.11.42'
    'git clone git@github.com:owlshells/dots.git'  'git clone git@github.com:owlshells/dots.git'
    'smbmap -H 10.10.11.42 -u svc'                 'smbmap -H 10.10.11.42 -u svc'
    'smbclient //h/share -U svc'                   'smbclient //h/share -U svc'
    'hashcat -m 1000 h.txt rockyou.txt'            'hashcat -m 1000 h.txt rockyou.txt'
    'sudo mkdir -p /opt/Mythic/loot'               'sudo mkdir -p /opt/Mythic/loot'
    'mkdir -p scans'                               'mkdir -p scans'
    'cp -p src dst'                                'cp -p src dst'
    'psql -h db -p 5432 -U svc'                    'psql -h db -p 5432 -U svc'
    # A quoted argument is one shell word, so the credential-spec rule used to
    # match a colon and an @ anywhere in ordinary prose and eat everything
    # between them. Conventional-commit subjects with an @ mention hit it daily.
    'git commit -m "fix: mention user@example.com"' 'git commit -m "fix: mention user@example.com"'
    'echo "call at 10:30 or mail bob@corp.com"'     'echo "call at 10:30 or mail bob@corp.com"'
)
for _in in ${(k)_keep}; do ok "$(_rt_redact $_in)" "${_keep[$_in]}" "untouched: $_in"; done
ok "$(_rt_redact "nxc smb h -u '' -p ''")"   "nxc smb h -u '' -p ''"   "null session is not a secret"
ok "$(_rt_redact 'nxc smb h -u guest -p ""')" 'nxc smb h -u guest -p ""' "empty double quotes too"

t "redaction: what must not survive"
has "$(_rt_redact 'nxc smb h -u svc -p Passw0rd')"          '{{redacted}}' "-p value"
ok  "$(_rt_redact 'nxc smb h -u svc -p Passw0rd')" 'nxc smb h -u svc -p {{redacted}}' "and nothing else"
has "$(_rt_redact 'nxc ldap dc -u s --password Winter2025')" '{{redacted}}' "--password value"
has "$(_rt_redact 'curl --pass=abc123 https://x')"          'pass={{redacted}}' "--flag=value form"
has "$(_rt_redact 'nxc smb dc -u s -H aad3b435b51404eeaad3b435b51404ee')" '{{redacted}}' "ntlm hash"
has "$(_rt_redact 'impacket-secretsdump corp/svc:Passw0rd@10.10.11.10')" 'svc:{{redacted}}@' "impacket target spec"
has "$(_rt_redact 'curl https://user:s3cr3t@example.com/a')" 'user:{{redacted}}@' "credential in a url"
has "$(_rt_redact 'smbclient //h/s -U svc%Passw0rd')"       'svc%{{redacted}}' "samba user%password"
has "$(_rt_redact 'AWS_SECRET_ACCESS_KEY=wJalr aws s3 ls')" '{{redacted}}' "secret-named assignment"
has "$(_rt_redact "export U=svc P='Passw0rd!'")"            'P={{redacted}}' "our own P= convention"
has "$(_rt_redact 'sshpass -p hunter2 ssh a@b')"            '{{redacted}}' "sshpass"

# An all-digit value is only ambiguous after a short flag, where -p might be a
# port list. After an unambiguous indicator it is a password whatever it looks
# like -- these leaked in cleartext until the port-list check was scoped to the
# short-flag path, and every secret in this file being non-numeric is why the
# suite stayed green through it.
has "$(_rt_redact 'nxc ldap dc -u s --password 12345678')"  '{{redacted}}' "numeric --password value"
has "$(_rt_redact 'nxc ldap dc -u s --password=87654321')"  '{{redacted}}' "numeric --password=value"
has "$(_rt_redact 'PASSWORD=12345678 ./run.sh')"            'PASSWORD={{redacted}}' "numeric PASSWORD="
has "$(_rt_redact 'GITHUB_TOKEN=1234567890 gh auth login')" 'GITHUB_TOKEN={{redacted}}' "all-digit token"

t "redaction: pwdump output, the one rule that is not about a command line"
# tmux pane logging captures screen output, so a dumped hash table reaches disk
# through a path the argv-shaped rules never see. Name and RID survive on
# purpose -- which accounts you dumped is the finding you write up.
ok "$(_rt_redact 'Administrator:500:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::')" \
   'Administrator:500:{{redacted}}:{{redacted}}:::' "sam dump line keeps the account and rid"
ok "$(_rt_redact 'CORP.LOCAL\svc:1104:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::')" \
   'CORP.LOCAL\svc:1104:{{redacted}}:{{redacted}}:::' "ntds dump line with a domain prefix"
ok "$(_rt_redact 'echo "call at 10:30 or mail bob@corp.com"')" \
   'echo "call at 10:30 or mail bob@corp.com"' "prose with a colon is not a hash table"
ok "$(_rt_redact 'ssh -L 8081:10.10.11.5:80 -N svc@10.10.11.42')" \
   'ssh -L 8081:10.10.11.5:80 -N svc@10.10.11.42' "a port-forward spec is not a hash table"

t "redaction: the ambiguous short flag is gated on the tool"
# `-p` is a password in netexec and make-parents in mkdir. Found on real logs.
ok "$(_rt_redact 'sudo mkdir -p /opt/x')" 'sudo mkdir -p /opt/x' "mkdir keeps its path"
ok "$(_rt_redact 'nxc smb h -u s -p Passw0rd')" 'nxc smb h -u s -p {{redacted}}' "netexec still redacted"
ok "$(_rt_redact 'sudo proxychains nxc smb h -u s -p Passw0rd')" \
   'sudo proxychains nxc smb h -u s -p {{redacted}}' "wrappers are seen through"
ok "$(_rt_redact 'sometool -p Passw0rd')" 'sometool -p Passw0rd' \
   "an unlisted tool's bare -p is left alone (documented miss)"
has "$(_rt_redact 'sometool --password Passw0rd')" '{{redacted}}' \
   "but its unambiguous long form is still caught"

t "redaction: leaks that were found the hard way"
ok "$(_rt_redact "nxc smb h -u svc -p 'Pass word 1'")" 'nxc smb h -u svc -p {{redacted}}' \
   "a password containing spaces leaves nothing behind"
ok "$(_rt_redact "smbclient //h/s -U 'CORP\svc%Passw0rd'")" "smbclient //h/s -U 'CORP\svc%{{redacted}}'" \
   "quoted user%password keeps its closing quote"
ok "$(_rt_redact 'smbmap -H 10.10.11.42 -u svc -p Passw0rd')" 'smbmap -H 10.10.11.42 -u svc -p {{redacted}}' \
   "-H keeps a host but redacts a hash"

t "redaction: idempotent and switchable"
typeset -g _once=$(_rt_redact 'nxc smb h -u s -p Passw0rd')
ok "$(_rt_redact $_once)" "$_once" "redacting twice changes nothing"
ok "$(RT_REDACT=0 _rt_redact 'nxc smb h -u s -p Passw0rd')" 'nxc smb h -u s -p Passw0rd' "RT_REDACT=0 disables"
ok "$(_rt_redact '')" "" "empty input"

t "redaction: the zsh and awk implementations agree"
# The live path must not fork, the scrub path runs from bash. Two versions is
# the cost; drift between them is the risk, so it is asserted.
typeset -g _corpus=$OPS/corpus.txt
print -rl -- \
  'nmap -Pn -p- 10.10.11.42' 'nmap -p 445,139 10.10.11.42' \
  "nxc smb h -u '' -p ''" 'nxc smb h -u guest -p ""' \
  'nxc smb h -u svc -p Passw0rd' 'nxc ldap dc -u s --password Winter2025 --shares' \
  'nxc smb dc -u s -H aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0' \
  'impacket-secretsdump corp.local/svc:Passw0rd@10.10.11.10' \
  'impacket-psexec -hashes :31d6cfe0d16ae931b73c59d7e0c089c0 corp/a@1.2.3.4' \
  'curl https://user:s3cr3t@example.com/api' 'curl --pass=abc123 https://x' \
  'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI aws s3 ls' 'sshpass -p hunter2 ssh a@b' \
  "smbclient //h/share -U 'CORP\svc%Passw0rd'" 'rpcclient -U svc%Passw0rd 10.10.11.10' \
  'smbmap -H 10.10.11.42 -u svc -p Passw0rd' 'ssh -L 8081:10.10.11.5:80 -N svc@10.10.11.42' \
  'git clone git@github.com:owlshells/dots.git' "nxc smb h -u svc -p 'Pass word 1'" \
  'git commit -m "fix: mention user@example.com"' 'echo "call at 10:30 or mail bob@corp.com"' \
  'nxc ldap dc -u s --password 12345678' 'nxc ldap dc -u s --password=87654321' \
  'PASSWORD=12345678 ./run.sh' 'GITHUB_TOKEN=1234567890 gh auth login' \
  'nmap -p 80,443 10.10.11.42' \
  'Administrator:500:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::' \
  'CORP.LOCAL\svc:1104:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::' \
  '[*] Dumping local SAM hashes (uid:rid:lmhash:nthash)' \
  > $_corpus
typeset -g _z=$(while IFS= read -r l; do _rt_redact "$l"; done < $_corpus)
typeset -g _a=$(rt-redact < $_corpus)
if [[ $_z == $_a ]]; then
    ok "1" "1" "both implementations agree on $(wc -l < $_corpus) command lines"
else
    fail_lines=$(diff <(print -r -- "$_z") <(print -r -- "$_a") | head -8)
    ok "$fail_lines" "" "implementations diverge"
fi

t "redaction: the write path actually applies it"
: > $RT_CMD_INDEX; _rt_recall_mem=()
_rt_index_add 'nxc smb 10.10.11.42 -u svc -p SuperSecret123'
ok "$(grep -c SuperSecret123 $RT_CMD_INDEX)" "0" "secret never reaches the index"
has "$(cat $RT_CMD_INDEX)" '{{redacted}}' "the placeholder is what lands"
ok "${_rt_recall_mem[(I)*SuperSecret123*]}" "0" "and never reaches the ghost-text corpus"

# ==============================================================================
# arsenal-ng variable bridge
# ==============================================================================
typeset -g RT_ARSENAL_VARS=$OPS/arsenal-vars.json
source $RT_DOTFILES/shell/zsh/pickers.zsh

_vars() { python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True))' "$RT_ARSENAL_VARS" 2>/dev/null }

t "arsenal bridge: session state becomes arsenal variables"
rm -f $RT_ARSENAL_VARS
RHOST=10.10.11.42 DOMAIN=corp.local U=svc_sql DC=10.10.11.10 LHOST=10.10.14.7 P='Passw0rd!' \
    _rt_arsenal_sync
typeset -g _v=$(_vars)
has "$_v" '"target": "10.10.11.42"'    "RHOST becomes {{target}}"
has "$_v" '"target_ip": "10.10.11.42"' "and {{target_ip}}"
has "$_v" '"domain": "corp.local"'     "DOMAIN becomes {{domain}}"
has "$_v" '"username": "svc_sql"'      "U becomes {{username}}"
has "$_v" '"dc_ip": "10.10.11.10"'     "DC becomes {{dc_ip}}"
has "$_v" '"lhost": "10.10.14.7"'      "LHOST becomes {{lhost}}"
ok  "$(grep -c password $RT_ARSENAL_VARS)" "0" \
    "the password is NOT persisted by default"
ok  "$(stat -c %a $RT_ARSENAL_VARS)" "600" "written 0600"

t "arsenal bridge: opt-in password, and merge safety"
RHOST=10.10.11.42 U=svc_sql P='Passw0rd!' RT_ARSENAL_SYNC_PASSWORD=1 _rt_arsenal_sync
has "$(_vars)" '"password": "Passw0rd!"' "RT_ARSENAL_SYNC_PASSWORD=1 includes it"
# A variable set by hand inside the TUI must survive the next sync.
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["wordlist"]="/usr/share/seclists/x.txt";json.dump(d,open(p,"w"))' $RT_ARSENAL_VARS
RHOST=10.10.12.99 U=svc_sql _rt_arsenal_sync
has "$(_vars)" '"wordlist": "/usr/share/seclists/x.txt"' "variables set in the TUI survive a re-sync"
has "$(_vars)" '"target": "10.10.12.99"'                 "and the new target lands"

t "arsenal bridge: degrades quietly"
rm -f $RT_ARSENAL_VARS
RHOST="" DOMAIN="" U="" DC="" LHOST="" _rt_arsenal_sync
[[ -f $RT_ARSENAL_VARS ]] && ok "file" "no file" "no session state writes no file" \
                          || ok "no file" "no file" "no session state writes no file"
print -r -- 'not json at all' > $RT_ARSENAL_VARS
RHOST=10.10.11.42 _rt_arsenal_sync
has "$(_vars)" '"target": "10.10.11.42"' "a corrupt store is replaced, not fatal"

# ==============================================================================
# the workflow helpers
#
# shell/functions.sh had no coverage at all, which is how `fuzz` shipped passing
# `- ic` to ffuf instead of `-ic` and stayed broken. The helpers that end in an
# exec are asserted through the RT_DRYRUN seam, which prints the argv one word
# per line -- so a single argument can be pinned by exact match rather than by a
# substring that would match the broken form too.
# ==============================================================================
typeset -g SECLISTS=/nonexistent-seclists WORDLISTS=/nonexistent-wordlists
source $RT_DOTFILES/shell/functions.sh

_argv() { RT_DRYRUN=1 "$@" 2>/dev/null }
_hasword() { (( _t_run++ )); [[ ${${(f)1}[(I)$2]} -gt 0 ]] && print -r -- "  ok    $3" \
        || { print -r -- "  FAIL  $3"; print -r -- "          no line exactly: ${(qq)2}"
             print -r -- "          got: ${(qq)1}"; _t_fail=1 }; }

t "fuzz: the argument that was broken for months"
typeset -g _fz="$(_argv fuzz http://boxy/FUZZ)"
_hasword "$_fz" '-ic'  "-ic is one word (it was '- ic', two)"
_hasword "$_fz" 'ffuf' "invokes ffuf"
_hasword "$_fz" 'http://boxy/FUZZ' "passes the url through"
ok "${_fz}" "${_fz//$'\n'-$'\n'/}" "no bare '-' argument survives"
typeset -g _fz2="$(_argv fuzz http://boxy/FUZZ -t 40 -mc 200)"
_hasword "$_fz2" '-t' "extra args pass through"
_hasword "$_fz2" '40' "and their values"
fuzz >/dev/null 2>&1; rc $? 1 "no url is an error"

t "scan: staged nmap"
typeset -g TARGET_DIR=$OPS/scanbox; mkdir -p $TARGET_DIR/scans
cp $RT_DOTFILES/tools/fixtures/allports.nmap $TARGET_DIR/scans/allports.nmap
typeset -g _sc="$(RT_DRYRUN=1 scan 10.10.11.42 2>/dev/null)"
_hasword "$_sc" '-p-'   "stage one sweeps all ports"
_hasword "$_sc" '-sCV'  "stage two runs the service scripts"
has "$_sc" '-p22,80,139,445,5985' "only the open tcp ports reach stage two"
ok "${_sc[(I)53]}" "0" "the udp line is not scraped as a tcp port"
scan 2>/dev/null >/dev/null; rc $? 1 "no target is an error"

t "target: validation"
for bad in 'RHOST=10.0.0.1' './x' '../x' 'a/b'; do
    target "$bad" >/dev/null 2>&1; rc $? 1 "rejected: ${(qq)bad}"
done
# An empty argument is not a rejection: it is indistinguishable from no argument
# at all, which is the documented "show me what is loaded" form.
has "$(target '')" "RHOST=" "an empty argument shows status, as no argument does"

t "target: scaffolding"
typeset -g TARGET_NAME="" RT_CMDLOG=""
target 10.10.11.42 newbox >/dev/null
ok "$RHOST"      "10.10.11.42"          "RHOST set"
ok "$TARGET_DIR" "$OPS/newbox"          "TARGET_DIR under \$OPS"
ok "$RT_CMDLOG"  "$OPS/newbox/notes/commands.log" "the ledger points at the box"
for d in scans loot exploit notes www; do
    [[ -d $OPS/newbox/$d ]] && rc 0 0 "created $d/" || rc 1 0 "created $d/"
done

t "target: seeds a scope file the guard can actually evaluate"
# `target boxy.htb` used to write the hostname verbatim, and the guard then read
# every address on the line as out of scope -- crying wolf on the box you had
# just loaded. A name is resolved, and an unresolvable one seeds no entry at all.
ok "$(_rt_scope_entries $OPS/newbox/scope.txt)" "10.10.11.42" "an address seeds itself"
target nonexistent.invalid ghost >/dev/null
ok "$(_rt_scope_entries $OPS/ghost/scope.txt)" "" "an unresolvable name seeds no entry"
has "$(<$OPS/ghost/scope.txt)" "did not resolve" "but says why, in a comment"
_pin_net tun0
TARGET_DIR=$OPS/ghost
ok "$(_rt_guard_check 'nmap -p- 10.10.11.42')" "" "so the guard stays inert rather than crying wolf"

t "encoders"
ok "$(b64 'hello world')"        "aGVsbG8gd29ybGQ=" "b64 of an argument"
ok "$(ub64 'aGVsbG8gd29ybGQ=')" "hello world"      "ub64 round-trips"
ok "$(print -n 'hello world' | b64)" "aGVsbG8gd29ybGQ=" "b64 from stdin"
ok "$(urlenc 'a b&c=d/e')"      "a%20b%26c%3Dd/e"  "urlenc"

t "note: appends to the box's notes"
TARGET_DIR=$OPS/newbox
note "creds in config.php" >/dev/null
has "$(<$OPS/newbox/notes/README.md)" "creds in config.php" "the line lands"

print -r -- ""
if (( _t_fail )); then print -r -- "FAILED  ($_t_run checks)"; else print -r -- "all pass ($_t_run checks)"; fi
exit $_t_fail
