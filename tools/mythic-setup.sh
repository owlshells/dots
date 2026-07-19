#!/usr/bin/env bash
# mythic-setup.sh — stand up Mythic C2 (Docker) end to end.
#
# Authorized red-team engagements only.
# Run as your normal user; it calls sudo for the privileged bits.
#
# Usage: mythic-setup.sh [agent] [profile]
#   defaults: agent=apollo (Windows C#), profile=http
#   alternatives worth a look: poseidon (linux/mac), athena (cross-plat .NET),
#   medusa (python). See `cht c2`. Uncommon agent > default = less signatured.
set -uo pipefail

MYTHIC_DIR="${MYTHIC_DIR:-$HOME/opt/Mythic}"
AGENT="${1:-apollo}"
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

# 5. Start
say "starting Mythic"
sudo ./mythic-cli start || die "start failed"

# 6. Report creds
say "Mythic is up"
cat <<EOF

  UI:       https://127.0.0.1:7443   (self-signed cert — expect a warning)
  user:     mythic_admin
  password: $(sudo grep -E '^MYTHIC_ADMIN_PASSWORD=' .env 2>/dev/null | cut -d= -f2- || echo '(see '"$MYTHIC_DIR"'/.env : MYTHIC_ADMIN_PASSWORD)')

  status:   sudo ./mythic-cli status      (or: mythic status  — see the shell helper)
  stop:     sudo ./mythic-cli stop
  agent:    $AGENT   profile: $PROFILE
EOF
