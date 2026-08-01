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
# -F b:zstat loads *only* the zstat builtin. A bare `zmodload zsh/stat` also
# defines `stat`, which shadows /usr/bin/stat with an incompatible one for the
# whole interactive shell -- it broke the `stat -c` in shell/zsh/hosts.zsh and in
# the test suite the moment it was added.
zmodload -F zsh/stat b:zstat 2>/dev/null

typeset -g _rt_guard_ack=""        # buffer the operator has already been warned about

# "Has this file changed since I last read it", forkless where zsh/stat loaded.
#
# Returns non-zero when it cannot answer -- no module, or no such file -- and the
# callers treat that as "reload". Degrading to re-reading a small file is cheap;
# degrading to *not* reading it is not, and that is what an earlier version did:
# with zsh/stat unloaded the host map stayed permanently empty and the hostname
# check was silently off while the whole suite stayed green.
#
# Size is in the stamp as well as mtime because mtime has one-second granularity
# and an edit that lands in the same second as the last read would otherwise keep
# serving the stale parse. Size alone does not close that either -- swapping one
# /24 for another of the same length changes neither -- so a file touched within
# the last second is always treated as changed. `scope add 10.10.99.0/24` and then
# Enter is that case exactly, and it has to see the new entry.
_rt_file_stamp() {
    local -a st
    [[ -r $1 ]] || return 1
    zstat -A st +mtime -- $1 2>/dev/null || return 1
    local -a sz; zstat -A sz +size -- $1 2>/dev/null || sz=(0)
    (( st[1] >= EPOCHSECONDS - 1 )) && return 1
    typeset -g REPLY="$1:$st[1]:$sz[1]"
}

# The ack means "you were warned about this exact line, a moment ago" -- press
# enter twice in a row and it runs. It must not outlive the line it belongs to.
#
# Clearing it only when a command runs was not enough: warn, then abandon the
# line with ^C, and the ack survived. Retyping the same command later matched it
# and ran with no warning at all -- silently skipping the check on a command the
# operator had never confirmed. A new prompt means a new line, so the ack dies
# with the old one, whether the previous line ran or was thrown away.
_rt_guard_reset_ack() { _rt_guard_ack=""; }
add-zsh-hook precmd _rt_guard_reset_ack

# --- IPv4 arithmetic -----------------------------------------------------------
# Sets REPLY rather than printing, for the same reason _rt_redact_r does: this
# runs from the accept-line widget on every Enter, and a command substitution
# here is a fork. Two per CIDR comparison, times every scope entry, times every
# address on the line -- it was the whole cost of the guard. The printing
# wrapper below is kept for tests and anything off the hot path.
_rt_ip2int_r() {
    local -a o; o=(${(s:.:)1})
    (( ${#o} == 4 )) || return 1
    local q
    for q in $o; do [[ $q == <0-255> ]] || return 1; done
    typeset -g REPLY=$(( (o[1] << 24) + (o[2] << 16) + (o[3] << 8) + o[4] ))
}

_rt_ip2int() {
    local REPLY
    _rt_ip2int_r "$1" || return 1
    print -r -- $REPLY
}

# Does this string parse as an address or a CIDR at all? Distinct from
# _rt_in_cidr, which answers "is it contained" and cannot tell an unparseable
# spec from a well-formed one that simply does not match -- both are a return of
# 1. Telling those apart is the difference between reporting a broken scope file
# and reporting a scope violation.
_rt_spec_valid() {
    local spec=$1 net=${1%%/*} bits=${1#*/} REPLY
    [[ $bits == $spec ]] && bits=32
    [[ $bits == <0-32> ]] || return 1
    _rt_ip2int_r "$net"
}

# _rt_in_cidr <ip> <cidr|ip>   — bare IPs are treated as /32
_rt_in_cidr() {
    local ip=$1 spec=$2 net=${2%%/*} bits
    bits=${spec#*/}
    [[ $bits == $spec ]] && bits=32
    [[ $bits == <0-32> ]] || return 1
    local a b REPLY
    _rt_ip2int_r "$ip"  || return 1; a=$REPLY
    _rt_ip2int_r "$net" || return 1; b=$REPLY
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
_rt_scope_file_r() {
    local d f
    for d in "$TARGET_DIR" "$OPS"; do
        [[ -n $d ]] || continue                # unset var must not become /scope.txt
        f="$d/scope.txt"
        [[ -r $f ]] && { typeset -g REPLY=$f; return 0; }
    done
    return 1
}

_rt_scope_file() {
    local REPLY
    _rt_scope_file_r || return 1
    print -r -- $REPLY
}

# Read the scope file once per edit, not once per address on the line. Parsing it
# inside the per-address loop meant a fork and a re-read for every IP typed.
#
# Entries are split into the ones _rt_in_cidr can actually evaluate and the ones
# it cannot, because conflating the two is a bug: a hostname in scope.txt made
# every address fail the containment test and so read as a violation. `target
# boxy.htb` seeded exactly that, and the guard then cried wolf on the box you had
# just loaded -- a guard that cries wolf is one you learn to dismiss. An entry we
# cannot evaluate is an operator mistake to report, not a verdict to act on.
typeset -ga _rt_scope_ok=() _rt_scope_bad=()
typeset -g  _rt_scope_stamp=""

_rt_scope_load() {
    local file=$1 REPLY=""
    _rt_file_stamp "$file" && [[ $REPLY == $_rt_scope_stamp ]] && return
    _rt_scope_stamp=$REPLY
    _rt_scope_ok=() _rt_scope_bad=()
    [[ -r $file ]] || return
    local line
    for line in ${(f)"$(<$file)"}; do
        line=${line%%\#*}                      # strip comments
        line=${line//[[:space:]]/}
        [[ -n $line ]] || continue
        if _rt_spec_valid "$line"; then
            _rt_scope_ok+=("$line")
        else
            _rt_scope_bad+=("$line")
        fi
    done
}

# The usable entries, one per line. Kept as a function because `scope` and the
# tests read it; the guard itself uses the arrays directly.
_rt_scope_entries() {
    _rt_scope_load "$1"
    (( ${#_rt_scope_ok} )) && print -rl -- $_rt_scope_ok
    return 0
}

_rt_in_scope() {
    local ip=$1 entry
    for entry in $_rt_scope_ok; do
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
    _rt_scope_load "$file"
    local a8=${ip%%.*}
    for entry in $_rt_scope_ok; do
        [[ ${entry%%.*} == $a8 ]] && return 0
    done
    return 1
}

# --- names ---------------------------------------------------------------------
# A command aimed at `dc01.corp.local` was not checked at all: only IPv4 literals
# were ever extracted. Resolving on the hot path is not an option -- that is a
# fork and a DNS round trip on every Enter -- but shell/zsh/hosts.zsh already
# maintains an ip<TAB>name index harvested from your own scans, so a name on the
# line can be mapped locally.
#
# Accepted miss, in the spirit of the ones documented in shell/zsh/redact.zsh: a
# name that is not in the index is not checked. Structurally that also means a
# name we know nothing about can never produce a false warning.
typeset -gA _rt_hostmap=()
typeset -g  _rt_hostmap_stamp=""

_rt_hostmap_load() {
    local file=${RT_HOSTS_INDEX:-${OPS:-$HOME/ops}/.hosts-index} REPLY=""
    _rt_file_stamp "$file" && [[ $REPLY == $_rt_hostmap_stamp ]] && return
    _rt_hostmap_stamp=$REPLY
    _rt_hostmap=()
    [[ -r $file ]] || return
    local line ip name
    for line in ${(f)"$(<$file)"}; do
        ip=${line%%$'\t'*}; name=${line#*$'\t'}
        [[ -n $name && $name != $ip ]] && _rt_hostmap[$name]=$ip
    done
}

# --- the check -----------------------------------------------------------------
# Emits warning text on stdout, or nothing when the command is fine.
_rt_guard_check() {
    emulate -L zsh
    setopt extended_glob
    local buf=$1
    [[ -z ${buf//[[:space:]]/} ]] && return

    # Extract addresses without forking. This used to be a `grep -oE` in a
    # command substitution -- one fork on every Enter, before any of the work.
    # zsh's own =~ finds the same matches; MEND lets the scan continue past each
    # one, which is what picks addresses out of URLs and impacket target specs.
    local -a ips
    local rest=$buf
    while [[ $rest =~ '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' ]]; do
        ips+=("$MATCH")
        rest=${rest[$((MEND+1)),-1]}
    done

    # Names, mapped through the scan-derived host index. Only tokens that look
    # like a dotted name are considered, and only ones the index knows resolve to
    # anything -- so this cannot invent a warning about a hostname it has never
    # seen. The address a name maps to is checked exactly like a typed one; the
    # name is what gets reported, because that is what the operator wrote.
    local -A named=()
    local w bare
    _rt_hostmap_load
    if (( ${#_rt_hostmap} )); then
        for w in ${(z)buf}; do
            bare=${${w#*://}%%[/:?]*}          # strip scheme, path, port, query
            bare=${bare##*@}                   # and any user[:pass]@ prefix
            [[ $bare == *.* && $bare != *[^A-Za-z0-9._-]* ]] || continue
            [[ -n ${_rt_hostmap[$bare]} ]] && named[$bare]=${_rt_hostmap[$bare]}
        done
    fi

    (( ${#ips} + ${#named} )) || return

    _rt_net_refresh

    local scope="" REPLY=""
    _rt_scope_file_r && scope=$REPLY
    local -a oos novpn
    local spec ip

    # An unconfigured shell stays silent: warn only once there is an engagement
    # loaded or a scope declared. Otherwise this fires on ordinary lab traffic.
    local armed=""
    [[ -n $scope || -n $RHOST || -n $TARGET_DIR ]] && armed=1
    [[ -n $armed ]] || return

    # A scope file whose entries cannot be evaluated enforces nothing, so it must
    # not be allowed to condemn anything either -- that is the wolf-cry. Drop to
    # "no scope" and let _rt_scope_nudge report the broken entries out of band.
    if [[ -n $scope ]]; then
        _rt_scope_load "$scope"
        (( ${#_rt_scope_ok} )) || scope=""
    fi

    # label -> address, so a name reports as the name and an address as itself
    local -A subjects=()
    for spec in ${(u)ips}; do subjects[$spec]=${spec%%/*}; done
    for w in ${(k)named}; do subjects[$w]=${named[$w]}; done

    local label
    for label in ${(k)subjects}; do
        ip=${subjects[$label]}
        _rt_ip2int_r "$ip" || continue
        _rt_is_local "$ip" && continue

        if [[ -n $scope ]] && _rt_scope_relevant "$ip" "$scope" \
           && ! _rt_in_scope "$ip" "$scope"; then
            # A name is ambiguous on its own in a warning, so carry the address.
            [[ -n ${named[$label]} ]] && oos+=("$label ($ip)") || oos+=("$label")
            continue                            # out of scope subsumes no-vpn
        fi
        # Reachable only over the tunnel, and there is no tunnel.
        if [[ -z $_rt_vpn_iface ]] && _rt_is_rfc1918 "$ip"; then
            [[ -n ${named[$label]} ]] && novpn+=("$label ($ip)") || novpn+=("$label")
        fi
    done

    local -a msg
    (( ${#oos} ))   && msg+=("out of scope: ${(j:, :)${(o)oos}}   (${scope/#$HOME/~})")
    (( ${#novpn} )) && msg+=("no vpn interface up, but targeting ${(j:, :)${(o)novpn}}")
    (( ${#msg} ))   || return

    print -r -- "${(F)msg}
press enter again to run anyway"
}

# --- the broken-scope nudge ----------------------------------------------------
# An entry the guard cannot evaluate is a configuration mistake, so it is
# reported the way shell/zsh/hosts.zsh reports a missing /etc/hosts entry: once,
# above the next prompt, with the fix on the second line.
#
# It deliberately does NOT go through the warning path. Making it blocking meant
# a diagnostic on every line with an address in it and a second Enter to get past
# it, forever, until the file was fixed -- a nag, and this repo's whole argument
# is that a warning you learn to dismiss is worse than no warning. Once per
# version of the file is enough; edit the file and you hear about it again.
typeset -g _rt_scope_notified=""

_rt_scope_nudge() {
    local REPLY=""
    _rt_scope_file_r || return
    _rt_scope_load "$REPLY"
    (( ${#_rt_scope_bad} )) || return
    # Keyed on the broken entries themselves rather than on the file's stamp: the
    # stamp is deliberately unavailable for a second after an edit, and an empty
    # stamp compared against an empty "already told you" would read as a match and
    # suppress the nudge entirely. This also re-fires when the set changes.
    local key="$REPLY:${(j:,:)_rt_scope_bad}"
    [[ $key == $_rt_scope_notified ]] && return
    _rt_scope_notified=$key
    local noun=entries; (( ${#_rt_scope_bad} == 1 )) && noun=entry
    print -Pr -- "%F{214}⋯ scope.txt: ${#_rt_scope_bad} unusable $noun, ignored:%f ${(j:, :)_rt_scope_bad}"
    print -Pr -- "%F{245}  not an address or cidr — resolve it, then: scope add <ip|cidr>%f"
}
add-zsh-hook precmd _rt_scope_nudge

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
