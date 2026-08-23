# lock

The lock screen is betterlockscreen wrapping i3lock-color, with the ring
replaced by a password box that shakes when the password is wrong.

```
                                             ╭────────────────╮
   09:41                                     │  ● ● ● ● ●     │
   locked                                    ╰────────────────╯
```

## Why there is a patch here at all

The ring is the only indicator i3lock-color has. `--no-unlock-indicator` gets
rid of it, but that flag is not a styling switch — from `i3lock(1)`:

> Disable the unlock indicator. i3lock will by default show an unlock indicator
> after pressing keys. **This will give feedback for every keypress and it will
> show you the current PAM state** (whether your password is currently being
> verified or whether it is wrong).

Both halves of that sentence go together. In the source, the ring, the keypress
highlight, and the `checking` / `no` strings are all inside one
`if (unlock_indicator && …)`, and the redraw on a failed password is behind the
same flag again. Turning the circle off left a lock screen that either went
away or did not, and said nothing either way.

`--bar-indicator` is upstream's other option and keeps the feedback, but it is
an audio-visualiser bar, not a field you type into.

So: `box-indicator.patch`, which adds a third indicator alongside the ring and
the bar.

## What the patch adds

A rounded rectangle at `--ind-pos`, holding one dot per byte of input, drawn
whether or not anything has been typed yet — a login field that only appears
once you are already typing is not much of an affordance. Border and fill come
from the existing `--ring-color` and `--inside-color` families, so a palette
written for the ring carries over with nothing to restyle, and it still tracks
the three PAM states: idle, verifying, wrong.

On a wrong password the box shakes: a sine damped by a decaying exponential,
horizontal only, ~0.45s. Every other redraw in i3lock is event driven and
nothing fires during that window, so the shake runs its own 60fps `ev` timer
that starts on the failure and stops itself when the animation ends. An idle
lock screen redraws exactly as often as it did before.

New flags, all documented in the patched `i3lock(1)`:

    --box-indicator            --shake-amplitude=px
    --box-width=px             --shake-frequency=hz
    --box-height=px            --shake-duration=seconds   (0 disables the shake)
    --box-radius=px
    --box-border-width=px
    --box-dot-radius=px
    --box-dot-gap=px
    --box-dot-color=rrggbbaa

## Building

```bash
./build.sh          # --keep leaves the build tree for inspection
```

Clones i3lock-color at the pinned tag, applies the patch, and installs to
`/usr/local/bin/i3lock`, which precedes `/usr/bin` on `PATH`. The distro package
is left alone and still owned by dpkg — this adds a binary rather than replacing
one, and `sudo rm /usr/local/bin/i3lock` is the entire uninstall.

`make install` is deliberately not used: upstream's install target also writes a
systemd unit and a `pam.d` file, and the packaged copies of both already work.
Overwriting a working PAM config from a hand-built tree is how you get locked
out of your own machine.

## The thing to remember

**An i3lock-color upgrade from the archive does not rebuild this.** The patched
binary in `/usr/local/bin` keeps shadowing the new one, so a security fix
upstream will sit there unused. Re-run `build.sh` after an upgrade; it pins
`UPSTREAM_TAG`, so bump that too.

That is the standing cost of the fork, and it is worth being honest that it is a
real one — this is the program that stands between a walk-away and the session.

## Failure modes

Deliberately arranged so the worst case is ugly rather than open:

- **rc linked, patched binary missing** — i3lock rejects the unknown flag,
  betterlockscreen fails with it, and `owl-lock`'s `|| exec i3lock` fallback
  locks the screen with the stock grey one. `install.sh` warns when it sees
  this.
- **the cache is missing** — same fallback; this is why `owl-lock` exists at
  all, since `betterlockscreen -l` fails *and leaves the screen unlocked*.
- **out of memory when starting the shake** — the box stops shaking and
  everything else carries on. The draw path allocates nothing, and no path here
  calls `exit()`, because for a screen locker exiting *is* unlocking.

## Files

| | |
|---|---|
| `box-indicator.patch` | the fork, against i3lock-color `2.13.c.5` |
| `build.sh` | fetch, patch, build, install |
| `betterlockscreenrc` | the styling; symlinked to `~/.config/betterlockscreen/` by `install.sh` |
