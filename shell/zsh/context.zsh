# ~/dots/shell/zsh/context.zsh — ambient operational state in the prompt.
#
# Claims RPROMPT only; Kali's stock twoline prompt leaves it unset. It is
# reapplied from a precmd hook rather than assigned once, because Kali's
# toggle_oneline_prompt (Ctrl-P) blanks RPROMPT every time you toggle.
#
# Colour is signal, not decoration: the bar is uniformly dim until something
# needs attention, and only then does it take a colour.

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook

: ${_RT_NET_TTL:=10}          # seconds between interface re-reads

typeset -g  _rt_vpn_iface=""
typeset -g  _rt_net_checked=0
typeset -ga _rt_local_nets=()

# --- interface state, cached ---------------------------------------------------
# One `ip` fork per _RT_NET_TTL seconds, not one per prompt. Populates both the
# VPN interface name and the list of locally-attached networks (ip/prefix),
# which guard.zsh reuses for its "is this even routable without the VPN" check.
_rt_net_refresh() {
    (( EPOCHSECONDS - _rt_net_checked < _RT_NET_TTL )) && return
    _rt_net_checked=$EPOCHSECONDS
    _rt_vpn_iface=""
    _rt_local_nets=()
    local line iface cidr
    for line in ${(f)"$(ip -4 -o addr show 2>/dev/null)"}; do
        iface=${${(z)line}[2]}
        cidr=${${line##*inet }%% *}
        [[ -n $cidr ]] && _rt_local_nets+=("$cidr")
        case $iface in
            (tun*|tap*|ppp*) [[ -z $_rt_vpn_iface ]] && _rt_vpn_iface=$iface ;;
        esac
    done
}

# --- the bar -------------------------------------------------------------------
# Every segment is skipped when its source variable is unset, so a shell with no
# engagement loaded shows an empty right prompt.
_rt_context_bar() {
    _rt_net_refresh

    local -a seg
    local dim='%F{242}'                       # segments return to this, not %f

    # the box you are working
    if [[ -n $TARGET_NAME || -n $RHOST ]]; then
        seg+="${TARGET_NAME:-?}${RHOST:+ $RHOST}"
    fi

    # the identity you are holding
    [[ -n $U ]] && seg+="${DOMAIN:+${DOMAIN}/}${U}"

    # the cloud identity you are holding — same class of mistake as the wrong box
    [[ -n $AWS_PROFILE ]] && seg+="aws:${AWS_PROFILE}"

    # transport
    if [[ -n $_rt_vpn_iface ]]; then
        seg+="$_rt_vpn_iface"
    elif [[ -n $RHOST ]]; then
        seg+="%F{red}no vpn${dim}"
    fi

    # the ledger — only shown when it is NOT recording, i.e. when it is a surprise
    [[ -n $RT_CMDLOG_OFF ]] && seg+="%F{214}log off${dim}"

    if (( ${#seg} )); then
        RPROMPT="${dim}${(j: · :)seg}%f"
    else
        RPROMPT=""
    fi
}

add-zsh-hook precmd _rt_context_bar
