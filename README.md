# Hybrid Attendance

Flutter attendance app with student, teacher, and sample device approval screens.

## Run

From PowerShell in this folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1
```

The script uses Flutter on PATH or the local `.tools/flutter` SDK and serves the app at http://127.0.0.1:8080. Keep the terminal open. Open that URL in a browser. Use the same browser and port to retain local data.

To keep the app running in the background after closing the terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -Background
```

Startup output and errors are saved in `.tools/app.stdout.log` and `.tools/app.stderr.log`.

The web launcher temporarily disables desktop plugin generation, so Windows Developer Mode is not required. It also uses the SDK short path to avoid spaces in native build-hook commands.

With Flutter already installed and desktop symlink support enabled:

```powershell
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

## Working local flow

1. Select Student and fill in the profile form.
2. Open the active Operating Systems class on Home or Schedule.
3. Choose **Record demo attendance**. Duplicate attendance for the same student, course and local date is prevented.
4. Check Analytics for saved records.
5. Log out, select Teacher, and enter a name and faculty ID.
6. Open Attendance or Analytics to see records saved in this browser.

Profiles and attendance persist using shared preferences. Passwords are not stored. Log out returns to role selection; it does not erase local profiles or attendance.

## Integration limits

This repository contains no backend, authentication service, roster, or classroom session API. Role selection is a local demo, not authentication. Attendance does not verify classroom Wi-Fi, device identity, or physical presence. Device approval screens use sample requests and do not bind actual devices. Local records do not sync between browsers or devices. Unsupported controls explain these limitations.

To enable verified attendance, provide the backend source or API contract, authentication configuration, class roster/session endpoints, and the target platform's Wi-Fi/presence verification requirements. Production credentials should not be committed to the repository.

## Checks

```powershell
flutter analyze
flutter test
flutter build web
```
