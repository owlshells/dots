# terminal

The terminal's look, as opposed to the shell's behaviour.

`install.sh` deploys this to **kitty**, which is the only terminal it targets:
kitty reads a background image from its own config file, so the whole thing
stays inside Linux, and it is what the deploy scripts install on a desktop Kali
box. A headless box has no kitty and the step skips itself, which is the common
case. `--no-terminal` skips it on a box that has kitty and does not want it.

    ./install.sh                        # slate
    DOTS_OWL_TINT=ash ./install.sh      # bone, ash, slate, char, or #rrggbb

What that does:

- generates `~/.local/share/dots/owl-<tint>.png` from the mask
- writes `~/.local/share/dots/kitty-owl.conf` beside it
- appends a marker-guarded `include` to `~/.config/kitty/kitty.conf`

The picture is generated per-machine and kept **outside the checkout**. Writing
it into `terminal/` would mean every install dirtied the working tree. The
fragment is generated rather than tracked-and-symlinked because kitty does not
expand `~` or `$HOME` in `background_image` — the path has to be absolute, and
only install time knows it.

Needs Pillow (`apt install python3-pil`); without it the step skips with a note
rather than failing the install.

Fading is `background_tint 0.75` — kitty blends the background colour over the
image, so higher is fainter. That is the knob equivalent to an opacity slider.

## The owl

`owl-mask.png` is an alpha mask cut from a Japanese woodblock print: *Kobushi ni
mimizuku* ("horned owl on a magnolia"), Library of Congress control number
[2008660938](https://www.loc.gov/item/2008660938/), call number FP 2 - JPD no.
2028, digital id `jpd.02375`. A **surimono** — privately commissioned for a
poetry circle — so the two columns of calligraphy are *kyōka*, signed 春調亭
(Shunchōtei) and 浅春庵 (Sesshun'an). The print itself is catalogued 無款,
unsigned, so those are the poets and not the artist. Neither LOC nor
Nichibunken's catalogue transcribes the verse.

Public domain: pre-1915 Japanese print, and LOC records no known restrictions.

The paper is gone because a *local* background model removed it — one global
paper colour is not enough on a sheet that has aged unevenly, and a brightness
threshold does not work at all here, since the owl's body is a pale cream within
a few levels of the paper behind it. Max-filtering a downscaled copy estimates
the paper level per region; subtracting that leaves the ink.

Regenerate at any tint:

    ./mkowl.py --tint slate -o owl-slate.png

## Windows Terminal — manual, and staying that way

The WSL box is driven through Windows Terminal, which is a Windows application
configured by a Windows file. `install.sh` deliberately does not touch it: a
Linux installer reaching across `/mnt/c` to rewrite a Windows app's config is
the wrong thing for this repo to do, and it would be dead weight on every real
Kali box. Use `mkowl.py` to produce the image and set this up by hand.

`settings.json` lives at

    %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json

and is not tracked anywhere. The relevant part of the profile:

    "backgroundImage": "C:\\Users\\<you>\\Pictures\\owl-slate.png",
    "backgroundImageOpacity": 0.25,
    "backgroundImageStretchMode": "uniform",
    "backgroundImageAlignment": "center",
    "colorScheme": "Neowave Mocha"

with the scheme's `background` at `#282828` and `selectionBackground` at
`#3f3f3f`.

### Two things that will waste your afternoon

**Windows Terminal caches `backgroundImage` by path.** Overwrite the file in
place and the old picture keeps rendering, in new tabs and new windows. Every
change needs a **new filename** and the `backgroundImage` line updated to match.
`backgroundImageOpacity` is *not* cached and applies on save — so a picture that
ignores you while its opacity obeys you is this bug, not a failed write.

**Profile objects contain a `guid` whose value has literal `{}`.** Pulling a
profile out of the raw JSON by brace matching lands inside the GUID string. Edit
that file line-based, and assert the parsed `guid` survives the round trip.

## Contrast

The prompt colours in `../shell/zsh/prompt.zsh` are tuned against `#282828`.
Moving the background costs every foreground some contrast — when it moved off
the old `#1b1526`, dim grey 242 fell to 2.81:1 and had to go to 245. If you
change the background again, re-check the dim first: it is the weakest element
and it carries the context bar, the host hints and the error parens.
