# ~/dots/shell/zsh/hosts.zsh — the box you scanned becomes the box you can tab.
#
# A precmd hook harvests hostnames out of nmap output as it lands, and publishes
# them through zsh's standard hosts source:
#
#     zstyle ':completion:*:hosts' hosts ...
#
# Every completer built on _hosts — ssh, scp, ping, telnet, sftp, curl — picks
# them up for free. Nothing per-tool is overridden.
#
# Two completers are added by hand, for the tools that ship none: netexec, and
# the impacket family's shared credential grammar.
#
# awscli needs nothing; /usr/share/zsh/vendor-completions/_aws ships with Kali.

autoload -Uz add-zsh-hook

: ${RT_HOSTS_INDEX:=${OPS:-$HOME/ops}/.hosts-index}
export RT_HOSTS_INDEX

typeset -ga _rt_known_hosts=()
typeset -g  _rt_hosts_stamp=""

# --- harvest -------------------------------------------------------------------
_rt_hosts_refresh() {
    local -a scans
    scans=( ${TARGET_DIR:+$TARGET_DIR/scans/*.nmap(N)} )
    (( ${#scans} )) || return 1
    # Cheap change detection: newest scan file, by name+mtime.
    local stamp="${(f)$(stat -c '%n %Y' -- $scans 2>/dev/null)}"
    [[ $stamp == $_rt_hosts_stamp ]] && return 1
    _rt_hosts_stamp=$stamp
    rt-host-harvest $scans 2>/dev/null || return 1
    return 0
}

_rt_hosts_load() {
    _rt_known_hosts=()
    [[ -r $RT_HOSTS_INDEX ]] && _rt_known_hosts+=( ${(f)"$(cut -f2 -- $RT_HOSTS_INDEX 2>/dev/null)"} )
    # /etc/hosts entries you added by hand count as known too.
    if [[ -r /etc/hosts ]]; then
        _rt_known_hosts+=( ${(f)"$(awk '!/^[[:space:]]*#/ && NF>1 {for(i=2;i<=NF;i++) print $i}' /etc/hosts 2>/dev/null)"} )
    fi
    _rt_known_hosts=( ${(u)_rt_known_hosts:#} )
    zstyle ':completion:*:hosts' hosts $_rt_known_hosts
}

# One line, once, when a scan turns up names /etc/hosts does not have yet.
# Web work stalls on exactly this and the fix is one command away.
_rt_hosts_nudge() {
    local -a fresh
    local ip name
    while IFS=$'\t' read -r ip name; do
        [[ -n $name ]] || continue
        grep -qiE "[[:space:]]${name//./\\.}([[:space:]]|\$)" /etc/hosts 2>/dev/null && continue
        fresh+=("$ip $name")
    done < $RT_HOSTS_INDEX
    (( ${#fresh} )) || return
    local first=${fresh[1]}
    print -Pr -- "%F{245}⋯ ${#fresh} scanned name$( (( ${#fresh} > 1 )) && print -n s) not in /etc/hosts:%f ${fresh[1]#* }"
    print -Pr -- "%F{245}  addhost ${first%% *} ${(j: :)${(@)fresh#* }}%f"
}

_rt_hosts_hook() {
    if _rt_hosts_refresh; then
        _rt_hosts_load
        _rt_hosts_nudge
    fi
}
add-zsh-hook precmd _rt_hosts_hook
_rt_hosts_load

# --- completion: the known-host set --------------------------------------------
_rt_hosts_only() {
    local -a ips
    [[ -r $RT_HOSTS_INDEX ]] && ips=( ${(fu)"$(cut -f1 -- $RT_HOSTS_INDEX 2>/dev/null)"} )
    [[ -n $RHOST ]] && ips=( $RHOST $ips )
    [[ -n $DC ]]    && ips=( $DC $ips )
    _alternative \
        "known-hosts:known host:compadd -a _rt_known_hosts" \
        "addresses:scanned address:compadd -a ips"
}

# --- completion: netexec -------------------------------------------------------
_nxc() {
    local -a protos flags
    protos=( smb ldap winrm mssql ssh ftp rdp wmi vnc nfs )
    flags=(
        '-u[username, or a file of them]'
        '-p[password, or a file of them]'
        '-H[NTLM hash]'
        '-k[kerberos auth]'
        '-d[domain]'
        '--local-auth[authenticate locally, not to the domain]'
        '--shares[enumerate shares]'
        '--users[enumerate users]'
        '--groups[enumerate groups]'
        '--pass-pol[dump the password policy]'
        '--rid-brute[enumerate users by RID]'
        '--sam[dump SAM]'
        '--lsa[dump LSA secrets]'
        '--ntds[dump NTDS.dit]'
        '--continue-on-success[keep going after a valid login]'
        '-x[execute a command]'
        '-M[run a module]'
    )
    if (( CURRENT == 2 )); then
        _describe -t protocols 'protocol' protos
    elif (( CURRENT == 3 )) && [[ $words[3] != -* ]]; then
        _rt_hosts_only
    else
        _arguments -S $flags '*:target:_rt_hosts_only'
    fi
}
compdef _nxc nxc netexec 2>/dev/null

# --- completion: the impacket credential grammar -------------------------------
# Every impacket script takes the same domain/user:password@target string. It is
# the most retyped and most fat-fingered argument in AD work, and you already
# have the pieces loaded in $DOMAIN/$U/$P/$RHOST — so offer it assembled.
_rt_impacket_targets() {
    local dom=${DOMAIN:+${DOMAIN}/} tgt=${RHOST:-$DC}
    local -a vals disp
    if [[ -n $U && -n $tgt ]]; then
        if [[ -n $P ]]; then
            vals+=( "${dom}${U}:${P}@${tgt}" )
            disp+=( "${dom}${U}:<password>@${tgt}  -- full spec from the session" )
        fi
        vals+=( "${dom}${U}@${tgt}" )
        disp+=( "${dom}${U}@${tgt}  -- prompt for the password" )
        vals+=( "${dom}${U}@${tgt} -no-pass" )
        disp+=( "${dom}${U}@${tgt} -no-pass  -- no authentication" )
    elif [[ -n $tgt ]]; then
        vals+=( "${dom}@${tgt}" )
        disp+=( "${dom}@${tgt}  -- set \$U and \$P for a full spec" )
    fi
    (( ${#vals} )) || return 1
    compadd -Q -U -d disp -a vals
}

_rt_impacket() {
    case ${words[CURRENT-1]} in
        (-dc-ip|-target-ip|-ip) _rt_hosts_only; return ;;
    esac
    if (( CURRENT == 2 )) && [[ -z ${words[2]} ]]; then
        _rt_impacket_targets && return
    fi
    _default
}
compdef _rt_impacket -p 'impacket-*' 2>/dev/null
