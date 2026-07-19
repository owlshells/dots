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

ENVF="$MYTHIC_DIR/.env"

# 4b. Bind the admin UI to localhost BEFORE first start.
# By default Mythic exposes nginx (the login) on 0.0.0.0 — with a VPN/tun up
# that reaches the target network. Agents call back on the C2 *profile* port,
# not this one, so localhost-only costs nothing operationally. WSL2 mirrors
# localhost, so the Windows browser still reaches https://127.0.0.1:7443.
say "binding admin UI to localhost (NGINX_BIND_LOCALHOST_ONLY=true)"
sudo test -f "$ENVF" || sudo ./mythic-cli config get DEBUG_LEVEL >/dev/null 2>&1 || true
sudo ./mythic-cli config set NGINX_BIND_LOCALHOST_ONLY true >/dev/null 2>&1 || true

# 5. Start — Mythic generates a random admin password into .env (the standard flow)
say "starting Mythic"
sudo ./mythic-cli start || die "start failed"

# 5b. Lock down .env: it holds live Postgres/RabbitMQ/JWT secrets in plaintext.
# Default perms can be world-readable; restrict to owner only.
sudo chmod 600 "$ENVF" 2>/dev/null || true

# 6. Report creds (read the password Mythic generated; retrieve later with `mythic creds`)
say "Mythic is up"
cat <<EOF

  UI:       https://127.0.0.1:7443   (self-signed cert — expect a warning; localhost only)
  user:     mythic_admin
  password: $(sudo grep -E '^MYTHIC_ADMIN_PASSWORD=' "$ENVF" 2>/dev/null | cut -d= -f2- || echo '(mythic creds)')

  -> copy the password into your manager now if you want a backup; .env (0600)
     is the source of truth and `mythic creds` reads it on demand.

  status:   sudo ./mythic-cli status      (or: mythic status  — see the shell helper)
  stop:     sudo ./mythic-cli stop
  agent:    $AGENT   profile: $PROFILE
EOF
