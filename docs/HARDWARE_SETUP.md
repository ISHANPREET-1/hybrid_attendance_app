# Hardware setup: Archer C6 router, ESP32 CSI sensor, processing laptop

This covers guide Phases 1–3 and Steps 38, 44, 45 and 47: configuring the router, flashing the ESP32, checking CSI capture, recording labelled data, training the detector, and running the live service.

Physical steps (router admin, flashing, recording in the room) have to be done on site. Everything here is scripted so each step gives a pass/fail result you can save as evidence.

```
 Archer C6 (ATTENDANCE_WIFI, 2.4 GHz ch 6, 20 MHz)
     ▲  ping replies ~100/s → CSI
     │
 ESP32-WROOM-32 ──USB (COM3, 921600 baud)──► Laptop: csi/attendance_csi.service
                                                 │  PRESENT / ABSENT / UNKNOWN every 1 s
                                                 ▼  HTTPS + sensor token
                                             Backend  /api/csi/verification
 Student phones (Android app) ── ATTENDANCE_WIFI ──► Backend /api/attendance
```

---

## 1. Router: TP-Link Archer C6 (V4.x)

1. Connect the laptop to the router (LAN cable or its default Wi-Fi) and open `http://tplinkwifi.net` or `http://192.168.0.1`. Log in with the admin password (set one on first login).
2. Go to **Advanced → Wireless → Wireless Settings**, **2.4 GHz** tab:

   | Setting | Value | Why |
   |---|---|---|
   | Enable Wireless Radio | On | |
   | Network Name (SSID) | `ATTENDANCE_WIFI` | Must match the app/backend `ATTENDANCE_SSID` exactly (case-sensitive) |
   | Hide SSID | Off | Phones must see it |
   | Security | WPA/WPA2-Personal, Version **WPA2-PSK**, Encryption **AES** | ESP32 example is set to accept WPA2 |
   | Password | strong, dedicated | Also goes in `firmware/sdkconfig.wifi` |
   | Mode | 802.11b/g/n mixed | |
   | Channel | **6** (or fixed 1 / 11, never Auto) | CSI changes if the channel hops; record it with every dataset |
   | Channel Width | **20 MHz** | The ESP32 CSI layout here assumes 20 MHz LLTF |
   | Transmit Power | High | |

3. **5 GHz** tab: either disable it or give it a different SSID (e.g. `ATTENDANCE_5G`). If both bands share one name, phones may join 5 GHz. The SSID check still passes, but the ESP32 only measures 2.4 GHz.
4. **Advanced → System → Time Settings**: set the time zone to IST (UTC+05:30), with NTP enabled if the router has internet.
5. Optional, recommended: **Advanced → Network → DHCP Server → Address Reservation**. Reserve fixed IPs for the ESP32 (shown in `idf.py monitor` as `got ip:`) and the laptop.
6. Save. Reboot if prompted. Connect the laptop to `ATTENDANCE_WIFI` and check it gets an IP.

**Internet:** CSI capture does not need internet. Phones and the CSI laptop do need to reach the backend. With the hosted (Vercel) backend, plug the router's WAN port into campus internet. With the local backend (`run.ps1` on the laptop), see §7.

Record for the phase report: a screenshot of the 2.4 GHz settings page, plus channel, width and firmware version.

## 2. ESP32 board

1. Plug the ESP32-WROOM-32 into the laptop with a **data** micro-USB cable. Charge-only cables are a common reason nothing shows up.
2. Device Manager → **Ports (COM & LPT)** should show **Silicon Labs CP210x USB to UART Bridge (COM3)**. If not, install the CP210x VCP driver from Silicon Labs, or try another cable or port.
3. Unplug and replug it twice and confirm it comes back on the same COM port. If the number changes, use the new one with `-Port` / `SERIAL_PORT` below.
4. Mounting: fix the board in place (non-metal stand, about 1–1.5 m high) with the router 3–6 m away **across the area where students sit**, so occupants are in the signal path. Don't move either device during a dataset or after training. Moving them means recording and training again. Measure and write down the distance.

## 3. Firmware (ESP-IDF v6.1)

Open **ESP-IDF 6.1 PowerShell** from the Start menu, `cd` into this repository, then:

```powershell
# First time: creates firmware\sdkconfig.wifi from the example and stops.
powershell -ExecutionPolicy Bypass -File firmware\setup_firmware.ps1 -Action build
notepad firmware\sdkconfig.wifi          # put the real SSID and password
powershell -ExecutionPolicy Bypass -File firmware\setup_firmware.ps1 -Action all -Port COM3
```

What the script does:

- Clones Espressif's [esp-csi](https://github.com/espressif/esp-csi) at a pinned commit and builds `examples/get-started/csi_recv_router` **unchanged**. The ESP32 pings the router about 100 times a second and prints CSI for each reply.
- Layers `firmware/sdkconfig.attendance` on top. It sets the IDF 5/6 option names, 921600 baud console, **unlimited Wi-Fi reconnect retries** (the example otherwise gives up after 6), no IPv6 wait, WPA2 threshold, and watchdog reboot on hang.
- Adds `firmware/sdkconfig.wifi` (git-ignored) for the credentials.
- Saves `firmware/logs/build_*.log` and `flash_*.log` as evidence.

Use `-Clean` after changing the Wi-Fi credentials or overlay. Defaults only apply to a fresh `sdkconfig`.

If flashing stops at `Connecting....`, hold **BOOT**, start flashing, and release BOOT when writing begins. If the build fails, read the **first** error. With ESP-IDF 6.1 the usual causes are a missing internet connection for the component manager (it downloads `esp_csi_gain_ctrl`), or a newer esp-csi revision. The pinned commit avoids the second.

**Expected monitor output:** boot log, then `got ip:192.168.0.x, gw: 192.168.0.1`, then `================ CSI RECV ================`, the `type,id,mac,...` header, and a continuous stream of `CSI_DATA,...,"[...]"` lines. Exit with `Ctrl+]`.

## 4. Verify continuous CSI (Step 10)

Close `idf.py monitor`. Only one program can hold COM3. Then:

```powershell
powershell -ExecutionPolicy Bypass -File csi\run_service.ps1 -Setup     # one-time Python venv
cd csi
venv\Scripts\python -m attendance_csi.check_serial --port COM3 --seconds 120
```

You should see about 80–100 packets/s, steady RSSI, 64 subcarriers, and low loss. Walk around the room for the last minute: the `variation` column should rise clearly compared with the empty room. Save the output. Repeat with the router power-cycled to confirm the ESP32 reconnects on its own (`resets` stays 0 and packets resume).

## 5. Record a labelled dataset (Step 14)

Thresholds and models are **not** chosen in advance. They come from your recordings. Minimum to start: **5 empty + 5 occupied** recordings of 2 minutes each, spread over at least two different days or times. More variety gives a more honest evaluation.

```powershell
cd csi
# Empty room: nobody inside, door closed, people outside kept away from the doorway.
venv\Scripts\python -m attendance_csi.record --label empty --occupancy 0 --activity none `
  --experiment 1 --duration 120 --room "Room 101" --position "ESP32 front desk, 1.2 m" --distance-m 4.5 `
  --router-channel 6 --notes "door closed, fans on"

# Occupied, varying who/where/what:
venv\Scripts\python -m attendance_csi.record --label occupied --occupancy 1 --activity sitting `
  --experiment 2 --duration 120 --room "Room 101" --position "ESP32 front desk, 1.2 m" --distance-m 4.5
```

Cover these conditions with separate experiment numbers: 1 person sitting still, 1 walking, several sitting, several moving, people entering and leaving, and the largest group you can gather. Each recording writes `data/recordings/<date>_expNNN_<label>_<n>p.csv` plus a `.json` with the ground truth and setup. Keep a paper log of anything unusual.

## 6. Train and evaluate (Steps 13, 15)

```powershell
venv\Scripts\python -m attendance_csi.train --data data/recordings --out models/presence.joblib --windows 2,3,5
```

- Features (`features.py`) cover temporal amplitude variation (CV, variance, frame-to-frame change), correlation with the window's mean profile, first-component energy share and RSSI spread. They come after guard-subcarrier removal, Hampel outlier clipping, a 3-point median filter and per-frame normalisation.
- Candidates: single-feature **threshold baseline**, logistic regression, random forest and SVM, each at every window length.
- Evaluation is **StratifiedGroupKFold by recording**: windows from one recording never appear in both train and test. The report prints accuracy, precision, recall, F1, the confusion matrix, and the false-positive and false-negative rates. It's saved as `models/presence.report.json`, which is your Phase evidence.
- The best by F1 (then lowest FPR) is saved with its window size, a minimum packet rate, and a confidence threshold (default 0.7). If F1 < 0.9 or FPR > 5%, the trainer warns: don't deploy, collect more varied data, or reposition the board.

A model validated with a few people is **not** validated for 100–250 students. Re-record and re-evaluate at realistic occupancy before relying on it.

## 7. Register the sensor and run the live service (Steps 16, 22, 44)

1. Make sure the class's **Room** field in the app matches the sensor's room exactly (e.g. `Room 101`).
2. Register the sensor. Either use **Administration → CSI sensors → Register sensor** in the app, or run this on the backend host:
   `.tools\venv\Scripts\python.exe -m backend.manage create-sensor --name "ESP32 Room 101" --room "Room 101"`
   Copy the one-time token.
3. Create `csi\.env` from `csi\.env.example`: set `BACKEND_URL` (the app's HTTPS origin) and `CSI_SERVICE_TOKEN`.
4. Run: `powershell -ExecutionPolicy Bypass -File csi\run_service.ps1`. It restarts automatically if it crashes. Logs go to `csi\logs\csi_service.log`.
5. In the app, a teacher opens a session with **CSI room-presence check: Require**. The session card shows `Room sensor (Room 101): PRESENT · confidence 93% · 0.8 s ago`.

States sent each second:

| State | When |
|---|---|
| `PRESENT` / `ABSENT` | Enough fresh packets, model confidence ≥ threshold, and recent windows agree |
| `UNKNOWN` | No packets for 2 s (ESP32 unplugged, router down, COM3 busy), too few packets, unusable window, low confidence, or windows disagree |

The backend rejects readings older than `CSI_MAX_AGE_S` (default 30 s), timestamps in the future, unknown states, and unauthenticated or revoked tokens. At check-in, `UNKNOWN`, stale or missing data gives **PENDING** (nothing recorded, retry). `ABSENT` gives **REJECTED**. Replayed data is refused unless `CSI_ALLOW_REPLAY=true`.

**Local backend on the laptop (no internet):** phones need HTTPS for the app and location features. The simplest robust setup is the hosted backend with internet on the router WAN. For a fully offline demo, run `run.ps1` on the laptop and use the browser portal on the laptop itself. Phone check-in still needs an HTTPS origin.

**Keep the laptop awake:** Settings → System → Power → Screen and sleep → *Never* while plugged in. Disable USB selective suspend (Power Options → Advanced → USB settings) so Windows doesn't power down the ESP32.

## 8. Recovery procedures (Step 45)

| Symptom | Action |
|---|---|
| Session card shows `UNKNOWN · no CSI packets` | Check the ESP32 LED and USB. Run `check_serial`. Replug USB, and the service reconnects on its own within seconds. |
| ESP32 not on the router after a power cut | It retries forever. If it's still offline after 1 minute, press **EN** (reset). |
| `Backend rejected reading: 401` in the log | Sensor token revoked or wrong. Register a new sensor and update `csi\.env`. |
| `422 timestamp is in the future` / stale | Laptop clock is wrong. Turn on *Set time automatically*. |
| Re-flash | `firmware\setup_firmware.ps1 -Action all -Port COM3` (add `-Clean` if settings changed). |

## 9. Classroom demonstration (Step 47)

1. Power on the router and wait for `ATTENDANCE_WIFI`. Plug in the ESP32. Run `check_serial` for 20 s and confirm ~100 pkt/s.
2. Start `csi\run_service.ps1`. The log shows `PRESENT conf=…` with people in the room.
3. Teacher signs in → Sessions → Open session with Code **Required**, Wi-Fi **Require** (`ATTENDANCE_WIFI`), and CSI **Require**. The session card shows the room sensor PRESENT.
4. Student phone joins `ATTENDANCE_WIFI` → Android app → sign in → Sessions → **Check in**. The dialog lists each layer: Authentication ✓, Session ✓, Registered device ✓, Code ✓, Classroom Wi-Fi ✓, Room presence ✓ → *Attendance successful*.
5. Teacher → Reports shows the student Present. Expand *Verification attempts* to see each attempt.
6. Show the rejections: (a) the same student on mobile data or another Wi-Fi gets *Classroom Wi-Fi ✗*. (b) A second phone signed in to the same account gets *Registered device ✗*. (c) Unplug the ESP32 for 5 s → *Verification pending · Room sensor data is stale/uncertain*.
7. Keep a backup recording. If the live RF environment misbehaves, `python -m attendance_csi.service --replay <file.csv>` shows the pipeline in dry-run. Posting a replay needs `--post-replay`, and the backend still refuses it for attendance unless `CSI_ALLOW_REPLAY=true` is set **for the demo only**. Say clearly when you're showing replayed data.
