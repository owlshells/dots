# dotfiles

Red-team / pentest shell setup for Kali. Modular, symlink-based, and
non-destructive — it hooks in through `~/.bash_aliases` (which Kali's stock
`.bashrc` already sources), so nothing in Kali's managed configs is touched and
uninstalling is just removing two symlinks.

> For authorized engagements, CTFs, and lab work only.

## Install

```bash
git clone git@github.com:0w15h3115/dotfiles.git ~/dotfiles
~/dotfiles/install.sh          # symlinks ~/.bash_aliases and ~/.tmux.conf (backs up originals)
source ~/.bashrc
```

Optional — install the CLI tools referenced here that aren't already present:

```bash
~/dotfiles/tools/install-tools.sh
```

## Layout

| Path | What |
|------|------|
| `shell/bash_aliases` | Loader — symlinked to `~/.bash_aliases`, sources the rest |
| `shell/exports.sh`   | History, PATH, `$WORDLISTS`/`$SECLISTS`, `$OPS` |
| `shell/aliases.sh`   | `ports`, `myip`, `vpnip`, clipboard, listing, tool shortcuts |
| `shell/functions.sh` | Engagement workflow helpers (below) |
| `shell/ad.sh`        | Active Directory helpers (netexec/impacket) |
| `cheatsheets/`       | AD, pivoting, reverse-shells, C2 — via `cht <name>` |
| `bin/addhost`        | Add/update an `/etc/hosts` entry |
| `tmux/tmux.conf`     | `C-a` prefix, per-pane logging, `tun0` in status bar |
| `tools/install-tools.sh` | Optional installer for missing tooling |

## Workflow helpers

```bash
lhost                    # your attack IP (prefers tun0) -> $LHOST
target 10.10.11.42 boxy  # sets $RHOST, scaffolds ~/ops/boxy/{scans,loot,...}, cds in
scan                     # staged nmap (all ports -> service scan) into ./scans
fuzz http://boxy/FUZZ    # ffuf with a sane default wordlist
serve 8000               # HTTP server in cwd, prints the http://LHOST:port url
smbserve share .         # impacket SMB share
listen 4444              # reverse-shell catcher (pwncat-cs > rlwrap nc > nc)
revshell 4444 bash       # print a reverse-shell one-liner for $LHOST (or: all)
upgrade-shell            # print the TTY-upgrade sequence
addhost 10.10.11.42 boxy.htb
dl payload.exe win       # print a download one-liner for $LHOST (linux/win)
tunnel                   # ligolo-ng / chisel pivot recipes with $LHOST filled in
crack kerb.hash kerb     # hashcat by name (ntlm|asrep|kerb|net-ntlmv2|sha512crypt)
cht active-directory     # open a cheatsheet (no arg = list them)
b64 / ub64 / urlenc      # quick encoders
note "found creds in config.php"   # timestamped line into the target's notes
```

### Active Directory (`shell/ad.sh`)

```bash
export DOMAIN=corp.local DC=10.10.11.10 U=user P='pass'   # adset shows current
nxc-null $DC             # null/guest SMB enum
nxc-spray $DC users.txt 'Spring2026!'   # one password, lockout-aware
asrep $DC $DOMAIN users.txt   # AS-REP roast -> hashcat -m 18200
kerberoast               # SPN roast (needs creds) -> hashcat -m 13100
bhpy                     # BloodHound collection -> zip
secretsdump $RHOST       # dump secrets with creds
```

`target` creates a per-box tree under `$OPS` (default `~/ops`). `~/ops` and
`*.log` are gitignored so loot and evidence never get committed.

## tmux logging

`prefix + P` (prefix is `C-a`) toggles per-pane logging to
`~/ops/tmux-logs/` — a running transcript of everything in that pane, useful
for engagement notes and reporting.

## Uninstall

```bash
rm ~/.bash_aliases ~/.tmux.conf      # restore backups from ~/.dotfiles-backup/ if needed
```
