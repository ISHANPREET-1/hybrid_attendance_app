# Deploying to AWS or GCP

One small Ubuntu VM runs everything: the Python backend (systemd service), the Flutter web app, an SQLite database on disk, and **Caddy**, which provides automatic HTTPS. With no domain of your own, the script uses a free `<ip>.sslip.io` address, which Let's Encrypt can certify.

Suitable for a class-size deployment (hundreds of users). For larger or multi-server deployments, use a managed PostgreSQL (`DATABASE_URL`) instead of SQLite.

## 1. Create the VM

**AWS (EC2):** Launch instance → Ubuntu Server 24.04 LTS → `t3.micro` (free tier) or `t3.small` → create/download a key pair (`.pem`) → Network settings: allow **SSH (22)**, **HTTP (80)**, **HTTPS (443)** from anywhere → 20 GB disk → Launch. Optionally attach an **Elastic IP** so the address never changes.

**GCP (Compute Engine):** Create instance → `e2-small` (or `e2-micro` free tier) → Boot disk Ubuntu 24.04 LTS, 20 GB → Firewall: tick **Allow HTTP** and **Allow HTTPS** → Create. Optionally reserve a **static external IP**.

## 2. Package the project on the Windows laptop

```powershell
$env:Path = "D:\flutter\bin;$env:Path"; cd D:\hybrid_app
flutter build web --no-web-resources-cdn
tar -czf D:\hybrid_deploy.tgz --exclude=.tools --exclude=.dart_tool --exclude=android --exclude=ios --exclude=windows --exclude=linux --exclude=macos --exclude=backend/data --exclude=.env.local -C D:\hybrid_app .
```

## 3. Upload and run the setup

**AWS:**
```powershell
scp -i C:\path\to\key.pem D:\hybrid_deploy.tgz ubuntu@<VM-IP>:~
ssh -i C:\path\to\key.pem ubuntu@<VM-IP>
```
**GCP:** open the VM's **SSH** button in the console, then ⚙ → **Upload file** → `D:\hybrid_deploy.tgz`.

Then, on the VM:
```bash
mkdir -p ~/app && tar -xzf ~/hybrid_deploy.tgz -C ~/app && cd ~/app && sudo bash deploy/setup_vm.sh
```

The script prints the **App URL**, the **admin setup link** and the **setup token**. Open `https://<ip-with-dashes>.sslip.io/#/setup` and create the administrator.

## 4. Point the Android app at it

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://<ip-with-dashes>.sslip.io
```
The APK is `build\app\outputs\flutter-apk\app-release.apk`. Existing installs can also use **Configure server** on the sign-in screen.

Point the CSI service at it too: `BACKEND_URL=https://<ip-with-dashes>.sslip.io` in `csi\.env`.

## Operations

| Task | Command (on the VM) |
|---|---|
| Live logs | `sudo journalctl -u hybrid-attendance -f` |
| Restart | `sudo systemctl restart hybrid-attendance` |
| Health | `curl https://<domain>/api/health` |
| Backup DB | `sudo sqlite3 /opt/hybrid_attendance/backend/data/attendance.sqlite3 ".backup ~/backup.sqlite3"` |
| Register CSI sensor | `cd /opt/hybrid_attendance && sudo -u hybrid .venv/bin/python -m backend.manage create-sensor --name "ESP32 Room 101" --room "Room 101"` |
| Update the app | upload a new `hybrid_deploy.tgz`, extract to `~/app`, run `sudo bash deploy/setup_vm.sh` again (database and secrets are kept) |

Settings live in `/opt/hybrid_attendance/.env.local` (restart after editing). `TRUST_PROXY=true` makes the backend use the real client IP from Caddy. `AUTH_IP_LIMIT=1000` allows a whole class behind one campus NAT address to sign in.
