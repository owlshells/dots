# Reverse shells & upgrades — quick reference

> `revshell [port] [type]` prints these with your LHOST filled in.
> `listen [port]` catches them (pwncat-cs > rlwrap nc > nc).
> `upgrade-shell` prints the TTY upgrade sequence.

## Catch
```bash
listen 4444                 # or: rlwrap nc -lvnp 4444
```

## Upgrade a dumb shell to a full TTY
```bash
python3 -c 'import pty;pty.spawn("/bin/bash")'   # or: script -qc /bin/bash /dev/null
# Ctrl-Z
stty raw -echo; fg
export TERM=xterm-256color; stty rows 50 cols 200
```

## Stabilise Windows shells
- Prefer `evil-winrm` or a C2 agent over a raw `nc` shell.
- ConPTY upgrade: use `ConPtyShell` / a Meterpreter-less agent for a real TTY.

## When the obvious ones are filtered
- Try each transport in turn: `revshell 4444 all` and paste whichever the box can run.
- Egress-filtered? Point the shell at 443/53 and listen there (`listen 443`).
- No interpreters? Static `nc`/`busybox`, or write a socket in whatever *is* installed.
