"""Turn a stream of CSI frames into PRESENT / ABSENT / UNKNOWN (guide Step 16).

UNKNOWN is returned whenever the evidence is not good enough: no recent packets
(ESP32, router or serial link down), too few packets in the window, unusable
data, model confidence below the trained threshold, or no majority among recent
decisions. UNKNOWN is never converted to PRESENT.
"""
from collections import Counter, deque
from dataclasses import dataclass
from typing import Optional

import joblib
import numpy as np

from .features import window_features


@dataclass
class Result:
    status: str
    measured_at: float
    confidence: Optional[float]
    packets: int
    window_s: float
    error: Optional[str] = None

    def payload(self, session_id=None, source=None):
        body = {'status': self.status, 'timestamp': self.measured_at, 'packets': self.packets,
                'window_s': self.window_s}
        if self.confidence is not None:
            body['confidence'] = round(float(self.confidence), 4)
        error = '; '.join(e for e in (source, self.error) if e)
        if error:
            body['error'] = error[:200]
        if session_id:
            body['session_id'] = session_id
        return body


class Detector:
    def __init__(self, bundle, stale_s=2.0, consensus=3):
        if isinstance(bundle, str):
            bundle = joblib.load(bundle)
        self.bundle = bundle
        self.model, self.features = bundle['model'], bundle['features']
        self.window_s = float(bundle['window_s'])
        self.min_confidence = float(bundle.get('min_confidence', 0.7))
        self.min_packet_rate = float(bundle.get('min_packet_rate', 5.0))
        self.stale_s = stale_s
        self.frames = deque()
        self.recent = deque(maxlen=max(1, consensus))

    def add(self, host_time, amplitudes, rssi):
        self.frames.append((host_time, amplitudes, rssi))

    def _trim(self, now):
        while self.frames and self.frames[0][0] < now - self.window_s:
            self.frames.popleft()

    def evaluate(self, now):
        self._trim(now)
        packets = len(self.frames)

        def unknown(reason, at=None):
            self.recent.append('UNKNOWN')
            return Result('UNKNOWN', at if at is not None else now, None, packets, self.window_s, reason)

        if not packets or now - self.frames[-1][0] > self.stale_s:
            return unknown('no CSI packets received (check ESP32, router and serial link)')
        last = self.frames[-1][0]
        rate = packets / self.window_s
        if rate < self.min_packet_rate:
            return unknown(f'too few packets ({rate:.1f}/s < {self.min_packet_rate:.1f}/s)', last)
        feats = window_features([f[0] for f in self.frames], [f[1] for f in self.frames], [f[2] for f in self.frames])
        if feats is None:
            return unknown('window unusable after cleaning', last)
        x = np.array([[feats[name] for name in self.features]])
        if not np.all(np.isfinite(x)):
            return unknown('non-finite features', last)
        p = float(self.model.predict_proba(x)[0, 1])
        confidence = max(p, 1 - p)
        if confidence < self.min_confidence:
            return unknown(f'low confidence {confidence:.2f}', last)
        state = 'PRESENT' if p >= 0.5 else 'ABSENT'
        self.recent.append(state)
        votes = Counter(self.recent)
        winner, count = votes.most_common(1)[0]
        if winner != state or count <= len(self.recent) // 2:
            return Result('UNKNOWN', last, None, packets, self.window_s, 'recent windows disagree')
        return Result(state, last, confidence, packets, self.window_s)
