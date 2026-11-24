"""Window-level CSI features for room-presence detection.

People change the multipath environment: amplitudes fluctuate over time when the
room is occupied (even seated people breathe and shift) and are steadier when it
is empty. Features therefore focus on *temporal variation* inside a window rather
than absolute level, which drifts with temperature, furniture and router gain.

Processing per window:
1. Stack per-frame subcarrier amplitudes into a (time x subcarrier) matrix.
2. Drop guard/null subcarriers (near-zero mean amplitude).
3. Remove outliers with a per-subcarrier Hampel-style clip (median +- k*MAD).
4. Smooth with a short median filter along time.
5. Normalise each frame by its mean amplitude (removes AGC gain steps).
6. Compute statistics.
"""
import numpy as np
from scipy.signal import medfilt

FEATURES = [
    'packets', 'packet_rate', 'rssi_mean', 'rssi_std',
    'amp_mean', 'amp_std_time', 'amp_cv_time', 'amp_var_time',
    'diff_mean', 'diff_max', 'corr_mean', 'pca1_ratio',
]
# Features that do not depend on window length or absolute gain; used for models.
MODEL_FEATURES = ['rssi_std', 'amp_cv_time', 'amp_var_time', 'diff_mean', 'diff_max', 'corr_mean', 'pca1_ratio']


def _matrix(amplitude_rows):
    width = min(len(a) for a in amplitude_rows)
    return np.vstack([np.asarray(a[:width], dtype=np.float64) for a in amplitude_rows])


def clean(matrix, min_amp=1.0, mad_k=4.0, median_kernel=3):
    keep = matrix.mean(axis=0) > min_amp
    matrix = matrix[:, keep]
    if matrix.shape[1] == 0:
        return matrix
    median = np.median(matrix, axis=0)
    mad = np.median(np.abs(matrix - median), axis=0) * 1.4826 + 1e-9
    matrix = np.clip(matrix, median - mad_k * mad, median + mad_k * mad)
    if matrix.shape[0] >= median_kernel and median_kernel > 1:
        matrix = np.apply_along_axis(medfilt, 0, matrix, median_kernel)
    return matrix


def window_features(times, amplitude_rows, rssi):
    """Compute features for one window. Returns None if the window is unusable."""
    if len(amplitude_rows) < 5:
        return None
    raw = clean(_matrix(amplitude_rows))
    if raw.shape[1] < 4:
        return None
    norm = raw / (raw.mean(axis=1, keepdims=True) + 1e-9)
    span = max(float(times[-1] - times[0]), 1e-3)
    std_t = norm.std(axis=0)
    diffs = np.abs(np.diff(norm, axis=0)).mean(axis=1)
    centred = norm - norm.mean(axis=0)
    # Correlation of each frame with the window's mean profile: drops with motion.
    profile = norm.mean(axis=0)
    corr = [np.corrcoef(row, profile)[0, 1] if row.std() > 0 else 1.0 for row in norm]
    singular = np.linalg.svd(centred, compute_uv=False)
    energy = (singular ** 2).sum()
    rssi = np.asarray(rssi, dtype=np.float64)
    return {
        'packets': float(len(amplitude_rows)),
        'packet_rate': len(amplitude_rows) / span,
        'rssi_mean': float(rssi.mean()),
        'rssi_std': float(rssi.std()),
        'amp_mean': float(raw.mean()),
        'amp_std_time': float(raw.std(axis=0).mean()),
        'amp_cv_time': float(std_t.mean()),
        'amp_var_time': float((std_t ** 2).mean()),
        'diff_mean': float(diffs.mean()),
        'diff_max': float(diffs.max()),
        'corr_mean': float(np.nan_to_num(np.mean(corr), nan=1.0)),
        'pca1_ratio': float(singular[0] ** 2 / energy) if energy > 0 else 0.0,
    }


def windows(frames, window_s, step_s):
    """Yield (start, end, features) for sliding windows over host-timestamped frames.

    ``frames`` is a sequence of (host_time, amplitudes, rssi) sorted by time.
    """
    if not frames:
        return
    times = np.array([f[0] for f in frames])
    start, last = times[0], times[-1]
    while start + window_s <= last + 1e-9:
        lo, hi = np.searchsorted(times, start), np.searchsorted(times, start + window_s)
        chunk = frames[lo:hi]
        feats = window_features([c[0] for c in chunk], [c[1] for c in chunk], [c[2] for c in chunk]) if len(chunk) else None
        if feats is not None:
            yield start, start + window_s, feats
        start += step_s
