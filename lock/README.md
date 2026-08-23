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

## The rate limit

After `--lockout-after` consecutive failures, every further attempt costs
`--lockout-delay` seconds before it is looked at, counted down on screen in
place of the wrong text. The box holds its wrong colour for the whole window
rather than resting after two seconds, because a box that looked ready while
still refusing input would be lying.

It is enforced in `finish_input()`, which is the single choke point for
submitting a password. That matters: pressing Return during the wrong-password
window does **not** go through the key handler's submit path — it sets
`retry_verification`, and `clear_auth_wrong` calls `finish_input()` itself two
seconds later. A gate in the key handler would have left that queued retry as a
way straight past the limit.

Two honest limits on what this buys:

- **It is friction, not an access control.** The counter lives in the running
  locker, so anyone who can power-cycle the machine gets a fresh one. What it
  stops is someone picking up an unattended laptop and working through a
  shortlist of guesses.
- **It is not `pam_faillock`, deliberately.** That locks the *account*, which on
  a laptop means locking yourself out of sudo and the TTYs at the same moment
  you are already shut out of the session. This touches no PAM state; the worst
  it can do is make you wait.

New flags, all documented in the patched `i3lock(1)`:

    --box-indicator            --shake-amplitude=px
    --box-width=px             --shake-frequency=hz
    --box-height=px            --shake-duration=seconds   (0 disables the shake)
    --box-radius=px
    --box-border-width=px      --lockout-after=n          (0 disables the limit)
    --box-dot-radius=px        --lockout-delay=seconds
    --box-dot-gap=px           --lockout-text=string
    --box-dot-color=rrggbbaa

## Building

```bash
./build.sh          # --keep leaves the build tree for inspection
                    # --wrapper-only installs owl-lock and stops
                    # --yes installs build deps without asking
```

This is the only thing that installs any part of the lock screen, and that is
deliberate. `kali-deploy-physical` used to write `owl-lock` and
`betterlockscreenrc` itself, which meant the rc path had two owners and a
re-deploy silently reverted whichever one had not run last. The deploy's dots
phase calls this script instead.

**`owl-lock` is installed first** — before the dependency check, before the
clone, before the compiler. It is five lines with no build requirements, and it
is the piece that decides whether a failed lock leaves the screen open; the
patched binary is the cosmetic half. So a box with no network, no compiler, or
an upstream tag that has moved still locks correctly, falling back to the stock
i3lock and its circle. That is why the deploy can call this without a build
failure costing anyone their lock screen.

It then clones i3lock-color at the pinned tag, applies the patch, and installs
to `/usr/local/bin/i3lock`, which precedes `/usr/bin` on `PATH`. The distro package
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
| `owl-lock` | the lock wrapper, installed to `/usr/local/bin` by `build.sh` |
