# Hybrid Attendance

A Flutter attendance app with student profiles, a sample class schedule, attendance recording, teacher reports, and record analytics.

## What works

- Student and teacher profile forms save to a Python API backed by SQLite.
- Student attendance is saved on the server and appears in teacher reports across browsers on this computer.
- Server-side validation, authoritative Indian Standard Time timestamps, and database uniqueness prevent duplicate attendance for a student/course/day, including simultaneous requests.
- Reports and analytics refresh every five seconds. A visible banner reports server connection failures; failed writes do not show successful attendance.
- Profile form values are retained in browser preferences. The SQLite database survives server restarts.

## Run on Windows

Requires Python 3.10+ and Flutter 3.35+ (Dart 3.9+). The launcher finds Flutter on PATH or in `.tools/flutter`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
```

This installs Dart dependencies, builds the Flutter web frontend, and starts the Python backend at **http://127.0.0.1:8080**. The same server serves both the frontend and API, so there is no separate frontend port or CORS configuration.

To leave the app running in the background:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -Background
```

To restart an existing build without rebuilding:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -SkipBuild -Background
```

Logs: `.tools/app.stdout.log` and `.tools/app.stderr.log`. The background process ID is written to `.tools/app-process.pid`. Stop the foreground server with Ctrl+C; stop the background process with `Stop-Process -Id (Get-Content .tools/app-process.pid)`.

The launcher disables desktop plugin generation for its web build and resolves the SDK short path to handle Windows paths containing spaces. Windows Developer Mode is not needed for this web target.

## Try the app

1. Open the URL and choose Student.
2. Fill out the profile and continue.
3. Open the sample Operating Systems class on Home or Schedule, then choose **Record attendance**.
4. Check the student's Analytics page.
5. Open another browser/tab, choose Teacher, and enter a faculty name and ID.
6. Open Attendance or Analytics. The student's record should appear within five seconds.
7. Restart the server and verify the record remains.

No sample attendance is inserted into the real database by the tests.

## Backend

Python standard library only; no pip installation or external database account needed.

- `GET /api/health`: server and database health.
- `POST /api/profiles`: `{ "role": "student" | "teacher", "profile": { ... } }`.
- `GET /api/attendance`: shared attendance records.
- `POST /api/attendance`: `{ "rollNo": "21CS101", "subject": "Operating Systems", "courseCode": "82703" }`.

Data is stored in `backend/data/attendance.sqlite3`, excluded from Git. Back up this database to retain server records. The API only serves built frontend assets, not repository files or the database. It binds to `127.0.0.1` and rejects cross-origin browser writes.

The supported launcher targets web. For a separately hosted frontend or native client, `API_BASE_URL` is available as a Dart build define, but remote hosting, CORS, HTTPS and authentication need deployment-specific configuration.

## Remaining prototype features

This is a working local development app, not a production attendance security system. Role selection does not authenticate users; anyone using this computer can choose Teacher or submit a student ID. Schedules and notifications are sample data. Device approval screens remain labeled samples and do not approve actual hardware. Wi-Fi checks, device binding, classroom presence, managed course sessions, roster-based absences/percentages, and several auxiliary controls are not implemented. Existing browser-only attendance is not automatically migrated to the server.

## Checks

```powershell
python -m unittest discover -s backend -v
# In a terminal where Flutter is configured:
flutter analyze
flutter test
flutter build web
```

Backend tests use temporary databases and verify persistence across restart, concurrent duplicate prevention, input validation and cross-origin rejection. Flutter tests cover the API connection, failed writes, local persistence helpers, and phone-sized screens.
