"""Live CSI presence service: ESP32 serial -> detector -> backend (Steps 16, 22, 44).

    python -m attendance_csi.service              # reads csi/.env

Settings (environment or csi/.env):
    BACKEND_URL         e.g. https://your-app.vercel.app or http://192.168.0.10:8080
    CSI_SERVICE_TOKEN   from `python -m backend.manage create-sensor` or Admin > CSI sensors
    SERIAL_PORT         COM3
    SERIAL_BAUD         921600
    MODEL_PATH          models/presence.joblib
    REPORT_INTERVAL_S   1
    SESSION_ID          optional; binds readings to one session

Readings are posted from a background thread so a slow network never stalls
serial reading. Only the newest result is kept if posting falls behind. When the
serial link drops, UNKNOWN is reported so the backend never sees stale PRESENT.

Replay (offline demo data, clearly marked):
    python -m attendance_csi.service --replay data/recordings/X.csv            # dry run
    python -m attendance_csi.service --replay X.csv --post-replay              # posts, tagged REPLAY
The backend refuses REPLAY readings for attendance unless CSI_ALLOW_REPLAY=true.
"""
import argparse
import logging
import os
import queue
import sys
import threading
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

from .detector import Detector
from .io import frames_from_lines, load_recording, serial_lines

log = logging.getLogger('attendance_csi')
REPLAY_TAG = 'REPLAY: offline recorded data'


class Poster(threading.Thread):
    def __init__(self, url, token, session=None, timeout=5.0):
        super().__init__(daemon=True)
        if session is None:
            import requests
            session = requests.Session()
        self.url = url.rstrip('/') + '/api/csi/verification'
        self.token, self.http, self.timeout = token, session, timeout
        self.queue = queue.Queue(maxsize=1)
        self.sent = self.failed = 0
        self.last_error = None
        self._stop = threading.Event()

    def submit(self, payload):
        try:
            self.queue.get_nowait()  # drop the older unsent result
        except queue.Empty:
            pass
        self.queue.put_nowait(payload)

    def run(self):
        while not self._stop.is_set():
            try:
                payload = self.queue.get(timeout=0.5)
            except queue.Empty:
                continue
            self.post(payload)

    def post(self, payload):
        try:
            response = self.http.post(self.url, json=payload, timeout=self.timeout,
                                      headers={'Authorization': f'Bearer {self.token}'})
            if response.status_code == 200:
                self.sent += 1
                self.last_error = None
                return True
            self.failed += 1
            self.last_error = f'{response.status_code} {response.text[:200]}'
            level = logging.CRITICAL if response.status_code == 401 else logging.WARNING
            log.log(level, 'Backend rejected reading: %s', self.last_error)
        except Exception as error:
            self.failed += 1
            self.last_error = str(error)
            log.warning('Backend unreachable: %s', error)
        return False

    def stop(self):
        self._stop.set()


def load_env(path):
    path = Path(path)
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def run(detector, frame_source, poster, interval, session_id=None, source=None, stop=lambda: False):
    next_report = None
    for now, frame in frame_source:
        if frame is not None:
            detector.add(frame.host_time, frame.amplitudes, frame.rssi)
        if next_report is None:
            # Schedule from the stream's own clock (serial host time or replay time).
            next_report = now + interval
        if now >= next_report:
            next_report = now + interval
            result = detector.evaluate(now)
            payload = result.payload(session_id, source)
            log.info('%s conf=%s packets=%d %s', result.status, payload.get('confidence'), result.packets, result.error or '')
            if poster:
                poster.submit(payload)
            else:
                print(payload, flush=True)
        if stop():
            break


def replay_frames(path, realtime=True):
    """Re-time a recording to the current clock so the detector sees it as a stream."""
    from .parser import CsiFrame
    import numpy as np
    _, frames = load_recording(path)
    if not frames:
        return
    offset = time.time() - frames[0][0]
    for t, amps, rssi in frames:
        target = t + offset
        if realtime:
            delay = target - time.time()
            if delay > 0:
                time.sleep(delay)
        # Re-pack amplitude as (0, amp) pairs; amplitude is preserved exactly.
        raw = np.column_stack([np.zeros_like(amps), amps]).ravel()
        frame = CsiFrame(0, 'replay', rssi, 0, 0, 0, raw, host_time=target)
        yield target, frame


def main(argv=None):
    load_env(Path(__file__).resolve().parent.parent / '.env')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--backend', default=os.getenv('BACKEND_URL'))
    parser.add_argument('--port', default=os.getenv('SERIAL_PORT', 'COM3'))
    parser.add_argument('--baud', type=int, default=int(os.getenv('SERIAL_BAUD', '921600')))
    parser.add_argument('--model', default=os.getenv('MODEL_PATH', 'models/presence.joblib'))
    parser.add_argument('--interval', type=float, default=float(os.getenv('REPORT_INTERVAL_S', '1')))
    parser.add_argument('--session-id', default=os.getenv('SESSION_ID') or None)
    parser.add_argument('--dry-run', action='store_true', help='Print results instead of posting')
    parser.add_argument('--replay', help='Feed a recorded CSV instead of the serial port')
    parser.add_argument('--post-replay', action='store_true', help='Allow posting replayed data (tagged REPLAY)')
    parser.add_argument('--log', default='logs/csi_service.log')
    args = parser.parse_args(argv)

    Path(args.log).parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s',
                        handlers=[logging.StreamHandler(), RotatingFileHandler(args.log, maxBytes=5_000_000, backupCount=5)])
    if not Path(args.model).exists():
        parser.error(f'Model {args.model} not found. Record data and run attendance_csi.train first.')
    detector = Detector(args.model)
    log.info('Model %s, window %.1fs, min confidence %.2f', detector.bundle['kind'], detector.window_s, detector.min_confidence)

    dry = args.dry_run or (args.replay and not args.post_replay)
    poster = None
    if not dry:
        token = os.getenv('CSI_SERVICE_TOKEN')
        if not args.backend or not token:
            parser.error('Set BACKEND_URL and CSI_SERVICE_TOKEN (csi/.env), or use --dry-run')
        poster = Poster(args.backend, token)
        poster.start()
    if args.replay:
        source, tag = ((t, f) for t, f in replay_frames(args.replay)), REPLAY_TAG
        log.warning('REPLAY MODE: results come from %s, not live CSI', args.replay)
    else:
        source, tag = frames_from_lines(serial_lines(args.port, args.baud)), None
    try:
        run(detector, source, poster, args.interval, args.session_id, tag)
    except KeyboardInterrupt:
        pass
    finally:
        if poster:
            poster.stop()
            log.info('Posted %d readings, %d failures', poster.sent, poster.failed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
