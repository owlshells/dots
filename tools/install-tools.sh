#!/usr/bin/env bash
# install-tools.sh — install red-team CLI tools that aren't already present.
# Optional; run it yourself. Groups so you can comment out what you don't want.
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '\n\033[1;32m[*]\033[0m %s\n' "$*"; }

APT_PKGS=(
    rlwrap          # readline wrapper for nc listeners
    seclists        # wordlists
    fzf             # fuzzy finder (Ctrl-R history, `payload` lookup)
    direnv          # per-engagement .envrc auto-load (see `denv`)
    ripgrep         # fast grep (rg)
    bat             # cat with syntax highlighting (batcat on Kali)
    jq              # json wrangling
    zoxide          # smarter cd
    responder       # LLMNR/NBT-NS poisoner
    feroxbuster     # content discovery
    proxychains4    # SOCKS chaining for pivots
    evil-winrm      # WinRM shell
    python3-dev     # headers for pip builds (netifaces -> pwncat-cs)
    build-essential # C toolchain for the same
    hashcat         # cracking (see `crack`)
    ligolo-ng       # tunneling (kali repo; else grab release binary)
    chisel          # tunneling fallback
    bloodhound      # AD graph (kali metapackage)
)

# pkg|command — the installed command name differs from the package name.
PIPX_PKGS=(
    "penelope-shell-handler|penelope"   # maintained reverse-shell handler
)

GO_PKGS=(
    "github.com/ropnop/kerbrute@latest"                         # not in Kali apt
    "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
)

say "apt packages"
missing=()
for p in "${APT_PKGS[@]}"; do have "${p/ripgrep/rg}" || missing+=("$p"); done
if [ "${#missing[@]}" -gt 0 ]; then
    sudo apt-get update -qq
    # Filter to packages apt actually knows about — one unknown name would
    # otherwise abort the whole `apt-get install` and take everything with it.
    avail=(); skip=()
    for p in "${missing[@]}"; do
        if apt-cache show "$p" >/dev/null 2>&1; then avail+=("$p"); else skip+=("$p"); fi
    done
    [ "${#avail[@]}" -gt 0 ] && sudo apt-get install -y "${avail[@]}"
    [ "${#skip[@]}" -gt 0 ] && echo "not in apt (installed via go/pipx instead): ${skip[*]}"
else
    echo "all present"
fi

if have pipx || sudo apt-get install -y pipx; then
    say "pipx packages"
    for entry in "${PIPX_PKGS[@]}"; do
        pkg="${entry%%|*}"; cmd="${entry##*|}"   # split "pkg|command"
        have "$cmd" || pipx install "$pkg"
    done
fi

if have go; then
    say "go packages"
    for p in "${GO_PKGS[@]}"; do go install -v "$p"; done
    echo "ensure ~/go/bin is on PATH (exports.sh handles this)"
else
    echo "go not installed; skipping go tools (apt-get install -y golang-go)"
fi

say "done"
