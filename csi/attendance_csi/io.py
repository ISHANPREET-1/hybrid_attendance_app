"""Serial reading with reconnection, and the labelled recording format.

A recording is two files sharing a stem in the data directory:

* ``<stem>.csv`` - one row per valid CSI frame: host_time, seq, rssi, channel,
  noise_floor, local_timestamp_us, raw (space-separated int values).
* ``<stem>.json`` - metadata: label (ground truth), occupancy count, activity,
  experiment number, router channel/bandwidth, ESP32 position and distance,
  environment notes, start/end time, frame and error counts.
"""
import csv
import json
import logging
import time
from pathlib import Path

import numpy as np

from .parser import CsiFrame, ParseError, parse_line

log = logging.getLogger(__name__)
CSV_FIELDS = ['host_time', 'seq', 'rssi', 'channel', 'noise_floor', 'local_timestamp_us', 'raw']
LABELS = ('empty', 'occupied')


def serial_lines(port, baud=921600, timeout=1.0, retry_s=2.0, stop=lambda: False, opener=None):
    """Yield (host_time, line) forever, reopening the port after disconnection.

    Yields (host_time, None) on every timeout or while disconnected so callers can
    detect missing data and report UNKNOWN instead of blocking.
    """
    if opener is None:
        import serial  # pyserial

        def opener():
            return serial.Serial(port, baud, timeout=timeout)
    while not stop():
        try:
            with opener() as handle:
                log.info('Opened %s at %d baud', port, baud)
                while not stop():
                    raw = handle.readline()
                    now = time.time()
                    if not raw:
                        yield now, None
                        continue
                    yield now, raw.decode('ascii', errors='replace')
        except Exception as error:  # serial.SerialException, OSError on unplug
            log.warning('Serial port %s unavailable (%s); retrying in %.0fs. '
                        'Close idf.py monitor if it is open.', port, error, retry_s)
            yield time.time(), None
            time.sleep(retry_s)


def frames_from_lines(lines, stats=None):
    """Parse (host_time, line) pairs, counting and skipping malformed lines."""
    stats = stats if stats is not None else {}
    for host_time, line in lines:
        if line is None:
            yield host_time, None
            continue
        try:
            frame = parse_line(line, host_time)
        except ParseError as error:
            stats['errors'] = stats.get('errors', 0) + 1
            log.debug('Skipping malformed CSI line: %s', error)
            continue
        if frame is not None:
            stats['frames'] = stats.get('frames', 0) + 1
            yield host_time, frame


class Recorder:
    def __init__(self, directory, stem, metadata):
        self.dir = Path(directory)
        self.dir.mkdir(parents=True, exist_ok=True)
        self.csv_path, self.meta_path = self.dir / f'{stem}.csv', self.dir / f'{stem}.json'
        if self.csv_path.exists():
            raise FileExistsError(f'{self.csv_path} already exists; use a new experiment number')
        self.meta = dict(metadata, started_at=time.time(), frames=0, errors=0)
        self._file = open(self.csv_path, 'w', newline='')
        self._writer = csv.writer(self._file)
        self._writer.writerow(CSV_FIELDS)

    def write(self, frame: CsiFrame):
        self._writer.writerow([f'{frame.host_time:.6f}', frame.seq, frame.rssi, frame.channel, frame.noise_floor,
                               frame.local_timestamp_us, ' '.join(str(int(v)) for v in frame.raw)])
        self.meta['frames'] += 1

    def close(self, errors=0):
        self._file.close()
        self.meta.update(ended_at=time.time(), errors=errors)
        self.meta_path.write_text(json.dumps(self.meta, indent=2))


def load_recording(csv_path):
    """Return (metadata, frames) where frames is a list of (host_time, amplitudes, rssi)."""
    from .parser import amplitudes
    csv_path = Path(csv_path)
    meta = json.loads(csv_path.with_suffix('.json').read_text())
    frames = []
    with open(csv_path, newline='') as handle:
        for row in csv.DictReader(handle):
            try:
                raw = np.array([int(v) for v in row['raw'].split()], dtype=np.int16)
                frames.append((float(row['host_time']), amplitudes(raw), int(row['rssi'])))
            except (ValueError, KeyError):
                continue
    frames.sort(key=lambda f: f[0])
    return meta, frames


def load_directory(directory):
    paths = sorted(Path(directory).glob('*.csv'))
    if not paths:
        raise FileNotFoundError(f'No recordings in {directory}')
    return [(p.stem, *load_recording(p)) for p in paths if p.with_suffix('.json').exists()]
