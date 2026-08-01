# ~/dots/shell/zsh/redact.zsh — keep secrets out of the ledger.
#
# The preexec hook records every command line verbatim, which means
# `nxc ... -p 'Passw0rd!'` and `impacket-secretsdump corp/svc:pw@dc` land on
# disk in cleartext -- in the box's notes/commands.log, which goes into the
# report, and in the recall index, which now offers them back as ghost text.
#
# `cmdlog off` was the only mitigation and it is opt-in, so it gets forgotten
# exactly when it matters. This redacts on the way in: the secret is never
# written, rather than written and later hidden.
#
# Set RT_REDACT=0 to disable. Redaction is deliberately the default.
#
# The mark is {{redacted}} -- the same placeholder grammar as snippets and
# arsenal-ng, so a recalled command reads as a template with a hole in it, and
# it stays inert if you run it by accident (`<redacted>` would be a redirect).

: ${RT_REDACT:=1}
: ${RT_REDACT_MARK:='{{redacted}}'}

# `-p` is the problem child: password in netexec, make-parents in mkdir,
# preserve in cp, port in nmap and psql. Real logs showed `sudo mkdir -p /opt/x`
# being redacted, and a ledger that mangles every mkdir is one you switch off --
# which leaks everything. So the ambiguous SHORT flags are only honoured for
# commands whose short -p really is a password; the LONG forms are unambiguous
# and always are.
#
# Accepted cost: an unlisted tool using bare -p for a password is missed. The
# long-form, user:pass@host, user%pass and NAME=secret rules still cover it,
# and adding a tool here is a one-line change.
typeset -ga _RT_PW_FLAGS_SHORT=(-p -P)
typeset -ga _RT_PW_FLAGS_LONG=(--password --pass --passwd --pw)
typeset -ga _RT_PW_TOOLS=(
    nxc netexec crackmapexec cme smbmap sshpass evil-winrm
    hydra medusa mongo mongosh mysql mysqldump
)
typeset -ga _RT_WRAPPERS=(sudo doas proxychains proxychains4 env time watch nohup stdbuf)
typeset -ga _RT_HASH_FLAGS=(-H --hash -hashes --hashes -nthash --nt-hash --ntlm-hash)
typeset -ga _RT_USER_FLAGS=(-U --user --username)
typeset -g  _RT_SECRET_NAME='(P|PW|PASS|PASSWD|PASSWORD|TOKEN|SECRET|APIKEY|API_KEY|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|GITHUB_TOKEN|DOTS_TOKEN)'

# Work word-by-word rather than with one big pattern. Shell-word splitting is
# what removes the whole class of false positives that a regex has to special-
# case: `nmap -Pn` and `-p-` are single words that simply are not the flag, so
# they can never be mistaken for one carrying a value. It also sidesteps glob
# backtracking, which quietly ate one quote of `-p ''` and left the other.
#
# Trade-off, accepted: runs of whitespace inside the command collapse to single
# spaces in the log. The command stays functionally identical and readable.
#
# Known misses, accepted: a purely numeric password is indistinguishable from a
# port list, and mysql's separator-less -p<pass> is indistinguishable from a
# flag bundle.
# -H is a hash in netexec but the HOST in smbmap. Judge the value, not the
# flag: an NTLM hash is >=16 hex characters (32, or 65 as LM:NT); an address or
# a hostname is not. Same principle as the port-list rule above.
_rt_is_hash_value() {
    local v=${1//[\'\"]/}; v=${v//:/}
    [[ ${#v} -ge 16 && $v == [0-9a-fA-F]## ]]
}

_rt_is_secret_value() {
    local v=$1
    [[ -z $v ]]           && return 1     # nothing there
    [[ $v == "''" ]]      && return 1     # `-p ''` is a null session, not a secret
    [[ $v == '""' ]]      && return 1
    return 0
}

# All-digits is only ambiguous after a SHORT flag, where -p might be nmap's port
# list. After --password, or in PASSWORD=, there is no such ambiguity and the
# value is a password whatever it looks like -- so this check is applied only on
# the short-flag path. Applying it everywhere wrote numeric passwords, PINs and
# all-digit tokens to the ledger in cleartext, which is the exact outcome this
# file exists to prevent.
_rt_is_port_list() {
    setopt local_options extended_glob
    [[ $1 == [0-9,-]## ]]
}

# Sets REPLY rather than printing: this runs from preexec on every command, and
# capturing stdout would mean a fork per command. _rt_redact below is the
# printing wrapper, for testing and for anything not on the hot path.
#
# Mirrored in bin/rt-redact for the scrub path; tools/selftest.zsh asserts the
# two agree on a shared corpus.
_rt_redact_r() {
    typeset -g REPLY=$1
    (( RT_REDACT )) || return
    setopt local_options extended_glob
    local m=$RT_REDACT_MARK
    local -a words out
    words=( ${(z)1} ) || return

    # Declared local so the (#b) backreference substitution below does not
    # create them globally and clobber whatever the operator had in $match.
    local -a match mbegin mend
    # The effective command, with wrappers and leading VAR=val peeled off, so
    # `sudo proxychains nxc ...` is still recognised as nxc.
    local cmd="" pw_short=0 w prev="" name val q
    for w in $words; do
        [[ $w == *=* ]] && continue
        (( ${_RT_WRAPPERS[(I)${w:t}]} )) && continue
        cmd=${w:t}; break
    done
    if (( ${_RT_PW_TOOLS[(I)$cmd]} )) || [[ $cmd == impacket-* ]]; then pw_short=1; fi

    for w in $words; do
        # 1. value following a secret-bearing flag
        if [[ -n $prev ]] && _rt_is_secret_value "$w" \
           && { (( ${_RT_PW_FLAGS_LONG[(I)$prev]} )) \
                || { (( pw_short )) && (( ${_RT_PW_FLAGS_SHORT[(I)$prev]} )) \
                     && ! _rt_is_port_list "$w" } \
                || { (( ${_RT_HASH_FLAGS[(I)$prev]} )) && _rt_is_hash_value "$w" } }; then
            out+=( "$m" ); prev=$w; continue
        fi
        # 2. --password=secret, and NAME=secret where the name says secret
        if [[ $w == *=* ]]; then
            name=${w%%=*}; val=${w#*=}
            if _rt_is_secret_value "$val" \
               && { (( ${_RT_PW_FLAGS_LONG[(I)$name]} + ${_RT_HASH_FLAGS[(I)$name]} )) \
                    || { (( pw_short )) && (( ${_RT_PW_FLAGS_SHORT[(I)$name]} )) \
                         && ! _rt_is_port_list "$val" } }; then
                out+=( "${name}=${m}" ); prev=$w; continue
            fi
            if [[ $name == (#i)${~_RT_SECRET_NAME} ]] && _rt_is_secret_value "$val"; then
                out+=( "${name}=${m}" ); prev=$w; continue
            fi
        fi
        # 3. samba-style user%password -- smbclient, rpcclient, smbmap, net
        if { [[ -n $prev ]] && (( ${_RT_USER_FLAGS[(I)$prev]} )) && [[ $w == *%* ]] } \
           || [[ $w == -U?*%* ]]; then                 # -U user%pw and -Uuser%pw
            q=""; [[ $w == (\'*\'|\"*\") ]] && q=${w[-1]}   # keep the closing quote
            out+=( "${w%%\%*}%$m$q" ); prev=$w; continue
        fi
        # 4. domain/user:secret@target -- impacket specs and credentialed URLs
        #
        # The secret span must not cross whitespace. A credential spec is one
        # unbroken token, but a quoted argument is also a single shell word, so
        # without this a colon and an @ anywhere in ordinary prose matched and
        # everything between them was replaced:
        #   git commit -m "fix: mention user@example.com"
        #     -> git commit -m "fix:{{redacted}}@example.com"
        # which destroys content in a ledger that ends up in the report. This is
        # also what bin/rt-redact already did, so the two now agree.
        if [[ $w == *:*@* ]]; then
            out+=( "${w//(#b)(:)([^:@[:space:]]##)(@)/$match[1]$m$match[3]}" ); prev=$w; continue
        fi
        # 5. pwdump format -- user:rid:lmhash:nthash:::
        #
        # The only rule here that is not about a command line. secretsdump, the
        # SAM/NTDS dump and hashdump all emit this, and it reaches disk through
        # tmux pane logging, which captures screen output rather than argv. The
        # account name and RID are kept on purpose: which accounts you dumped is
        # the finding you write up, and only the hashes are the secret.
        if [[ $w == (#b)([^:[:space:]]##):(<->):([0-9a-fA-F](#c16,)):([0-9a-fA-F](#c16,))(*) ]]; then
            out+=( "$match[1]:$match[2]:$m:$m$match[5]" ); prev=$w; continue
        fi
        out+=( "$w" ); prev=$w
    done
    # Only hand back the rebuilt line if something was actually redacted.
    # Rebuilding collapses runs of whitespace, and for a multi-line jq program
    # that reflows code for no benefit -- so an untouched command stays byte-
    # exact, and only a line that had a secret in it gets normalised.
    local rebuilt="${(j: :)out}"
    [[ $rebuilt == *${m}* ]] && REPLY=$rebuilt
}

# Printing wrapper — tests, the scrub path, and anything off the hot path.
_rt_redact() {
    local REPLY
    _rt_redact_r "$1"
    print -r -- "$REPLY"
}
