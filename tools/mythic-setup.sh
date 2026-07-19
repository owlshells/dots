#!/usr/bin/env bash
# mythic-setup.sh — stand up Mythic C2 (Docker) end to end.
#
# Authorized red-team engagements only.
# Run as your normal user; it calls sudo for the privileged bits.
#
# Usage: mythic-setup.sh [agent] [profile]
#   defaults: agent=thanatos (Rust, Windows+Linux), profile=http
#   why not apollo: apollo (C#) is the most common Mythic agent, so it's the
#   most signatured. Rust/C agents are far less represented in vendor rules.
#   other maintained, uncommon options (pass as arg 1):
#     xenon      C,    Windows        (freshest — updated 2026)
#     kharon     C++,  Windows        (PIC, heavier feature set)
#     poseidon   Go,   Linux/macOS
#     medusa     Python, cross-plat
#   See `cht c2`. Uncommon agent > default = less signatured.
set -uo pipefail

MYTHIC_DIR="${MYTHIC_DIR:-$HOME/opt/Mythic}"
AGENT="${1:-thanatos}"
PROFILE="${2:-http}"

say() { printf '\n\033[1;36m[*]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[-]\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Clone if missing
if [ ! -d "$MYTHIC_DIR/.git" ]; then
    say "cloning Mythic -> $MYTHIC_DIR"
    mkdir -p "$(dirname "$MYTHIC_DIR")"
    git clone --depth 1 --single-branch https://github.com/its-a-feature/Mythic.git "$MYTHIC_DIR" \
        || die "clone failed"
fi
cd "$MYTHIC_DIR" || die "cannot cd $MYTHIC_DIR"

# 2. Docker (use Mythic's bundled Kali installer if docker is absent)
if ! command -v docker >/dev/null; then
    say "installing Docker via Mythic's bundled Kali installer (sudo)"
    [ -f ./install_docker_kali.sh ] || die "install_docker_kali.sh not found"
    sudo ./install_docker_kali.sh || die "docker install failed"
fi

# WSL2 has no systemd by default — make sure the daemon is up
if ! sudo docker info >/dev/null 2>&1; then
    say "starting docker daemon"
    sudo service docker start 2>/dev/null || sudo dockerd >/tmp/dockerd.log 2>&1 &
    sleep 5
    sudo docker info >/dev/null 2>&1 || die "docker daemon not reachable (check /tmp/dockerd.log)"
fi

# 3. Build mythic-cli
if [ ! -x ./mythic-cli ]; then
    say "building mythic-cli (sudo make)"
    sudo make || die "make failed"
fi

# 4. Install agent + C2 profile (idempotent-ish; re-install is harmless)
say "installing agent: $AGENT"
sudo ./mythic-cli install github "https://github.com/MythicAgents/$AGENT"   || die "agent install failed"
say "installing C2 profile: $PROFILE"
sudo ./mythic-cli install github "https://github.com/MythicC2Profiles/$PROFILE" || die "profile install failed"

# 4b. Seed the admin password from YOUR input — never hardcoded in the repo.
#   Source, in priority order:
#     1. $MYTHIC_ADMIN_PW  (pipe from your manager, e.g.
#        MYTHIC_ADMIN_PW="$(bw get password mythic)" mythic-setup.sh)
#     2. interactive secure prompt (paste from your manager)
#     3. neither -> let Mythic generate a random one (read later with `mythic creds`)
# Only applies to a FRESH install: Mythic sets the admin password when the
# account is first created, so seeding an already-initialised instance is a
# no-op (rotate those in the UI: Settings -> your operator -> change password).
ENVF="$MYTHIC_DIR/.env"
seed_pw=""
if [ -n "${MYTHIC_ADMIN_PW:-}" ]; then
    seed_pw="$MYTHIC_ADMIN_PW"
elif [ -t 0 ]; then
    read -rsp "Mythic admin password (paste from your manager; blank = auto-generate): " seed_pw; echo
fi

if [ -n "$seed_pw" ]; then
    # .env values are double-quoted; a literal " in the password would break
    # parsing. Reject it rather than corrupt the file.
    case "$seed_pw" in *'"'*) die 'password contains a double-quote (") — Mythic .env cannot store it; pick one without it';; esac
    # Make sure .env exists first (agent install above usually creates it; if not,
    # a config read generates defaults without starting anything).
    sudo test -f "$ENVF" || sudo ./mythic-cli config get DEBUG_LEVEL >/dev/null 2>&1 || true
    if sudo test -f "$ENVF"; then
        # printf is a shell builtin, so the password never appears in `ps`/argv.
        { sudo grep -v '^MYTHIC_ADMIN_PASSWORD=' "$ENVF"; printf 'MYTHIC_ADMIN_PASSWORD="%s"\n' "$seed_pw"; } \
            | sudo tee "$ENVF.tmp" >/dev/null && sudo mv "$ENVF.tmp" "$ENVF"
        say "admin password seeded into .env from your input (nothing written to the repo)"
    else
        say "warn: .env not present yet — Mythic will generate a random password at start"
        seed_pw=""
    fi
fi

# 5. Start
say "starting Mythic"
sudo ./mythic-cli start || die "start failed"

# 5b. If we seeded, the account is now created with your password — strip the
# plaintext from .env so it doesn't linger on disk (your manager is the source
# of truth). If auto-generated, leave it so you can read it once, then delete.
if [ -n "$seed_pw" ]; then
    { sudo grep -v '^MYTHIC_ADMIN_PASSWORD=' "$ENVF"; } | sudo tee "$ENVF.tmp" >/dev/null && sudo mv "$ENVF.tmp" "$ENVF"
    say "seeded password removed from .env (retrieve it from your manager)"
fi

# 6. Report creds
say "Mythic is up"
if [ -n "$seed_pw" ]; then
    _pwline="password: (the one you supplied — from your manager)"
else
    _pwline="password: $(sudo grep -E '^MYTHIC_ADMIN_PASSWORD=' "$ENVF" 2>/dev/null | cut -d= -f2- || echo '(see '"$ENVF"' : MYTHIC_ADMIN_PASSWORD)')"
fi
cat <<EOF

  UI:       https://127.0.0.1:7443   (self-signed cert — expect a warning)
  user:     mythic_admin
  $_pwline

  status:   sudo ./mythic-cli status      (or: mythic status  — see the shell helper)
  stop:     sudo ./mythic-cli stop
  agent:    $AGENT   profile: $PROFILE
EOF
