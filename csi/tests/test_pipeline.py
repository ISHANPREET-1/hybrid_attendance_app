"""CSI pipeline tests (guide Step 39). Run from csi/:  python -m unittest discover -s tests"""
import io as stdio
import sys
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent))  # repository root, for the backend end-to-end test

from attendance_csi import train
from attendance_csi.detector import Detector
from attendance_csi.features import MODEL_FEATURES, window_features, windows
from attendance_csi.io import frames_from_lines, load_directory, serial_lines
from attendance_csi.parser import ParseError, amplitudes, parse_line
from attendance_csi.service import Poster, run
from attendance_csi.simulate import Room, lines, write_recordings

FIXTURE = ROOT / 'tests/fixtures/esp_csi_readme_lines.txt'


class ParserTests(unittest.TestCase):
    def test_real_espressif_lines_both_layouts(self):
        esp32, c6 = [parse_line(l) for l in FIXTURE.read_text().splitlines()]
        self.assertEqual((esp32.seq, esp32.rssi, esp32.channel, esp32.raw.size), (0, -30, 13, 128))
        self.assertEqual((c6.seq, c6.rssi, c6.channel, c6.raw.size), (7, -23, 11, 256))
        # first_word=1 on the ESP32 line: first two subcarriers are invalid and zeroed.
        self.assertTrue(np.all(esp32.raw[:4] == 0))
        self.assertEqual(esp32.amplitudes.size, 64)

    def test_amplitude_formula(self):
        np.testing.assert_allclose(amplitudes([3, 4, -6, 8]), [5, 10])

    def test_logs_headers_and_malformed_lines(self):
        self.assertIsNone(parse_line('I (1234) wifi: connected'))
        self.assertIsNone(parse_line('type,id,mac,rssi,...'))
        good = FIXTURE.read_text().splitlines()[0]
        for bad in (good[:120], good.replace('"[', '"[x,'), good.replace(',-30,', ',-300,'),
                    good.replace(',128,1,', ',99,1,')):
            with self.assertRaises(ParseError):
                parse_line(bad)
        # Boot noise glued in front of a valid line (common after a reset) still parses.
        self.assertIsNotNone(parse_line('\x00\x1b[0m' + good))

    def test_frames_from_lines_counts_errors(self):
        good = FIXTURE.read_text().splitlines()[0]
        stats = {}
        out = list(frames_from_lines([(1.0, good), (2.0, 'garbage CSI_DATA,1,"[1'), (3.0, None), (4.0, 'log')], stats))
        self.assertEqual(stats, {'frames': 1, 'errors': 1})
        self.assertEqual([f is None for _, f in out], [False, True])


class SerialReconnectTests(unittest.TestCase):
    def test_reconnects_after_unplug(self):
        good = (FIXTURE.read_text().splitlines()[0] + '\n').encode()
        attempts = {'n': 0}

        class Port:
            def __init__(self, data):
                self.data = list(data)

            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

            def readline(self):
                if not self.data:
                    raise OSError('device disconnected')
                return self.data.pop(0)

        def opener():
            attempts['n'] += 1
            if attempts['n'] == 2:
                raise OSError('COM3 busy')
            return Port([good, b''])

        got = []
        def csi_lines():
            return sum(1 for g in got if g and g.startswith('CSI_DATA'))
        for _, line in serial_lines('COM3', retry_s=0, opener=opener, stop=lambda: csi_lines() >= 2 or attempts['n'] > 5):
            got.append(line)
        self.assertGreaterEqual(attempts['n'], 3)
        self.assertEqual(sum(1 for g in got if g and g.startswith('CSI_DATA')), 2)


class FeatureTests(unittest.TestCase):
    def frames(self, occupants, seconds=4, seed=1):
        room = Room(seed)
        return [(t, parse_line(l, t).amplitudes, parse_line(l, t).rssi) for t, l in lines(room, occupants, seconds)]

    def test_occupancy_raises_temporal_variation(self):
        empty = window_features(*zip(*self.frames(0)))
        busy = window_features(*zip(*self.frames(2)))
        self.assertGreater(busy['amp_cv_time'], 2 * empty['amp_cv_time'])
        self.assertLess(busy['corr_mean'], empty['corr_mean'])
        self.assertAlmostEqual(empty['packet_rate'], 100, delta=2)

    def test_windows_and_short_input(self):
        frames = self.frames(0, seconds=6)
        # 6 s of frames -> windows starting at 0, 1, 2 s (a 3-6 s window would overrun the data).
        self.assertEqual(len(list(windows(frames, 3, 1))), 3)
        self.assertIsNone(window_features([0, 1], [np.ones(64)] * 2, [-40, -40]))


class TrainingAndDetectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.data = Path(cls.tmp.name) / 'rec'
        cls.model = Path(cls.tmp.name) / 'presence.joblib'
        write_recordings(cls.data, count=3, seconds=20)
        with redirect_stdout(stdio.StringIO()) as out:
            cls.code = train.main(['--data', str(cls.data), '--out', str(cls.model), '--windows', '2,3'])
        cls.output = out.getvalue()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_grouped_split_and_model_saved(self):
        self.assertEqual(self.code, 0, self.output)
        self.assertTrue(self.model.exists())
        self.assertTrue(self.model.with_suffix('.report.json').exists())
        df = train.build_dataset(load_directory(self.data), 3, 1)
        self.assertEqual(df['recording'].nunique(), 6)
        self.assertIn('Selected', self.output)

    def test_detector_states(self):
        det = Detector(str(self.model), consensus=1)
        self.assertEqual(det.features, MODEL_FEATURES)
        room, start = Room(7), 1_900_000_000.0
        for occupants, expected in ((2, 'PRESENT'), (0, 'ABSENT')):
            det = Detector(str(self.model), consensus=1)
            for t, l in lines(room, occupants, det.window_s + 0.5, start):
                f = parse_line(l, t)
                det.add(t, f.amplitudes, f.rssi)
            result = det.evaluate(t)
            self.assertEqual(result.status, expected, result)
            self.assertGreaterEqual(result.confidence, det.min_confidence)
        # Stale: no packets for longer than stale_s -> UNKNOWN, never PRESENT.
        self.assertEqual(det.evaluate(t + 5).status, 'UNKNOWN')
        # Too few packets (e.g. router busy) -> UNKNOWN.
        det = Detector(str(self.model), consensus=1)
        for i, (tt, l) in enumerate(lines(room, 2, det.window_s, start)):
            if i % 50 == 0:
                f = parse_line(l, tt)
                det.add(tt, f.amplitudes, f.rssi)
        self.assertEqual(det.evaluate(tt).status, 'UNKNOWN')

    def test_service_posts_to_real_backend(self):
        """Serial lines -> detector -> authenticated POST -> backend stores the reading."""
        from backend.server import create_server
        from backend.service import digest
        from backend.database import csi_sensors, csi_readings
        from sqlalchemy import insert, select
        import requests
        tmp = Path(self.tmp.name)
        server = create_server(0, tmp / 'db.sqlite3', tmp / 'web', setup_token='x')
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with server.service.engine.begin() as conn:
                conn.execute(insert(csi_sensors).values(id='s1', name='bench', room='Lab 3B',
                                                        token_hash=digest('tok'), active=1, created_at=time.time()))
            url = f'http://127.0.0.1:{server.server_port}'
            det = Detector(str(self.model), consensus=1)
            now = time.time()
            room = Room(3)
            stream = ((t, parse_line(l, t)) for t, l in lines(room, 2, det.window_s + 1.2, now - det.window_s - 1.2))
            poster = Poster(url, 'tok', requests.Session())
            sent = []
            poster.submit = lambda p: sent.append(poster.post(p))
            run(det, stream, poster, interval=1.0)
            self.assertTrue(sent and all(sent), poster.last_error)
            bad = Poster(url, 'wrong', requests.Session())
            self.assertFalse(bad.post({'status': 'PRESENT', 'timestamp': time.time()}))
            self.assertTrue(bad.last_error.startswith('401'))
            with server.service.engine.connect() as conn:
                stored = conn.execute(select(csi_readings.c.status, csi_readings.c.room)).all()
            self.assertTrue(stored)
            self.assertTrue(all(r.room == 'Lab 3B' for r in stored))
        finally:
            server.shutdown()
            server.server_close()
            server.service.engine.dispose()


if __name__ == '__main__':
    unittest.main()
