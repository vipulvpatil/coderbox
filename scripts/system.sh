#!/usr/bin/env bash
# Machine setup for a coderbox. Run as root. Safe to re-run.
#
#   system.sh [path-to-tailscale-authkey-file]
#
# The auth key is only needed the first time (before the machine has joined
# your tailnet). The key file is deleted after use.
#
# Run this from cloud-init or over Tailscale, never over a public SSH
# connection: it closes every public port.

set -euo pipefail

USERNAME="${CODERBOX_USER:-coder}"
AUTHKEY_FILE="${1:-}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo $0)"
export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"   # amd64 or arm64
# On first boot, Ubuntu's own updates may hold the apt lock; wait instead of failing.
APT=(apt-get -o DPkg::Lock::Timeout=600)

log "Base packages"
"${APT[@]}" update -q
"${APT[@]}" install -yq ca-certificates curl gnupg sudo

log "User: $USERNAME"
if ! id "$USERNAME" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups sudo "$USERNAME"
fi
passwd --lock "$USERNAME" >/dev/null   # no password login, ever
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-coderbox
chmod 440 /etc/sudoers.d/90-coderbox
visudo -cf /etc/sudoers.d/90-coderbox >/dev/null

# Keep any SSH key the provider gave root, so plain SSH over Tailscale works too.
if [[ -f /root/.ssh/authorized_keys && ! -f /home/$USERNAME/.ssh/authorized_keys ]]; then
  install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.ssh"
  install -m 600 -o "$USERNAME" -g "$USERNAME" /root/.ssh/authorized_keys "/home/$USERNAME/.ssh/"
fi

log "Apt repositories (GitHub CLI, Caddy)"
install -d -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/caddy-stable.gpg
chmod go+r /etc/apt/keyrings/caddy-stable.gpg
echo "deb [signed-by=/etc/apt/keyrings/caddy-stable.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" \
  > /etc/apt/sources.list.d/caddy-stable.list

log "Packages"
"${APT[@]}" update -q
"${APT[@]}" install -yq git jq vim build-essential python3 ufw unattended-upgrades gh caddy

log "Tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! tailscale status >/dev/null 2>&1; then
  [[ -n "$AUTHKEY_FILE" && -s "$AUTHKEY_FILE" ]] \
    || die "not on a tailnet yet: pass a Tailscale auth key file as the first argument"
  tailscale up --authkey="$(tr -d '[:space:]' < "$AUTHKEY_FILE")" --ssh
fi
[[ -n "$AUTHKEY_FILE" && -f "$AUTHKEY_FILE" ]] && rm -f "$AUTHKEY_FILE"
TS_HOST="$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
[[ -n "$TS_HOST" && "$TS_HOST" != null ]] || die "could not read this machine's Tailscale name"

log "Firewall: Tailscale only, no public ports"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow in on tailscale0 >/dev/null
ufw delete allow OpenSSH >/dev/null 2>&1 || true
ufw --force enable >/dev/null

log "SSH: keys only, no root login"
# 10- sorts before the cloud image's 50-cloud-init.conf; sshd keeps the first value it reads.
cat > /etc/ssh/sshd_config.d/10-coderbox.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
# Ubuntu 24.04 starts sshd on demand (ssh.socket). Until the first connection,
# /run/sshd does not exist and ssh.service is not running: `sshd -t` needs the
# directory, and a plain `reload` would fail on the inactive service.
install -d -m 755 /run/sshd
sshd -t
systemctl try-reload-or-restart ssh

log "Go (latest stable)"
GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
if [[ "$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')" != "$GO_VERSION" ]]; then
  curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm /tmp/go.tar.gz
fi

log "code-server"
if ! command -v code-server >/dev/null; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi
# Only Caddy talks to code-server, so it listens on localhost and needs no
# password: being on your tailnet is the authentication.
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config" "/home/$USERNAME/.config/code-server"
cat > "/home/$USERNAME/.config/code-server/config.yaml" <<'EOF'
bind-addr: 127.0.0.1:8080
auth: none
cert: false
EOF
chown "$USERNAME:$USERNAME" "/home/$USERNAME/.config/code-server/config.yaml"
systemctl enable "code-server@$USERNAME" >/dev/null
systemctl restart "code-server@$USERNAME"

log "Caddy: HTTPS with a Tailscale certificate"
if ! grep -qs '^TS_PERMIT_CERT_UID=caddy' /etc/default/tailscaled; then
  echo 'TS_PERMIT_CERT_UID=caddy' >> /etc/default/tailscaled
  systemctl restart tailscaled
  sleep 3
fi
cat > /etc/caddy/Caddyfile <<EOF
$TS_HOST {
	reverse_proxy 127.0.0.1:8080
}
EOF
systemctl restart caddy

log "Done"
echo "code-server: https://$TS_HOST"
echo "Next: run scripts/user.sh as $USERNAME (cloud-init does this for you)."
