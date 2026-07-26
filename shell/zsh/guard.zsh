# ~/dots/shell/zsh/guard.zsh — catch the command aimed at the wrong box.
#
# preexec cannot abort a command, so the check runs at line-accept time. It
# binds ^M to its own widget and delegates with `zle accept-line` rather than
# redefining accept-line, because zsh-autosuggestions loads before this file and
# has already wrapped that widget — replacing it would silently break their
# clear-on-accept.
#
# With no scope file the guard is inert and invisible. `target` seeds one.

autoload -Uz add-zsh-hook

typeset -g _rt_guard_ack=""        # buffer the operator has already been warned about

# --- IPv4 arithmetic -----------------------------------------------------------
_rt_ip2int() {
    local -a o; o=(${(s:.:)1})
    (( ${#o} == 4 )) || return 1
    local q
    for q in $o; do [[ $q == <0-255> ]] || return 1; done
    print -r -- $(( (o[1] << 24) + (o[2] << 16) + (o[3] << 8) + o[4] ))
}

# _rt_in_cidr <ip> <cidr|ip>   — bare IPs are treated as /32
_rt_in_cidr() {
    local ip=$1 spec=$2 net=${2%%/*} bits
    bits=${spec#*/}
    [[ $bits == $spec ]] && bits=32
    [[ $bits == <0-32> ]] || return 1
    local a b
    a=$(_rt_ip2int "$ip")  || return 1
    b=$(_rt_ip2int "$net") || return 1
    (( bits == 0 )) && return 0
    local mask=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    (( (a & mask) == (b & mask) ))
}

_rt_is_rfc1918() {
    local ip=$1
    _rt_in_cidr "$ip" 10.0.0.0/8     && return 0
    _rt_in_cidr "$ip" 172.16.0.0/12  && return 0
    _rt_in_cidr "$ip" 192.168.0.0/16 && return 0
    return 1
}

# On a network this host is directly attached to — no VPN needed to reach it.
_rt_is_local() {
    local ip=$1 net
    _rt_in_cidr "$ip" 127.0.0.0/8 && return 0
    for net in $_rt_local_nets; do
        _rt_in_cidr "$ip" "$net" && return 0
    done
    return 1
}

# --- scope ---------------------------------------------------------------------
# Nearest scope file wins: the box's own, else the engagement-wide one.
_rt_scope_file() {
    local d f
    for d in "$TARGET_DIR" "$OPS"; do
        [[ -n $d ]] || continue                # unset var must not become /scope.txt
        f="$d/scope.txt"
        [[ -r $f ]] && { print -r -- "$f"; return 0; }
    done
    return 1
}

_rt_scope_entries() {
    local line
    for line in ${(f)"$(<$1)"}; do
        line=${line%%\#*}                      # strip comments
        line=${line//[[:space:]]/}
        [[ -n $line ]] && print -r -- "$line"
    done
}

_rt_in_scope() {
    local ip=$1 entry
    for entry in ${(f)"$(_rt_scope_entries $2)"}; do
        _rt_in_cidr "$ip" "$entry" && return 0
    done
    return 1
}

# Is this address one the scope file is even talking about?
#
# Without this, every public address you touch on an internal engagement —
# package mirrors, 8.8.8.8, github — reads as "out of scope", and a warning that
# cries wolf is a warning you learn to dismiss. Private space is always checked;
# public space is checked only when the scope file itself reaches into the same
# /8, i.e. when you are actually doing external work in that neighbourhood.
_rt_scope_relevant() {
    local ip=$1 file=$2 entry
    _rt_is_rfc1918 "$ip" && return 0
    _rt_in_cidr "$ip" 100.64.0.0/10 && return 0        # CGNAT
    local a8=${ip%%.*}
    for entry in ${(f)"$(_rt_scope_entries $file)"}; do
        [[ ${entry%%.*} == $a8 ]] && return 0
    done
    return 1
}

# --- the check -----------------------------------------------------------------
# Emits warning text on stdout, or nothing when the command is fine.
_rt_guard_check() {
    local buf=$1
    [[ -z ${buf//[[:space:]]/} ]] && return

    local -a ips
    ips=( ${(u)${(f)"$(print -r -- "$buf" \
        | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' 2>/dev/null)"}} )
    (( ${#ips} )) || return

    _rt_net_refresh

    local scope="" ; scope=$(_rt_scope_file)
    local -a oos novpn
    local spec ip

    # An unconfigured shell stays silent: warn only once there is an engagement
    # loaded or a scope declared. Otherwise this fires on ordinary lab traffic.
    local armed=""
    [[ -n $scope || -n $RHOST || -n $TARGET_DIR ]] && armed=1
    [[ -n $armed ]] || return

    for spec in $ips; do
        ip=${spec%%/*}
        _rt_ip2int "$ip" >/dev/null || continue
        _rt_is_local "$ip" && continue

        if [[ -n $scope ]] && _rt_scope_relevant "$ip" "$scope" \
           && ! _rt_in_scope "$ip" "$scope"; then
            oos+=("$spec")
            continue                            # out of scope subsumes no-vpn
        fi
        # Reachable only over the tunnel, and there is no tunnel.
        if [[ -z $_rt_vpn_iface ]] && _rt_is_rfc1918 "$ip"; then
            novpn+=("$spec")
        fi
    done

    local -a msg
    (( ${#oos} ))   && msg+=("out of scope: ${(j:, :)oos}   (${scope/#$HOME/~})")
    (( ${#novpn} )) && msg+=("no vpn interface up, but targeting ${(j:, :)novpn}")
    (( ${#msg} ))   || return

    print -r -- "${(F)msg}
press enter again to run anyway"
}

# --- the widget ----------------------------------------------------------------
rt-accept-line() {
    local warn
    warn=$(_rt_guard_check "$BUFFER")
    if [[ -n $warn && $BUFFER != $_rt_guard_ack ]]; then
        _rt_guard_ack=$BUFFER
        zle -M "$warn"
        return 0
    fi
    _rt_guard_ack=""
    zle accept-line                             # autosuggestions' wrapper, if present
}
zle -N rt-accept-line
bindkey '^M' rt-accept-line
bindkey '^J' rt-accept-line

# --- scope management ----------------------------------------------------------
# Config, not workflow — you touch this once per engagement, and `target`
# already seeds it with the box you named.
scope() {
    local file="${TARGET_DIR:-$OPS}/scope.txt"
    case ${1:-} in
        add)
            shift
            (( $# )) || { print -u2 "usage: scope add <ip|cidr> [...]"; return 1; }
            mkdir -p "${file:h}" || return 1
            print -rl -- "$@" >> "$file"
            print -r -- "scope += $* -> ${file/#$HOME/~}"
            ;;
        edit) ${EDITOR:-vim} "$file" ;;
        "")
            if [[ -r $file ]]; then
                print -r -- "# ${file/#$HOME/~}"
                cat "$file"
            else
                print -r -- "no scope file (${file/#$HOME/~}) — guard is inert"
            fi
            ;;
        *) print -u2 "usage: scope [add <ip|cidr>... | edit]"; return 1 ;;
    esac
}
