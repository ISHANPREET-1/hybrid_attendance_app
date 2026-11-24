#!/usr/bin/env bash
# One-shot production setup for an Ubuntu 22.04/24.04 VM (AWS EC2 or GCP Compute Engine).
#   - Python backend as a systemd service (auto-start on boot, auto-restart on crash)
#   - Caddy reverse proxy with automatic HTTPS (Let's Encrypt)
#   - SQLite database on the VM disk (backend/data/attendance.sqlite3)
#
# Usage, from inside the uploaded project folder (it must contain build/web):
#   sudo bash deploy/setup_vm.sh                 # uses <public-ip>.sslip.io as the domain
#   sudo bash deploy/setup_vm.sh attend.example.com   # or your own domain (DNS A record -> VM IP)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
SRC="$(cd "$(dirname "$0")/.." && pwd)"
APP=/opt/hybrid_attendance
[ -f "$SRC/build/web/index.html" ] || { echo "build/web missing. On your laptop run: flutter build web --no-web-resources-cdn, then upload again."; exit 1; }

IP="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')"
DOMAIN="${1:-${IP//./-}.sslip.io}"
echo "Public IP: $IP   Domain: https://$DOMAIN"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-venv python3-pip rsync sqlite3 debian-keyring debian-archive-keyring apt-transport-https curl gpg
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y && apt-get install -y caddy
fi

id hybrid >/dev/null 2>&1 || useradd --system --home "$APP" --shell /usr/sbin/nologin hybrid
mkdir -p "$APP"
# Keep the existing database and secrets on re-deploys.
rsync -a --delete --exclude backend/data --exclude .env.local --exclude .tools --exclude .venv \
  --exclude android --exclude ios --exclude windows --exclude linux --exclude macos --exclude .dart_tool \
  "$SRC/" "$APP/"
mkdir -p "$APP/backend/data"
python3 -m venv "$APP/.venv"
"$APP/.venv/bin/pip" install --quiet --upgrade pip
"$APP/.venv/bin/pip" install --quiet -r "$APP/requirements.txt"

if [ ! -f "$APP/.env.local" ]; then
  TOKEN="$(python3 -c 'import secrets;print(secrets.token_urlsafe(32))')"
  cat > "$APP/.env.local" <<ENV
APP_ORIGIN=https://$DOMAIN
COOKIE_SECURE=true
TRUST_PROXY=true
AUTH_IP_LIMIT=1000
ADMIN_SETUP_TOKEN=$TOKEN
ATTENDANCE_SSID=ATTENDANCE_WIFI
CSI_MAX_AGE_S=30
ENV
fi
sed -i "s#^APP_ORIGIN=.*#APP_ORIGIN=https://$DOMAIN#" "$APP/.env.local"
chown -R hybrid:hybrid "$APP"
chmod 600 "$APP/.env.local"

cat > /etc/systemd/system/hybrid-attendance.service <<UNIT
[Unit]
Description=Hybrid Attendance backend
After=network-online.target
Wants=network-online.target

[Service]
User=hybrid
WorkingDirectory=$APP
ExecStart=$APP/.venv/bin/python backend/server.py --port 8080
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
	encode gzip
	reverse_proxy 127.0.0.1:8080
}
CADDY

systemctl daemon-reload
systemctl enable --now hybrid-attendance
systemctl restart hybrid-attendance caddy
sleep 4
echo
if curl -fsS "https://$DOMAIN/api/health" ; then echo; echo "HTTPS OK"; else
  echo "HTTPS not ready yet. Check that ports 80 and 443 are open in the cloud firewall, then: sudo systemctl restart caddy"; fi
echo
echo "App URL:          https://$DOMAIN"
echo "Admin setup:      https://$DOMAIN/#/setup"
echo "Setup token:      $(grep ^ADMIN_SETUP_TOKEN "$APP/.env.local" | cut -d= -f2)"
echo "Logs:             sudo journalctl -u hybrid-attendance -f"
echo "Backup database:  sudo sqlite3 $APP/backend/data/attendance.sqlite3 \".backup /home/\$SUDO_USER/attendance-backup.sqlite3\""
