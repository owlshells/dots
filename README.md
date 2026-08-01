# dots

The design rule is that this layer should **work without being invoked**. A
shorter name for a command is a second vocabulary to memorise and it buys
nothing; the shell knowing which box you are on, refusing to fire at something
out of scope, and completing from what you actually ran last time buys a lot.
So the helpers here are either scaffolding that does real work, or ambient
behaviour you never type.

> For authorized engagements, CTFs, and lab work only.

## Install

```bash
git clone git@github.com:owlshells/dots.git ~/dots
~/dots/install.sh          # symlinks ~/.bash_aliases and ~/.tmux.conf (backs up originals)
exec zsh
```

Optional:

```bash
~/dots/tools/install-tools.sh      # the CLI tools referenced here
~/dots/tools/backfill-index.sh     # seed recall from command logs you already have
~/dots/tools/selftest.zsh          # logic checks; no network or engagement needed
~/dots/tools/install-test.sh       # install.sh against a throwaway $HOME
~/dots/tools/scrub-logs.sh         # retro-redact secrets from logs already on disk
```

**bash** hooks in through `~/.bash_aliases`; **zsh** appends one guarded
`source` line to `~/.zshrc`. Kali keeps its prompt, completion, syntax
highlighting and autosuggestions — this loads after them and delegates to them.
The shared modules run in either shell; **the ambient layer is zsh-only**.

## The ambient layer

Nothing below is a command you run.

### The context bar

The right prompt carries whatever is loaded, and is empty when nothing is:

```
~/ops/boxy/scans            boxy 10.10.11.42 · corp.local/svc_sql · aws:stonepass · tun0
```

Target, credentials, AWS profile, VPN interface, and the ledger state. It is
uniformly dim on purpose — colour appears only when something wants attention
(tunnel down, logging paused), so a coloured prompt always means something.

### The scope guard

Every address on the line is checked before the line runs. Out of scope, or
private and unroutable with no tunnel up, and the first Enter warns instead of
executing:

```
❯ nmap -p- 10.10.99.7
out of scope: 10.10.99.7   (~/ops/boxy/scope.txt)
press enter again to run anyway
```

Pressing Enter again on the unchanged line runs it. `target` seeds `scope.txt`
with the box you named, so the guard arms itself; widen it with
`scope add 10.10.11.0/24`. **With no scope file the guard is inert and silent** —
it never speaks until it has something to enforce, and it ignores public
addresses unless your scope actually reaches into that space, so ordinary
traffic to mirrors and DNS never cries wolf.

Hostnames are checked too, against the names harvested from your own scans (see
below) — so `nmap dc01.corp.local` is judged on the address that name resolves
to, with no DNS lookup on the keypress. A name the index has never seen is not
checked at all, which is what makes it impossible for this to invent a warning.

An entry in `scope.txt` that is not an address or a CIDR cannot be enforced, and
it is reported as its own thing rather than being allowed to condemn traffic:

```
⋯ scope.txt: 1 unusable entry, ignored: boxy.htb
  not an address or cidr — resolve it, then: scope add <ip|cidr>
```

Once per edit of the file, above the prompt, and it never blocks a command. A
hostname there used to make *every* address read as out of scope, which meant
`target boxy.htb` produced a guard that cried wolf on the box you had just
loaded. `target` now resolves a name before seeding, and writes no entry at all
if it does not resolve — an inert guard is honest, an unmatchable entry is not.

### Recall — `^X^R`

The preexec ledger has always recorded every command with its timestamp and
directory. Now it is read back. `^X^R` searches all of it, and the preview shows
the commands **either side** of the hit — the approach you took, not one line:

```
  07-20 09:01  nmap -Pn -p- 10.10.11.42
▸ 07-20 09:02  nxc smb 10.10.11.42 -u guest -p ""
  07-20 09:03  impacket-GetNPUsers corp/:@10.10.11.10 -no-pass
```

The same ledger feeds zsh-autosuggestions, so ghost text completes from past
engagements rather than only this session.

Ranking never uses tool names — a denylist of "noise commands" is stale the day
you install something new. Entries are judged on shape (does it take arguments)
and place (was it run under `$OPS`), which holds for tools that do not exist
yet. `^A` in the picker drops the filter entirely.

### Credentials never reach the ledger

The ledger records every command, which means a password typed on the command
line would land in the box's `notes/commands.log` — and from there in the report
— and in the recall index, which would then offer it back as ghost text.
`cmdlog off` was the only defence, and an opt-in defence is one you forget
exactly when it matters.

So redaction happens **on write**, by default:

```
nxc smb 10.10.11.42 -u svc -p 'Passw0rd!'   ->  ... -u svc -p {{redacted}}
impacket-secretsdump corp/svc:Passw0rd@dc   ->  corp/svc:{{redacted}}@dc
smbclient //h/s -U 'CORP\svc%Passw0rd'      ->  -U 'CORP\svc%{{redacted}}'
AWS_SECRET_ACCESS_KEY=wJalrXUtn aws s3 ls   ->  AWS_SECRET_ACCESS_KEY={{redacted}}
```

The mark is `{{redacted}}` so a recalled command reads as a template with a hole
in it, matching arsenal-ng's grammar — and unlike `<redacted>` it stays inert if
you run it by accident.

Over-redaction is treated as its own failure, because a ledger that eats your
`nmap` port lists is one you switch off, and that leaks everything. So values
are judged by shape: `nmap -Pn -p-`, `-p 445,139` and `-p 1-65535` are port
specs and survive; `-p ''` is a null session and survives; `-H 10.10.11.42` is
smbmap's *host* and survives while `-H <32 hex>` is a hash and does not.

Bare `-p` is only treated as a password for commands whose `-p` really is one
(`nxc`, `sshpass`, `smbmap`, `hydra`, `impacket-*`, …) — real logs had
`sudo mkdir -p /opt/x` being redacted. The unambiguous long forms
(`--password`, `--pass`) are always honoured, as are `user:pass@host`,
`user%pass` and secret-named assignments.

Known misses, by design: a purely numeric password is indistinguishable from a
port, `mysql -p<pass>` from a flag bundle, and an unlisted tool's bare `-p`
from anything else. `RT_REDACT=0` disables the whole thing.

Some rules are not about command lines at all. A dumped hash table, a Responder
capture, a roasted ticket — these are *output*, and they reach disk through tmux
pane logging rather than through argv. Each keeps the half that is the finding
and masks only the crackable half:

| Shape | Kept | Masked |
|---|---|---|
| `Administrator:500:<lm>:<nt>:::` | account, RID | both hashes |
| `svc::CORP:<challenge>:<response>` | account, domain | the rest |
| `$krb5tgs$` `$krb5asrep$` `$krb5pa$` `$DCC2$` | principal, realm | the hash runs |
| `krbtgt:aes256-cts-hmac-sha1-96:<key>` | principal, etype | the key |
| `* Password : hunter2` | the label, and `(null)` | the value |
| `-----BEGIN … PRIVATE KEY-----` | the markers | every body line |

Which accounts you dumped, which principals you roasted and which etypes exist
are all things you write up; the material hashcat wants is not.

An IPv6 address has the same field shape as a NetNTLM hash — a name, `::`, then
hex groups — so that rule additionally requires a 32-character hex run, which an
IPv6 group (four characters at most) cannot produce. `ping6 fe80::215:5dff:fe00:1`
survives untouched, and the suite asserts it.

The private key block is the one rule the live path does not have: `redact.zsh`
is handed a single command line and cannot know it is inside a block. The scrub
path does it, preserving the line count while it does, because `scrub-logs.sh`
rejoins prefixes to bodies by line number.

Anything already logged before this existed:

```bash
tools/scrub-logs.sh --dry-run    # then without, to rewrite in place
```

It keeps a `.prescrub` copy of every file it changes, refuses to write if a
rewrite would alter a line without redacting it, and leaves every untouched
line byte-identical. It covers the recall index, every box's
`notes/commands.log`, the daily global logs, **and the tmux pane transcripts** —
which are the least protected logs on the box, since the ledger has been
redacted on write since this landed and those never were.

### Completion that follows your scans

Hostnames are harvested out of nmap output as it lands — the report line, http
redirects, TLS commonName and SANs, `smb-os-discovery` — and published through
zsh's standard hosts source. `ssh`, `scp`, `ping`, `curl` and friends pick them
up with no per-tool configuration. When a scan finds names `/etc/hosts` lacks,
one line says so and hands you the `addhost` command.

Two completers are added by hand, for tools that ship none:

- **netexec** — protocols and the common flags.
- **impacket** — the `domain/user:password@target` grammar every script shares,
  assembled from `$DOMAIN`/`$U`/`$P`/`$RHOST`. One TAB instead of retyping the
  most fat-fingered string in AD work.

awscli needs nothing; Kali's package already ships `_aws`.

### The command library — `^X^S`

`^X^S` opens [arsenal-ng](https://github.com/halilkirazkaya/arsenal-ng), Kali's
packaged command library: 2830 cheats across 238 files including a whole
impacket tree,
`{{placeholder}}` templating with defaults (`{{lport|4444}}`), a persistent
variable store, and command injection straight into the terminal.

This replaced a hand-written `snippets/*.txt` corpus that lived in this repo.
It used the same `{{placeholder}}` grammar with a third of the content, and
maintaining it meant maintaining a worse copy of something that arrives through
`apt`. The old snippets are in git history if they are ever wanted.

**Its variables are seeded from your session.** `^X^S` writes
`~/.config/arsenal-ng/variables.json` before launching, so `target 10.10.11.42
boxy` means every `{{target}}` across 2830 cheats is already filled:

| session | arsenal |
|---|---|
| `$RHOST`  | `{{target}}`, `{{target_ip}}` |
| `$DOMAIN` | `{{domain}}` |
| `$U`      | `{{username}}`, `{{user}}` |
| `$DC`     | `{{dc_ip}}` |
| `$LHOST`  | `{{lhost}}` |

`$P` is deliberately **not** written. Everything else there is context; a
password is a credential, and persisting it to a file that outlives the session
is the habit the redaction work exists to break. Opt in with
`RT_ARSENAL_SYNC_PASSWORD=1`. The store is merged rather than overwritten, so
variables you set inside the TUI survive, and it is written `0600`.

Install it with `sudo apt install arsenal-ng`; both deploy scripts now include
it. `^X^S` says so if it is missing.

Keybinds all live under `^X`: `^X^R` recall, `^X^S` command library, `^X^P`
payload paths. (`^P` and space are already claimed by Kali's config.)

## Commands that do real work

```bash
lhost                    # your attack IP (prefers tun0) -> $LHOST
target 10.10.11.42 boxy  # $RHOST, ~/ops/boxy/{scans,loot,...}, scope.txt, cd
scan                     # staged nmap (all ports -> service scan) into ./scans
fuzz http://boxy/FUZZ    # ffuf with a sane default wordlist
serve 8000               # HTTP server in cwd, prints the http://LHOST:port url
smbserve share .         # impacket SMB share
listen 4444              # reverse-shell catcher (penelope > rlwrap nc > nc)
addhost 10.10.11.42 boxy.htb
scope / scope add        # what the guard enforces
note "creds in config.php"     # timestamped line into the box's notes
b64 / ub64 / urlenc      # encoders
mythic start|status      # drive mythic-cli from anywhere
cmdlog / cmdlog off      # ledger status; pause before typing a password
payload smb              # fzf SecLists/PayloadsAllTheThings with preview
denv                     # direnv .envrc template for per-engagement creds
```

`target` creates a per-box tree under `$OPS` (default `~/ops`). `~/ops` and
`*.log` are gitignored, so loot and evidence are never committed.

The helpers that end by handing off to a tool (`scan`, `fuzz`, `serve`,
`smbserve`, `listen`) honour `RT_DRYRUN=1`, which prints the argv they would run
instead of running it — one word per line. That is how the suite asserts them
without scanning anything, and it is useful by hand when you want the command
rather than the effect:

```bash
RT_DRYRUN=1 scan 10.10.11.42     # both nmap stages, as they would be invoked
```

## Layout

| Path | What |
|------|------|
| `shell/zshrc`, `shell/bash_aliases` | loaders |
| `shell/exports.sh`   | history, PATH, `$WORDLISTS`/`$SECLISTS`, `$OPS` |
| `shell/aliases.sh`   | `ports`, `myip`, `vpnip`, clipboard, listing |
| `shell/functions.sh` | the workflow helpers above |
| `shell/zsh.sh`       | `payload`, `cmdlog`, `denv` |
| `shell/zsh/context.zsh`  | the context bar |
| `shell/zsh/guard.zsh`    | scope + VPN interlock, `scope` |
| `shell/zsh/recall.zsh`   | ledger index, `^X^R`, ghost-text strategy |
| `shell/zsh/hosts.zsh`    | host harvesting, `_nxc`, impacket completion |
| `shell/zsh/redact.zsh`   | keeps credentials out of the ledger, on write |
| `shell/zsh/pickers.zsh`  | `^X^S` arsenal-ng, `^X^P` payload paths |
| `bin/`               | `addhost`, and the renderers fzf shells out to |
| `tmux/tmux.conf`     | `C-a` prefix, per-pane logging, tun0 in the status bar |
| `tools/`             | installers, Mythic bootstrap, backfill, the two test suites |

## tmux

`prefix + P` (prefix is `C-a`) toggles per-pane logging to `~/ops/tmux-logs/` —
a transcript of screen output, distinct from the command ledger.

Because it is output rather than argv, on-write redaction does not cover it: a
`secretsdump` table lands there in cleartext. `tools/scrub-logs.sh` now scrubs
these transcripts retroactively, and that is the path to trust. `prefix + R`
additionally toggles a live filter through `bin/rt-redact` for logging started
after it — opt-in, because most of the argv-shaped rules cannot fire on screen
output. It lowers exposure; it does not remove it.

## Uninstall

```bash
rm ~/.bash_aliases ~/.tmux.conf      # restore from ~/.dotfiles-backup/ if needed
# zsh: delete the block between the "red-team dotfiles" markers in ~/.zshrc
```
