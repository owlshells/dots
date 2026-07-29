#!/bin/bash
# Exercise the owl hook on a real Kali, across all four paths it can take.
# /repo is the dots checkout, mounted read-only; we copy it so install.sh can
# chmod its own bin/ without writing through to the host.
set -uo pipefail

green() { echo -e "\033[0;32m  PASS\033[0m $*"; }
red()   { echo -e "\033[0;31m  FAIL\033[0m $*"; }
head_() { echo -e "\n\033[1;34m== $1\033[0m"; }
rc=0
ck() { if eval "$2"; then green "$1"; else red "$1"; rc=1; fi; }

cp -a /repo /dots && cd /dots

head_ "A: no kitty installed -> skips cleanly"
out=$(./install.sh 2>&1)
ck "install exits 0"                 "[ $? -eq 0 ]"
ck "says it skipped for no kitty"    "grep -q 'no kitty on this box' <<<\"\$out\""
ck "wrote no image"                  "[ ! -e \$HOME/.local/share/dots/owl-slate.png ]"

head_ "Installing kitty (no python3-pil yet)"
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends kitty >/dev/null 2>&1
ck "kitty present"                   "command -v kitty >/dev/null"
python3 -c 'import PIL' 2>/dev/null && echo "  (note: Pillow already pulled in as a kitty dep)"

head_ "B: kitty but no Pillow -> skips with the apt hint"
if python3 -c 'import PIL' 2>/dev/null; then
    echo "  skipped: kitty pulled Pillow in, cannot test this path here"
else
    out=$(./install.sh 2>&1)
    ck "names the package to install" "grep -q 'apt install python3-pil' <<<\"\$out\""
    ck "still wrote no image"         "[ ! -e \$HOME/.local/share/dots/owl-slate.png ]"
fi

head_ "Installing python3-pil"
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pil >/dev/null 2>&1
ck "Pillow importable"               "python3 -c 'import PIL'"

head_ "C: full deploy"
out=$(./install.sh 2>&1)
echo "$out" | grep -E 'owl' | sed 's/^/  > /'
ck "reports the hook"                "grep -q 'hook  owl (slate)' <<<\"\$out\""
ck "image generated"                 "[ -s \$HOME/.local/share/dots/owl-slate.png ]"
ck "fragment generated"              "[ -s \$HOME/.local/share/dots/kitty-owl.conf ]"
ck "include added to kitty.conf"     "grep -q 'kitty-owl.conf' \$HOME/.config/kitty/kitty.conf"
ck "absolute path in fragment"       "grep -qE '^background_image +/' \$HOME/.local/share/dots/kitty-owl.conf"
ck "image is a valid PNG"            "python3 -c \"from PIL import Image; Image.open('\$HOME/.local/share/dots/owl-slate.png').verify()\""
ck "nothing written into the repo"   "[ -z \"\$(cd /dots && git status --porcelain 2>/dev/null | grep -v '^ M install.sh')\" ]"

head_ "kitty parses what we wrote"
parsed=$(kitty +runpy "
from kitty.config import load_config
o = load_config('$HOME/.config/kitty/kitty.conf')
print('IMG', o.background_image[0] if o.background_image else None)
print('TINT', o.background_tint)
print('LAYOUT', o.background_image_layout)
" 2>&1 | grep -E '^(IMG|TINT|LAYOUT)')
echo "$parsed" | sed 's/^/  > /'
ck "background_image resolves"       "grep -q 'IMG /root/.local/share/dots/owl-slate.png' <<<\"\$parsed\""
ck "tint applied"                    "grep -q 'TINT 0.75' <<<\"\$parsed\""

head_ "D: second run is a no-op"
out=$(./install.sh 2>&1)
ck "reports already present"         "grep -q 'already present' <<<\"\$out\""
ck "include appears exactly once"    "[ \$(grep -c 'kitty-owl.conf' \$HOME/.config/kitty/kitty.conf) -eq 1 ]"

head_ "E: a custom tint"
out=$(DOTS_OWL_TINT='#FF2D2D' ./install.sh 2>&1)
ck "generated the custom tint"       "[ -s \"$HOME/.local/share/dots/owl-FF2D2D.png\" ]"
ck "no hash in the filename"         "[ ! -e \"$HOME/.local/share/dots/owl-#FF2D2D.png\" ]"

echo
[ $rc -eq 0 ] && echo -e "\033[0;32mALL PASSED\033[0m" || echo -e "\033[0;31mFAILURES\033[0m"
exit $rc
