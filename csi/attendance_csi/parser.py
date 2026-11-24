"""Parse the serial output of Espressif's esp-csi ``csi_recv_router`` example.

ESP32 (classic/S2/S3/C3) line format, 25 comma-separated columns::

    CSI_DATA,id,mac,rssi,rate,sig_mode,mcs,bandwidth,smoothing,not_sounding,
    aggregation,stbc,fec_coding,sgi,noise_floor,ampdu_cnt,channel,
    secondary_channel,local_timestamp,ant,sig_len,rx_format,len,first_word,"[..]"

ESP32-C5/C6/C61 use a shorter 15-column header. Both are handled by reading the
fixed fields from the front and the last three (len, first_word, data) from the
back, so either layout parses without configuration.

The data array holds signed 8-bit pairs per subcarrier, imaginary then real.
Amplitude = sqrt(real^2 + imag^2). When ``first_word`` is 1 the first four bytes
(two subcarriers) are invalid and are zeroed.
"""
from dataclasses import dataclass, field
import math
import time

import numpy as np

HEADER_PREFIX = 'type,'
DATA_PREFIX = 'CSI_DATA'
LONG_FIELDS = 25   # ESP32 / S2 / S3 / C3
SHORT_FIELDS = 15  # ESP32-C5 / C6 / C61


@dataclass
class CsiFrame:
    seq: int
    mac: str
    rssi: int
    channel: int
    noise_floor: int
    local_timestamp_us: int
    raw: np.ndarray                    # int16 values as printed
    host_time: float = field(default_factory=time.time)

    @property
    def amplitudes(self):
        return amplitudes(self.raw)


def amplitudes(raw):
    """Per-subcarrier amplitude from interleaved (imag, real) pairs."""
    values = np.asarray(raw, dtype=np.float32)
    if values.size % 2:
        values = values[:-1]
    pairs = values.reshape(-1, 2)
    return np.hypot(pairs[:, 0], pairs[:, 1])


class ParseError(ValueError):
    pass


def parse_line(line, host_time=None):
    """Return a CsiFrame, or None for log lines/headers. Raise ParseError if malformed."""
    if isinstance(line, bytes):
        line = line.decode('ascii', errors='replace')
    line = line.strip()
    start = line.find(DATA_PREFIX + ',')
    if start < 0:
        return None
    line = line[start:]
    open_bracket, close_bracket = line.find('"['), line.rfind(']"')
    if open_bracket < 0 or close_bracket < open_bracket:
        raise ParseError('incomplete data array')
    head = line[:open_bracket].rstrip(',').split(',')
    if len(head) not in (LONG_FIELDS - 1, SHORT_FIELDS - 1):
        raise ParseError(f'unexpected field count {len(head) + 1}')
    try:
        values = np.array([int(v) for v in line[open_bracket + 2:close_bracket].split(',') if v.strip()], dtype=np.int16)
        declared_len, first_word = int(head[-2]), int(head[-1])
        seq, mac, rssi = int(head[1]), head[2], int(head[3])
        if len(head) == LONG_FIELDS - 1:
            noise_floor, channel, stamp = int(head[14]), int(head[16]), int(head[18])
        else:
            noise_floor, channel, stamp = int(head[5]), int(head[8]), int(head[9])
    except ValueError as error:
        raise ParseError(str(error)) from None
    # C5/C61 "force LLTF" builds print (len-2)/2 values; others print len values.
    if values.size not in (declared_len, (declared_len - 2) // 2) or values.size < 4:
        raise ParseError(f'data length {values.size} does not match declared {declared_len}')
    if not -110 <= rssi <= 0:
        raise ParseError(f'implausible rssi {rssi}')
    if first_word:
        values = values.copy()
        values[:4] = 0
    return CsiFrame(seq=seq, mac=mac, rssi=rssi, channel=channel, noise_floor=noise_floor,
                    local_timestamp_us=stamp, raw=values,
                    host_time=time.time() if host_time is None else host_time)


def format_line(frame):
    """Serialise a frame in the ESP32 long format (used by the simulator and tests)."""
    head = [DATA_PREFIX, frame.seq, frame.mac, frame.rssi, 11, 1, 0, 0, 1, 0, 1, 0, 0, 0,
            frame.noise_floor, 0, frame.channel, 0, frame.local_timestamp_us, 0, 76, 1,
            int(frame.raw.size), 0]
    return ','.join(str(v) for v in head) + ',"[' + ','.join(str(int(v)) for v in frame.raw) + ']"'


def is_finite_frame(frame):
    amp = frame.amplitudes
    return amp.size > 0 and bool(np.all(np.isfinite(amp))) and not math.isnan(float(amp.mean()))
