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
b64 / ub64 / urlenc      # quick encoders
note "found creds in config.php"   # timestamped line into the target's notes
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
