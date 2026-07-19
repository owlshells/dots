#!/usr/bin/env bash
# install-tools.sh — install red-team CLI tools that aren't already present.
# Optional; run it yourself. Groups so you can comment out what you don't want.
set -uo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '\n\033[1;32m[*]\033[0m %s\n' "$*"; }

APT_PKGS=(
    rlwrap          # readline wrapper for nc listeners
    seclists        # wordlists
    fzf             # fuzzy finder
    ripgrep         # fast grep (rg)
    bat             # cat with syntax highlighting (batcat on Kali)
    jq              # json wrangling
    zoxide          # smarter cd
    responder       # LLMNR/NBT-NS poisoner
    feroxbuster     # content discovery
    proxychains4    # SOCKS chaining for pivots
    evil-winrm      # WinRM shell
    kerbrute        # pre-auth user enum / spray
    hashcat         # cracking (see `crack`)
    ligolo-ng       # tunneling (kali repo; else grab release binary)
    chisel          # tunneling fallback
    bloodhound      # AD graph (kali metapackage)
)

PIPX_PKGS=(
    pwncat-cs       # post-exploitation reverse-shell handler
)

GO_PKGS=(
    "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
)

say "apt packages"
missing=()
for p in "${APT_PKGS[@]}"; do have "${p/ripgrep/rg}" || missing+=("$p"); done
if [ "${#missing[@]}" -gt 0 ]; then
    sudo apt-get update -qq && sudo apt-get install -y "${missing[@]}"
else
    echo "all present"
fi

if have pipx || sudo apt-get install -y pipx; then
    say "pipx packages"
    for p in "${PIPX_PKGS[@]}"; do
        name="${p%%[><=]*}"
        have "$name" || pipx install "$p"
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
