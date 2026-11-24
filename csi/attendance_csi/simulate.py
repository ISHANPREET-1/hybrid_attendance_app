"""Synthetic CSI in the exact ESP32 serial format, for tests and pipeline dry runs.

Synthetic data is NOT evidence that detection works in a real room. Recordings
are tagged ``source: synthetic`` and must not be mixed with real datasets.

    python -m attendance_csi.simulate --out data/synthetic --recordings 4
"""
import argparse
import sys

import numpy as np

from .io import Recorder
from .parser import CsiFrame, format_line, parse_line

SUBCARRIERS = 64
GUARD = {0, 1, 2, 3, 4, 5, 32, 59, 60, 61, 62, 63}  # null/guard tones stay ~0


class Room:
    """Static multipath profile plus noise; occupants add slow, correlated fluctuation."""

    def __init__(self, seed=0):
        self.rng = np.random.default_rng(seed)
        self.base = self.rng.uniform(12, 30, SUBCARRIERS)
        self.phase = self.rng.uniform(0, 2 * np.pi, SUBCARRIERS)

    def frame(self, t, occupants, seq, rate_hz=100):
        amp = self.base * (1 + 0.015 * self.rng.standard_normal(SUBCARRIERS))
        rssi = -45 + self.rng.normal(0, 0.6)
        for k in range(occupants):
            freq = 0.25 + 0.4 * k  # breathing / shifting
            shape = np.sin(np.linspace(0, (3 + k) * np.pi, SUBCARRIERS) + self.phase[k % SUBCARRIERS])
            amp *= 1 + 0.12 * np.sin(2 * np.pi * freq * t + k) * shape
            rssi += self.rng.normal(0, 1.2)
        amp[list(GUARD)] = 0
        angle = self.rng.uniform(0, 2 * np.pi, SUBCARRIERS)
        imag, real = np.round(amp * np.sin(angle)), np.round(amp * np.cos(angle))
        raw = np.clip(np.column_stack([imag, real]).ravel(), -127, 127).astype(np.int16)
        return CsiFrame(seq=seq, mac='aa:bb:cc:dd:ee:ff', rssi=int(round(rssi)), channel=6, noise_floor=-95,
                        local_timestamp_us=int(t * 1e6), raw=raw, host_time=t)


def lines(room, occupants, seconds, start=1_800_000_000.0, rate_hz=100):
    for i in range(int(seconds * rate_hz)):
        t = start + i / rate_hz
        yield t, format_line(room.frame(t, occupants, i, rate_hz))


def write_recordings(out, count=3, seconds=60, seed=0):
    room = Room(seed)
    paths = []
    for n in range(count):
        for label, occ in (('empty', 0), ('occupied', 1 + n % 3)):
            stem = f'synthetic_exp{n:03d}_{label}_{occ}p'
            rec = Recorder(out, stem, dict(label=label, occupancy=occ, activity='synthetic', experiment=n,
                                           source='synthetic', position='simulated', distance_m=0,
                                           router_channel=6, bandwidth_mhz=20))
            start = 1_800_000_000.0 + n * 10_000 + (5_000 if occ else 0)
            for t, line in lines(room, occ, seconds, start):
                rec.write(parse_line(line, t))
            rec.close()
            paths.append(rec.csv_path)
    return paths


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--out', default='data/synthetic')
    parser.add_argument('--recordings', type=int, default=4, help='Pairs of empty/occupied recordings')
    parser.add_argument('--seconds', type=float, default=60)
    args = parser.parse_args(argv)
    for path in write_recordings(args.out, args.recordings, args.seconds):
        print(path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
