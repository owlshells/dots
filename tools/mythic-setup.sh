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
#   Uncommon agent > default = less signatured.
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

# 2. Docker — pick Mythic's bundled installer matching the distro (works on a
# cloud Ubuntu/Debian box or on local Kali).
if ! command -v docker >/dev/null; then
    distro_id="$(. /etc/os-release 2>/dev/null && echo "${ID:-}")"
    case "$distro_id" in
        kali)          installer=./install_docker_kali.sh ;;
        ubuntu)        installer=./install_docker_ubuntu.sh ;;
        debian|*)      installer=./install_docker_debian.sh ;;
    esac
    say "installing Docker via ${installer} (sudo)"
    [ -f "$installer" ] || die "$installer not found in $MYTHIC_DIR"
    sudo "$installer" || die "docker install failed"
fi

# Ensure the daemon is up (systemd on most cloud instances; WSL2 has none, so
# fall back to service, then a raw dockerd).
if ! sudo docker info >/dev/null 2>&1; then
    say "starting docker daemon"
    sudo systemctl start docker 2>/dev/null \
        || sudo service docker start 2>/dev/null \
        || sudo dockerd >/tmp/dockerd.log 2>&1 &
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
# By default Mythic exposes nginx (the login) on 0.0.0.0. On a cloud teamserver
# that puts your C2 login on a public IP; locally (with a VPN/tun up) it reaches
# the target network. Agents call back on the C2 *profile* port, not this one,
# so localhost-only costs nothing operationally. Reach the UI via:
#   - cloud: SSH tunnel   ssh -L 7443:127.0.0.1:7443 user@teamserver
#   - WSL2:  the Windows browser hits https://127.0.0.1:7443 directly
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
            remote box? tunnel it:  ssh -L 7443:127.0.0.1:7443 user@<teamserver>
  user:     mythic_admin
  password: $(sudo grep -E '^MYTHIC_ADMIN_PASSWORD=' "$ENVF" 2>/dev/null | cut -d= -f2- || echo '(mythic creds)')

  -> copy the password into your manager now if you want a backup; .env (0600)
     is the source of truth and `mythic creds` reads it on demand.

  status:   sudo ./mythic-cli status      (or: mythic status  — see the shell helper)
  stop:     sudo ./mythic-cli stop
  agent:    $AGENT   profile: $PROFILE
EOF
