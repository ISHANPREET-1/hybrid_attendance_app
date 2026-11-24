# Hybrid Attendance

Flutter web and Android application with an authenticated Python backend. Students check in to real class sessions; teachers manage classes and rosters; administrators manage staff invitations, device approvals and CSI room sensors.

Attendance is decided by the backend from several verification layers: identity, registered device, optional rotating code, optional classroom Wi-Fi (Android app), optional **ESP32 CSI room presence**, and optional location or campus network. See [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) for the rules and API, and [docs/HARDWARE_SETUP.md](docs/HARDWARE_SETUP.md) for the router, ESP32 firmware and CSI pipeline.

## Implemented workflows

- **Accounts:** student registration, administrator-invited staff accounts, login, logout, profile editing, password changes, and administrator-issued one-time password reset tokens.
- **Security:** Argon2id password hashes, opaque sessions stored hashed in the database, HttpOnly cookies, Secure cookies on HTTPS/Vercel, CSRF checks, same-origin writes, persistent request throttling, server-enforced roles and course ownership, and audit activity.
- **Classes:** create/edit/archive, enroll or remove registered students by email. Administrators may manage all classes; teachers may manage only their own.
- **Sessions:** open now or schedule a future start in IST, set a duration, close/cancel, automatic activation/expiration, and a rotating classroom code. Overlapping sessions in the same course are rejected. The roster is copied when the session is created so later roster edits cannot rewrite reports.
- **Browser approvals:** a student requests approval for their current browser; an administrator approves, rejects or revokes it. Approving a new browser revokes the previous approval. The browser token is an HttpOnly cookie, not a user-entered device identifier.
- **Attendance:** the server derives the student from their login, requires roster membership and browser approval, verifies the live classroom code, enforces the session window, and prevents duplicate check-ins even under concurrent requests.
- **Location/network options:** a teacher can optionally require a geofence using their current location or classroom coordinates; the server checks distance and reported accuracy. If campus egress CIDRs are configured, the teacher can require the observed client IP to match the campus network.
- **Reports:** present/absent/pending/cancelled status, per-student/course percentages over completed sessions, search, and CSV download. Students see only their own records; teachers see only their own classes. Cancelled sessions do not count in percentages.
- **Hybrid verification (v3):** per session, a teacher can require the classroom Wi-Fi SSID (read by the Android app with location permission) and a live `PRESENT` reading from the room's ESP32 CSI sensor. Android phones register with a secure install UUID plus an ANDROID_ID-derived hash; one phone cannot belong to two students, and reinstalling or replacing a phone needs administrator re-approval. Check-ins return `VERIFIED`, `PENDING` (CSI unavailable, stale or uncertain; nothing recorded) or `REJECTED`, with a per-layer explanation. Every attempt is logged for teachers. CSI sensors post to `POST /api/csi/verification` with their own revocable bearer token. CSI is room-level occupancy and never identifies a student.
- **Announcements:** staff post to their classes; enrolled students see them. Dashboard figures, profiles, devices and reports refresh from the backend every ten seconds.

There are no shared default passwords, fake rosters, sample approvals, or browser-only attendance writes. Optional INITIAL_ADMIN_* settings create the first administrator once using your private credentials. The old prototype screens have been replaced by the authenticated portal.

## Run locally on Windows

Requires Python 3.12 and Flutter 3.35+ (the installed SDK in `.tools/flutter` is 3.47.9).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -Background
```

The launcher creates an isolated Python environment, installs backend dependencies when missing, builds Flutter, and starts both the frontend and API at **http://127.0.0.1:8080**. For an existing build, use `-SkipBuild -Background`.

- Backend stdout/stderr: `.tools/app.stdout.log`, `.tools/app.stderr.log`.
- Background PID: `.tools/app-process.pid`.
- Stop: `Stop-Process -Id (Get-Content .tools/app-process.pid)`.
- SQLite database: `backend/data/attendance.sqlite3`. Back it up to retain local records.

If a previous version is still running, stop it before launching the new backend.

## Easy administrator sign-in

Private deployment settings and generated initial administrator credentials are in `vercel/.env`. Fill its DATABASE_URL and add its values in Vercel project settings before deploying. The build creates the first administrator automatically when INITIAL_ADMIN_EMAIL and INITIAL_ADMIN_PASSWORD are provided. Existing accounts and passwords are never overwritten on redeploy.

Local sign-in: **http://127.0.0.1:8080/#/login**. Hosted sign-in: `https://YOUR-PROJECT.vercel.app/#/login`. The login ID is INITIAL_ADMIN_EMAIL; the password is INITIAL_ADMIN_PASSWORD. Internal first-admin ID: `initial-admin`. The local administrator has already been created from the private file. See `vercel/README.md`.

For a fresh local database: `.tools\venv\Scripts\python.exe -m backend.manage bootstrap-admin --env-file vercel/.env`. This reads only administrator settings from that file and keeps your normal local database and cookie settings.

Manual setup, when no administrator exists: **http://127.0.0.1:8080/#/setup** or `https://YOUR-PROJECT.vercel.app/#/setup`.

## Manual administrator setup and first attendance

1. Open the local app and choose **First administrator setup**.
2. Read the one-time setup secret from `.tools/setup-token.txt`. If `ADMIN_SETUP_TOKEN` is configured in `.env.local`, use that value instead. Keep this token private.
3. Enter your real name, email and a password of at least 12 characters. First setup cannot be repeated after the first administrator exists.
4. In **Administration**, invite a teacher using their email. Share the one-time token privately; the invitation expires in 48 hours and is bound to that email.
5. The teacher chooses **Create an account**, supplies the invitation, then signs in. The teacher creates a class.
6. A student registers with their email and roll number, then requests their browser approval in **Devices**.
7. An administrator verifies the student and approves the browser. The teacher verifies the student and enrolls that registered email in the class.
8. The teacher opens a session from **Sessions** and displays the current code in the classroom.
9. The student enters the code in **Sessions**. If a location check is required, clicking check-in requests browser location permission.
10. The teacher closes the session. Reports show attendees and absences; CSV export downloads the same authorized report.

Use separate browser profiles for administrator, teacher and student when testing simultaneously; tabs in one browser share the login cookie. Password-reset tokens are generated by an administrator and privately delivered to the account holder. No email service or outbound messages are assumed.

## Vercel deployment

The repository includes `vercel.json`, a pinned Flutter build script, `.python-version`, and `api/index.py`. The Python function uses the same backend as the local server. All `/api/*` calls stay on the frontend origin, so there is no cross-origin cookie setup or public API key.

1. Create a hosted PostgreSQL database and use its **pooled connection URL with TLS**. Local SQLite is deliberately rejected on Vercel.
2. Import this repository into your Vercel account. Choose the **Other** framework preset. The committed configuration supplies `bash scripts/build-web.sh` and output directory `build/web`.
3. Add environment variables in Vercel project settings before deploying:

| Variable | Value | Required |
| --- | --- | --- |
| `DATABASE_URL` | Hosted PostgreSQL pooled URL, e.g. `postgresql://USER:PASSWORD@HOST/DATABASE?sslmode=require` | Yes |
| `INITIAL_ADMIN_EMAIL` | Initial administrator login email from `vercel/.env` | For automatic first setup |
| `INITIAL_ADMIN_PASSWORD` | Generated private password from `vercel/.env` | For automatic first setup |
| `INITIAL_ADMIN_NAME` | Administrator display name | Optional |
| `ADMIN_SETUP_TOKEN` | A long random setup secret generated on your computer | Yes, for initial administrator setup |
| `APP_ORIGIN` | Exact HTTPS production origin, no trailing slash | Recommended for production; omit for preview deployments with changing URLs |
| `COOKIE_SECURE` | `true` | Automatic on Vercel; required on other HTTPS hosts |
| `CAMPUS_CIDRS` | Actual public campus egress CIDRs, comma separated | Optional; required only for campus-network checks |

Generate a setup token locally with `python -c "import secrets; print(secrets.token_urlsafe(32))"`. Store it directly in Vercel; do not commit it or share database credentials in chat.

4. Deploy. The build installs backend dependencies, applies the additive v2 schema, fetches the official pinned Flutter SDK and builds the web frontend. Provision separate database URLs for Preview and Production to keep their users and attendance separate.
5. Open `/api/health` and verify `status: ok`, `storage: postgresql`, `version: 2`.
6. Sign in at `/#/login` using the INITIAL_ADMIN_EMAIL and INITIAL_ADMIN_PASSWORD you configured. If automatic setup was omitted, use `/#/setup` with ADMIN_SETUP_TOKEN instead. Then invite real teachers and enroll real students.
7. Run the complete first-attendance workflow above on the deployment. Hosted PostgreSQL and actual Vercel routing must be verified against your own deployment; no cloud account or credentials are included in this repository.

`API_BASE_URL` is unnecessary for this same-origin deployment. `DATABASE_URL`, passwords and setup secrets are backend values and are never embedded in Flutter. Changing backend environment variables requires a new deployment. Do not point `API_BASE_URL` at localhost on Vercel.

Official references: [Python file-based functions](https://vercel.com/docs/functions/runtimes/python/api-directory), [Vercel configuration](https://vercel.com/docs/project-configuration/vercel-json), [environment variables](https://vercel.com/docs/environment-variables).

## Local environment and database tools

Copy `.env.example` to `.env.local` for optional local configuration. It is loaded by the backend and excluded from Git and deployment bundles. Existing process variables override the file.

```powershell
.tools\venv\Scripts\python.exe -m backend.manage migrate
.tools\venv\Scripts\python.exe -m backend.manage check
```

Both SQLite and PostgreSQL use SQLAlchemy's parameterized queries and shared schema. The v2 tables are versioned and additive. Original demo tables remain in the existing SQLite file; old unauthenticated attendance is not assigned automatically to new accounts because its identity and class-session ownership were never established. No legacy endpoint can write attendance without authentication.

## Browser and platform limits

Browser approval binds an account to an approved browser cookie, not to unchangeable physical hardware. The Android app adds an install UUID (Keystore-backed secure storage) and an ANDROID_ID-derived device hash, and reads the connected Wi-Fi SSID. These are stronger than a browser cookie but are still client-reported: a rooted phone can alter them. Classroom codes can be shared and reported location can be spoofed. CSI shows that *someone* is in the room, not who. Together the layers make proxy attendance much harder; none of them is hardware attestation on its own. Browsers cannot read the SSID, so sessions that require Wi-Fi must be checked in from the Android app.

Location needs HTTPS in deployment (localhost is allowed for local testing), user permission, and an accurate device location. Campus-network checks compare the server-observed public IP against administrator-configured campus egress CIDRs. Private Wi-Fi addresses do not identify campus users to a public Vercel host. On Vercel the backend uses the platform-controlled `x-real-ip`; the local server uses the socket peer IP and ignores spoofable proxy headers. See [Geolocation API](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation_API).

Android builds need `flutter build apk` and testing on the target Android versions: the SSID check needs fine-location permission and location services on (Android 10+), and minSdk is 24. Native login and device cookies are stored encrypted (flutter_secure_storage); cookies saved by earlier builds are migrated automatically. Automated email delivery, biometric identity and native hardware attestation are not included.

## Validation

```powershell
.tools\venv\Scripts\python.exe -m unittest backend.test_server backend.test_bootstrap backend.test_verification -v
cd csi; ..\.tools\venv\Scripts\python.exe -m unittest discover -s tests; cd ..   # needs csi\requirements.txt installed
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
```

Backend integration tests use temporary databases, real HTTP clients and separate cookie jars. They cover account invitations, role/ownership enforcement, student isolation, CSRF and origin rejection, approved browsers, rotating/expired codes, location and network checks, session scheduling and cancellation, concurrent duplicates, reports/CSV, profile/announcement writes, password resets/revocation and persistence after restart. Flutter tests cover authenticated state handling, error behavior, all role-specific pages on a phone, session management dialogs and hidden student management actions. PostgreSQL schema compilation can be checked without credentials, but a real hosted database and deployment must be tested with their configured connection.
