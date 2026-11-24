# CSI room-presence pipeline

Turns ESP32 Wi-Fi Channel State Information into a room-level `PRESENT` / `ABSENT` / `UNKNOWN` signal for the attendance backend. It never identifies a student.

Full on-site procedure: [`docs/HARDWARE_SETUP.md`](../docs/HARDWARE_SETUP.md).

| Command (run from `csi/`) | Purpose |
|---|---|
| `python -m attendance_csi.check_serial --port COM3` | Confirm continuous CSI: packet rate, loss, resets, variation |
| `python -m attendance_csi.record --label empty --occupancy 0 ...` | Record a labelled dataset to `data/recordings/` |
| `python -m attendance_csi.train --data data/recordings --windows 2,3,5` | Compare models and windows with grouped CV, save `models/presence.joblib` + report |
| `python -m attendance_csi.service` | Live service: serial → detector → `POST /api/csi/verification` (settings in `.env`) |
| `python -m attendance_csi.service --replay FILE.csv` | Offline dry run on a recording (tagged REPLAY if posted) |
| `python -m attendance_csi.simulate` | Synthetic data for tests only. Not evidence of real-room performance |
| `python -m unittest discover -s tests` | Pipeline tests, including end-to-end posting to a real backend |

On Windows, `run_service.ps1` creates the venv, installs `requirements.txt`, and restarts the service if it exits with an error.

`data/`, `models/`, `logs/` and `.env` are git-ignored. Keep the raw recordings and training reports as project evidence.
