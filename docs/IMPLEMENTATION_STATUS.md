# Implementation status against the Complete Implementation Guide

Branch: `feature/csi-wifi-device-verification`. This document is the Phase evidence index (guide §15). It records what is implemented, how it was verified, and what still needs on-site execution.

## Architecture decision: keep the existing Python backend

The guide (§2.3, Phase 4) was written for an older demo-only version of this repository, and recommends building a Node.js/Express/Prisma backend. The repository already ships an authenticated **Python + SQLAlchemy** backend on SQLite (local) and PostgreSQL (hosted), with 13 integration tests. It covers accounts, Argon2id passwords, hashed opaque sessions, CSRF, roles, course ownership, roster snapshots, session scheduling, device approval, duplicate-proof attendance, reports and audit logs.

Rewriting that in Node would discard working, tested code. The guide itself says not to (§2.6 "Do not rewrite the application from scratch", §16.4). The guide's backend requirements (§7 Steps 17–25) are met in the existing stack:

| Guide asks for | Implemented as |
|---|---|
| Express routes/controllers/services | `backend/server.py` (HTTP + auth boundary), `backend/service.py` (workflows), `backend/verification.py` (verification layers) |
| PostgreSQL + Prisma schema/migrations | SQLAlchemy Core schema in `backend/database.py`. Versioned, additive tables (`*_v3`) are created by `python -m backend.manage migrate` on SQLite or PostgreSQL |
| JWT | Server-side opaque session tokens (hashed in the DB, HttpOnly cookie, 12 h expiry, CSRF token). These can be revoked instantly, which a JWT can't without a deny-list, and they meet the same requirement |
| Unique constraint against duplicate attendance | `UNIQUE(session_id, student_id)` on `attendance_v2`, plus a row lock on the session |

## Verification rules (guide Steps 24, 34, 35)

The backend makes the final decision (`Service.check_in`). Every attempt is stored in `attendance_checks_v3` with each layer's result, for teachers and audit.

| Layer | Pass | Fail → REJECTED | Pending → PENDING (nothing recorded) |
|---|---|---|---|
| Authentication | Valid session cookie (expired → 401) | | |
| Session | Open, inside its time window, student on the roster snapshot | Closed/expired/cancelled (409), not on roster | |
| Device | Approved device for this student. For Android: install UUID and device hash match the registered phone | Unapproved, revoked, other phone, app reinstalled (new UUID), identity missing or malformed | |
| Code (optional per session) | Current or previous 30 s rotating code | Wrong or expired code | |
| Location / campus network (optional, existing) | Within radius, or IP in `CAMPUS_CIDRS` | Outside, inaccurate, or wrong network | |
| Wi-Fi (optional per session) | Reported SSID equals the session SSID (default `ATTENDANCE_WIFI`) | Other SSID, unreadable SSID, permission denied, or browser (no SSID) | |
| CSI (optional per session) | Latest live reading for the class room is PRESENT and measured within `csi_max_age_s` (default 30 s) after the session started | ABSENT | No reading, stale, UNKNOWN, or replayed data |
| Duplicate | | | Returns the existing VERIFIED result. No second record |

Notes:
- **CSI is room-level only.** Readings are stored per room/sensor and never per student, and they only add to the per-student identity and device checks.
- The Wi-Fi SSID is reported by the app and can be spoofed on a rooted phone. It's a supporting check, as the guide says (§13.12). For a stronger network check, host the backend on the classroom LAN and use `CAMPUS_CIDRS` with the router's subnet.
- "CSI reports absence → reject or retry" (guide Step 35): this build **rejects** the attempt and the student can retry. The retry/exception policy should be agreed with the supervisor.

## Guide step map

| Guide | Status | Where |
|---|---|---|
| §2 Inspect & preserve app | Done. All existing workflows kept. Old code-only sessions behave as before (covered by tests) | `backend/test_server.py` (unchanged, passing) |
| Step 1–3 Router & ESP32 setup | Scripted and documented. **Needs to be done on site** | `docs/HARDWARE_SETUP.md` §1–2 |
| Step 4–9 Firmware | `firmware/setup_firmware.ps1` + `sdkconfig.attendance` overlay on pinned esp-csi `csi_recv_router`. Kconfig names checked against ESP-IDF v6.1.1 source. **Not compiled here** (Espressif registry/toolchain unreachable from the sandbox) | `firmware/` |
| Step 10 Continuous CSI check | `attendance_csi.check_serial`: rate, loss, resets, variation | `csi/attendance_csi/check_serial.py` |
| Step 11–12 Python env & collector | Reconnecting serial reader; parser for ESP32 and C5/C6 formats tested on real esp-csi output | `csi/attendance_csi/{io,parser}.py` |
| Step 13 Features | Amplitude, variation, short-window change, correlation, PCA energy; Hampel clip, median filter, normalisation | `features.py` |
| Step 14 Labelled dataset | `attendance_csi.record` with ground truth and setup metadata. **Needs recordings in the room** | `record.py` |
| Step 15 Model | Threshold baseline, LR, RF, SVM × window sizes, grouped-by-recording CV, full metrics, auto-selection | `train.py`, `models.py` |
| Step 16 Detection service | PRESENT/ABSENT/UNKNOWN, staleness, low-confidence and consensus rules, background posting, replay mode clearly tagged | `detector.py`, `service.py`, `run_service.ps1` |
| Step 17–18 Backend modules & schema | New tables: `session_policy_v3`, `device_identity_v3`, `csi_sensors_v3`, `csi_readings_v3`, `attendance_checks_v3` | `backend/database.py` |
| Step 19 Auth | Already present (see above) | |
| Step 20 Device registration/approval/history | Android identity binding; one phone per student; replacement through admin approval revokes the old device (history kept) | `service.py` `devices/*`, `verification.device_check` |
| Step 21 Class/session APIs | Already present, plus per-session verification policy | `sessions/open` |
| Step 22–23 CSI API & validation | `POST /api/csi/verification`, per-sensor bearer token (hashed), rate-limited, schema, timestamp, skew, staleness, session/room binding; revocable | `server.py`, `verification.ingest_reading` |
| Step 24–25 Integration & failures | Combined decision, PENDING on unavailable/stale/UNKNOWN, all attempts logged | `Service.check_in` |
| Step 26–33 Flutter | Android device identity (secure-storage UUID + ANDROID_ID hash), SSID via `network_info_plus` with permission handling, per-layer result dialog, teacher room-sensor status and attempt list, admin sensor management, Keystore-encrypted cookie storage with migration. **Not compiled here** (Flutter SDK download blocked) | `lib/` |
| Step 36 Integrity | DB unique constraint, session row lock, closed sessions refused, expired login refused, stale CSI refused, audit + attempt log | tests |
| Step 37 Flutter checks | **To run locally:** `flutter pub get && flutter analyze && flutter test && flutter build web` and `flutter build apk` | |
| Step 38–42 Testing | Backend + CSI automated tests below. Hardware, Android and multi-student tests need the classroom | |
| Step 43–47 Deployment & demo | Runbooks in `docs/HARDWARE_SETUP.md` §7–9 and README | |

## Automated verification run in this change

```
python -m unittest backend.test_server backend.test_bootstrap backend.test_verification   # 26 tests, OK
cd csi && python -m unittest discover -s tests                                            # 10 tests, OK
```

`backend/test_verification.py` covers the guide's Step 42 scenarios:
- Valid student/device/Wi-Fi/CSI → VERIFIED, and a duplicate → same result with no second record.
- Unregistered device, another phone, reinstalled app, malformed identity, one phone on two accounts → rejected. Admin-approved replacement works and revokes the old device. A device approved before the app sent identity goes back to admin review. A missing classroom code is a logged rejection.
- Wrong, unknown or permission-denied Wi-Fi → rejected.
- CSI missing, UNKNOWN or stale → PENDING. ABSENT → rejected. A late or stale reading never overrides a fresher one. Replayed data → PENDING.
- Sensor auth: no token, forged token or revoked token → 401. Bad status, timestamp, future time or confidence → 422. Wrong room → 403. Closed session → 409.
- Closed session check-in → rejected and logged. Teachers see attempts and room status.
- Old code-only/browser sessions unchanged.

`csi/tests/test_pipeline.py` covers parsing real Espressif ESP32 and C6 lines, malformed input, serial reconnection after unplug or busy port, feature behaviour, grouped training/evaluation and model saving, detector PRESENT/ABSENT/UNKNOWN (stale, too few packets), and **serial → detector → authenticated POST → real backend** end to end.

Synthetic CSI (`attendance_csi.simulate`) is used only for tests. Its perfect scores say nothing about a real room.

## What still has to be done on site

1. Router configuration (HARDWARE_SETUP §1). Firmware build and flash with ESP-IDF 6.1 (§3). Save the logs.
2. `check_serial` evidence (§4). Labelled recordings (§5). `train` report (§6), at increasing occupancy up to class size.
3. `flutter pub get && flutter analyze && flutter test && flutter build web && flutter build apk`. Install on Android phones and test the SSID and permission paths on the target Android versions.
4. End-to-end runs from the Step 42 table with real phones, including several students checking in at once. Then the Step 47 demonstration.

## API reference: new and changed endpoints

All student/teacher/admin endpoints keep the existing conventions: same-origin, `ha_session` cookie, `X-CSRF-Token` header, JSON. The sensor endpoint uses `Authorization: Bearer` and no cookies.

| Endpoint | Who | Purpose |
|---|---|---|
| `POST /api/csi/verification` | CSI service (bearer token) | Submit `{status, timestamp, confidence?, packets?, window_s?, error?, session_id?}` |
| `POST /api/csi/sensors` | admin | Register a sensor for a room; returns its token once |
| `POST /api/csi/sensors/revoke` | admin | Revoke a sensor token |
| `POST /api/sessions/open` | teacher/admin | New optional fields: `code_required` (default true), `wifi_required`, `wifi_ssid`, `csi_required`, `csi_max_age_s` (5–600) |
| `POST /api/devices/request` | student | New optional fields: `install_uuid`, `device_hash`, `platform`, `model` |
| `POST /api/attendance` | student | New optional fields: `install_uuid`, `device_hash`, `wifi_ssid`, `wifi_permission`. Returns `outcome` + `checks`. **202** = PENDING |
| `GET /api/state` | all | New keys: `checks` (attempts), `csi_rooms` (latest room state), `csi_sensors` (admin), `attendance_ssid`; sessions include their policy; devices include `platform`/`model` |

CLI: `python -m backend.manage create-sensor --name … --room …`, `list-sensors`, `revoke-sensor --id …`.

New environment variables (backend): `ATTENDANCE_SSID` (default `ATTENDANCE_WIFI`), `CSI_MAX_AGE_S` (default 30), `CSI_ALLOW_REPLAY` (demo only, default off).

### Request/response examples (captured from a live run of this build)

### Register a CSI sensor (administrator)

```json
{
  "POST": "/api/csi/sensors",
  "body": {
    "name": "ESP32 Room 101",
    "room": "Room 101"
  }
}
```

Response `200`:

```json
{
  "id": "<id>",
  "token": "<43-character token, shown once>",
  "message": "Put this token in the CSI service .env as CSI_SERVICE_TOKEN. It is shown only once."
}
```

### Register a phone (student, Android app)

```json
{
  "POST": "/api/devices/request",
  "body": {
    "label": "My phone",
    "install_uuid": "f536f99b-6bde-47d4-a42e-62bab1cbd568",
    "device_hash": "3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f",
    "platform": "android",
    "model": "Google Pixel 7"
  }
}
```

Response `200`:

```json
{
  "message": "Saved successfully"
}
```

### Open a session requiring Wi-Fi and CSI (teacher)

```json
{
  "POST": "/api/sessions/open",
  "body": {
    "course_id": "<course id>",
    "minutes": 50,
    "code_required": false,
    "wifi_required": true,
    "wifi_ssid": "ATTENDANCE_WIFI",
    "csi_required": true,
    "csi_max_age_s": 30
  }
}
```

Response `200`:

```json
{
  "message": "Saved successfully"
}
```

### Check-in before the room sensor has reported → PENDING

```json
{
  "POST": "/api/attendance",
  "body": {
    "session_id": "<session id>",
    "install_uuid": "f536f99b-6bde-47d4-a42e-62bab1cbd568",
    "device_hash": "3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f",
    "platform": "android",
    "model": "Google Pixel 7",
    "wifi_ssid": "\"ATTENDANCE_WIFI\"",
    "wifi_permission": "granted"
  }
}
```

Response `202`:

```json
{
  "message": "Room sensor has not reported yet. Try again shortly.",
  "outcome": "PENDING",
  "checks": [
    {
      "name": "identity",
      "status": "pass",
      "detail": "Signed in as s@college.test"
    },
    {
      "name": "session",
      "status": "pass",
      "detail": "OS101 session is active"
    },
    {
      "name": "device",
      "status": "pass",
      "detail": "Registered device verified"
    },
    {
      "name": "wifi",
      "status": "pass",
      "detail": "Connected to ATTENDANCE_WIFI"
    },
    {
      "name": "csi",
      "status": "pending",
      "detail": "Room sensor has not reported yet. Try again shortly."
    }
  ]
}
```

### CSI processing service posts a reading

```json
{
  "POST": "/api/csi/verification",
  "headers": {
    "Authorization": "Bearer <CSI_SERVICE_TOKEN>",
    "Content-Type": "application/json"
  },
  "body": {
    "status": "PRESENT",
    "timestamp": "2026-11-24T06:52:22+00:00",
    "confidence": 0.93,
    "packets": 297,
    "window_s": 3.0
  }
}
```

Response `200`:

```json
{
  "accepted": true,
  "id": "<id>",
  "room": "Room 101",
  "status": "PRESENT"
}
```

### Stale reading → 422 (logged, never used)

```json
{
  "POST": "/api/csi/verification",
  "body": {
    "status": "PRESENT",
    "timestamp": "2026-11-24T06:40:00+00:00",
    "confidence": 0.93,
    "packets": 297,
    "window_s": 3.0
  }
}
```

Response `422`:

```json
{
  "error": "Measurement is stale (older than 30 s); recorded but not usable"
}
```

### Missing or wrong sensor token → 401

```json
{
  "POST": "/api/csi/verification",
  "headers": {
    "Authorization": "Bearer forged"
  }
}
```

Response `401`:

```json
{
  "error": "Sensor token is invalid or revoked"
}
```

### Wrong Wi-Fi → REJECTED

```json
{
  "POST": "/api/attendance",
  "body": {
    "session_id": "<session id>",
    "install_uuid": "f536f99b-6bde-47d4-a42e-62bab1cbd568",
    "device_hash": "3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f",
    "platform": "android",
    "model": "Google Pixel 7",
    "wifi_ssid": "Home-5G",
    "wifi_permission": "granted"
  }
}
```

Response `403`:

```json
{
  "outcome": "REJECTED",
  "checks": [
    {
      "name": "identity",
      "status": "pass",
      "detail": "Signed in as s@college.test"
    },
    {
      "name": "session",
      "status": "pass",
      "detail": "OS101 session is active"
    },
    {
      "name": "device",
      "status": "pass",
      "detail": "Registered device verified"
    },
    {
      "name": "wifi",
      "status": "fail",
      "detail": "Connected to \"Home-5G\", not ATTENDANCE_WIFI."
    },
    {
      "name": "csi",
      "status": "pass",
      "detail": "Room presence verified"
    }
  ],
  "error": "Connected to \"Home-5G\", not ATTENDANCE_WIFI."
}
```

### All layers pass → VERIFIED

```json
{
  "POST": "/api/attendance",
  "body": {
    "session_id": "<session id>",
    "install_uuid": "f536f99b-6bde-47d4-a42e-62bab1cbd568",
    "device_hash": "3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f",
    "platform": "android",
    "model": "Google Pixel 7",
    "wifi_ssid": "\"ATTENDANCE_WIFI\"",
    "wifi_permission": "granted"
  }
}
```

Response `200`:

```json
{
  "message": "Attendance recorded",
  "outcome": "VERIFIED",
  "checks": [
    {
      "name": "identity",
      "status": "pass",
      "detail": "Signed in as s@college.test"
    },
    {
      "name": "session",
      "status": "pass",
      "detail": "OS101 session is active"
    },
    {
      "name": "device",
      "status": "pass",
      "detail": "Registered device verified"
    },
    {
      "name": "wifi",
      "status": "pass",
      "detail": "Connected to ATTENDANCE_WIFI"
    },
    {
      "name": "csi",
      "status": "pass",
      "detail": "Room presence verified"
    }
  ]
}
```

### Duplicate request → existing result, no second record

```json
{
  "POST": "/api/attendance",
  "body": {
    "session_id": "<session id>",
    "install_uuid": "f536f99b-6bde-47d4-a42e-62bab1cbd568",
    "device_hash": "3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f3f",
    "platform": "android",
    "model": "Google Pixel 7",
    "wifi_ssid": "\"ATTENDANCE_WIFI\"",
    "wifi_permission": "granted"
  }
}
```

Response `200`:

```json
{
  "message": "Attendance was already recorded for this session",
  "outcome": "VERIFIED",
  "duplicate": true,
  "checks": "[...]",
  "recorded_at": 1795503142.992297
}
```
