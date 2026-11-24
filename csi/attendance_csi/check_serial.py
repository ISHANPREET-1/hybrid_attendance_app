"""Verify continuous CSI acquisition from the ESP32 (guide Steps 10 and 38).

    python -m attendance_csi.check_serial --port COM3 --seconds 60

Reports packets/second, sequence gaps (lost packets), ESP32 resets (sequence
restarting at 0), malformed lines, RSSI, channel and subcarrier count. Walk
in and out of the room while it runs and watch the "variation" column rise.
"""
import argparse
import logging
import sys
import time

import numpy as np

from .features import window_features
from .io import frames_from_lines, serial_lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--port', default='COM3')
    parser.add_argument('--baud', type=int, default=921600)
    parser.add_argument('--seconds', type=float, default=60)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')

    deadline, stats = time.time() + args.seconds, {}
    last_seq, gaps, resets, total = None, 0, 0, 0
    block, block_start = [], time.time()
    print(f'{"time":>8} {"pkt/s":>6} {"rssi":>5} {"ch":>3} {"subc":>5} {"variation":>9} {"lost":>5} {"resets":>6}')
    for now, frame in frames_from_lines(serial_lines(args.port, args.baud, stop=lambda: time.time() > deadline), stats):
        if frame is not None:
            total += 1
            if last_seq is not None:
                if frame.seq < last_seq:
                    resets += 1
                elif frame.seq > last_seq + 1:
                    gaps += frame.seq - last_seq - 1
            last_seq = frame.seq
            block.append(frame)
        if now - block_start >= 2:
            if block:
                feats = window_features([f.host_time for f in block], [f.amplitudes for f in block], [f.rssi for f in block])
                variation = f'{feats["amp_cv_time"]:.4f}' if feats else '-'
                print(f'{time.strftime("%H:%M:%S"):>8} {len(block) / (now - block_start):6.1f} '
                      f'{np.mean([f.rssi for f in block]):5.0f} {block[-1].channel:3d} {block[-1].amplitudes.size:5d} '
                      f'{variation:>9} {gaps:5d} {resets:6d}', flush=True)
            else:
                print(f'{time.strftime("%H:%M:%S"):>8}   no CSI frames (ESP32 not connected to router, wrong port/baud, or monitor still open)')
            block, block_start = [], now
        if now > deadline:
            break
    expected = total + gaps
    print(f'\nFrames: {total}, malformed lines: {stats.get("errors", 0)}, lost by sequence gap: {gaps} '
          f'({100 * gaps / expected if expected else 0:.1f}%), ESP32 restarts: {resets}')
    return 0 if total else 1


if __name__ == '__main__':
    sys.exit(main())
