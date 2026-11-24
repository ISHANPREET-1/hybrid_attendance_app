"""Record a labelled CSI dataset from the ESP32 (guide Step 14).

Example (empty room, 120 s)::

    python -m attendance_csi.record --port COM3 --label empty --occupancy 0 \
        --activity none --experiment 1 --duration 120 \
        --position "ESP32 on front desk, 1.2 m high" --distance-m 4.5

Repeat several times per class, changing positions and activity for occupied
recordings (sitting, walking, entering/leaving, different group sizes). Close
``idf.py monitor`` first: only one program can hold COM3.
"""
import argparse
import logging
import signal
import sys
import time

from .io import LABELS, Recorder, frames_from_lines, serial_lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--port', default='COM3')
    parser.add_argument('--baud', type=int, default=921600)
    parser.add_argument('--out', default='data/recordings')
    parser.add_argument('--label', choices=LABELS, required=True, help='Ground truth for the whole recording')
    parser.add_argument('--occupancy', type=int, required=True, help='Number of people in the room')
    parser.add_argument('--activity', default='', help='e.g. none, sitting, walking, entering-leaving')
    parser.add_argument('--experiment', type=int, required=True)
    parser.add_argument('--duration', type=float, default=120)
    parser.add_argument('--position', required=True, help='ESP32 mounting position')
    parser.add_argument('--distance-m', type=float, required=True, help='Router to ESP32 distance')
    parser.add_argument('--router-channel', type=int, default=6)
    parser.add_argument('--bandwidth-mhz', type=int, default=20)
    parser.add_argument('--room', default='')
    parser.add_argument('--notes', default='', help='Doors/windows, furniture changes, interference ...')
    args = parser.parse_args(argv)
    if (args.label == 'empty') != (args.occupancy == 0):
        parser.error('label "empty" must have --occupancy 0, and "occupied" must have --occupancy >= 1')
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')

    stem = f'{time.strftime("%Y%m%d")}_exp{args.experiment:03d}_{args.label}_{args.occupancy}p'
    recorder = Recorder(args.out, stem, dict(
        label=args.label, occupancy=args.occupancy, activity=args.activity, experiment=args.experiment,
        room=args.room, position=args.position, distance_m=args.distance_m,
        router_channel=args.router_channel, bandwidth_mhz=args.bandwidth_mhz, notes=args.notes,
        source='live-serial', port=args.port))
    stopped = {'flag': False}
    signal.signal(signal.SIGINT, lambda *_: stopped.update(flag=True))
    deadline, stats, last_report = time.time() + args.duration, {}, 0
    lines = serial_lines(args.port, args.baud, stop=lambda: stopped['flag'] or time.time() >= deadline)
    try:
        for now, frame in frames_from_lines(lines, stats):
            if frame is not None:
                recorder.write(frame)
            if now - last_report >= 5:
                last_report = now
                remaining = max(0, deadline - now)
                print(f'  {recorder.meta["frames"]} frames, {stats.get("errors", 0)} malformed, {remaining:.0f}s left', flush=True)
            if now >= deadline or stopped['flag']:
                break
    finally:
        recorder.close(stats.get('errors', 0))
    print(f'Saved {recorder.csv_path} ({recorder.meta["frames"]} frames)')
    if recorder.meta['frames'] == 0:
        print('No CSI frames received. Check the ESP32 is flashed, connected to the router, and that '
              'idf.py monitor is closed.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
