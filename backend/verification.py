"""Hybrid verification layers: device identity, Wi-Fi, and CSI room presence.

Each check returns a dict ``{name, status, detail}`` where status is one of
``pass``, ``fail`` (attendance REJECTED) or ``pending`` (attendance PENDING; the
student may retry). The backend, never the app, makes the final decision.

CSI is room-level occupancy only: it never identifies a student, so it is
combined with the per-student identity and device checks, never used alone.
"""
import json
import os
import re
import time
from datetime import datetime

from sqlalchemy import select, insert, update, or_

from .database import (csi_sensors, csi_readings, device_identity,
                       session_policy, attendance_checks, class_sessions, courses)

CSI_STATES = ('PRESENT', 'ABSENT', 'UNKNOWN')
UUID_RE = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
HASH_RE = re.compile(r'^[0-9a-f]{64}$')
# Measurements further in the future than this are treated as clock errors.
CLOCK_SKEW_S = 10


def default_ssid():
    return os.getenv('ATTENDANCE_SSID', 'ATTENDANCE_WIFI')


def default_csi_max_age():
    try:
        return max(5, min(600, int(os.getenv('CSI_MAX_AGE_S', '30'))))
    except ValueError:
        return 30


def check(name, status, detail):
    return {'name': name, 'status': status, 'detail': detail}


def parse_timestamp(value):
    """Accept epoch seconds or an ISO-8601 string with a timezone."""
    if isinstance(value, bool):
        raise ValueError()
    if isinstance(value, (int, float)):
        stamp = float(value)
    elif isinstance(value, str) and len(value) <= 40:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if parsed.tzinfo is None:
            raise ValueError()
        stamp = parsed.timestamp()
    else:
        raise ValueError()
    if not 1_600_000_000 < stamp < 4_000_000_000:
        raise ValueError()
    return stamp


def normalize_ssid(value):
    """Android may wrap SSIDs in quotes and returns '<unknown ssid>' without permission."""
    if not isinstance(value, str):
        return None
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    if not value or value.lower() in ('<unknown ssid>', 'unknown', '0x'):
        return None
    return value[:64]


def identity_from(data):
    """Validated native-app identity, or None for browsers that cannot supply it."""
    install, hashed = data.get('install_uuid'), data.get('device_hash')
    if install is None and hashed is None:
        return None
    if not isinstance(install, str) or not isinstance(hashed, str):
        raise ValueError('install_uuid and device_hash must both be supplied')
    install, hashed = install.strip().lower(), hashed.strip().lower()
    if not UUID_RE.fullmatch(install) or not HASH_RE.fullmatch(hashed):
        raise ValueError('Device identity is malformed')
    platform = data.get('platform', 'android')
    model = data.get('model', '')
    if not isinstance(platform, str) or not isinstance(model, str):
        raise ValueError('Device identity is malformed')
    return {'install_uuid': install, 'device_hash': hashed,
            'platform': platform.strip()[:20] or 'android', 'model': model.strip()[:120]}


def policy_for(conn, session_id):
    row = conn.execute(select(session_policy).where(session_policy.c.session_id == session_id)).mappings().first()
    if row:
        return dict(row)
    # Sessions created before v3 keep their original behaviour.
    return {'session_id': session_id, 'code_required': 1, 'wifi_required': 0,
            'wifi_ssid': '', 'csi_required': 0, 'csi_max_age_s': default_csi_max_age()}


def active_sensor_count(conn, room):
    if not room:
        return 0
    return len(conn.execute(select(csi_sensors.c.id).where(
        csi_sensors.c.room == room, csi_sensors.c.active == 1)).all())


def latest_reading(conn, room):
    # Newest by *measurement* time, so a late-arriving old reading never overrides a
    # newer one; readings rejected as stale are kept for diagnosis but never used.
    query = select(csi_readings).join(csi_sensors, csi_sensors.c.id == csi_readings.c.sensor_id).where(
        csi_readings.c.room == room, csi_sensors.c.active == 1,
        or_(csi_readings.c.error.is_(None), ~csi_readings.c.error.like('stale:%'))).order_by(
        csi_readings.c.measured_at.desc(), csi_readings.c.received_at.desc()).limit(1)
    row = conn.execute(query).mappings().first()
    return dict(row) if row else None


def device_check(conn, device, data):
    """The approved device record must match the identity the app reports."""
    if not device:
        return check('device', 'fail', 'This device needs administrator approval. Request it in Devices.'), None
    stored = conn.execute(select(device_identity).where(device_identity.c.device_id == device['id'])).mappings().first()
    try:
        supplied = identity_from(data)
    except ValueError as error:
        return check('device', 'fail', str(error)), None
    if stored is None:
        if supplied is not None:
            return check('device', 'fail', 'This approval belongs to a browser. Request approval from the app.'), None
        return check('device', 'pass', 'Approved browser'), None
    if supplied is None:
        return check('device', 'fail', 'Check in from the registered app on your approved phone.'), None
    if supplied['device_hash'] != stored['device_hash']:
        return check('device', 'fail', 'This phone is not your approved device.'), None
    if supplied['install_uuid'] != stored['install_uuid']:
        return check('device', 'fail', 'The app was reinstalled. Request device approval again.'), None
    return check('device', 'pass', 'Registered device verified'), supplied


def wifi_check(policy, data):
    if not policy['wifi_required']:
        return check('wifi', 'pass', 'Not required for this session'), None
    expected = policy['wifi_ssid'] or default_ssid()
    if data.get('wifi_permission') == 'denied':
        return check('wifi', 'fail', 'Allow location/nearby-devices permission so the app can read the Wi-Fi name.'), None
    ssid = normalize_ssid(data.get('wifi_ssid'))
    if ssid is None:
        return check('wifi', 'fail', f'Connect to {expected}. The Wi-Fi name could not be read on this device.'), None
    if ssid != expected:
        return check('wifi', 'fail', f'Connected to "{ssid}", not {expected}.'), ssid
    return check('wifi', 'pass', f'Connected to {expected}'), ssid


def csi_check(conn, policy, session, room, now=None):
    now = time.time() if now is None else now
    if not policy['csi_required']:
        return check('csi', 'pass', 'Not required for this session'), None
    reading = latest_reading(conn, room) if room else None
    if not reading:
        return check('csi', 'pending', 'Room sensor has not reported yet. Try again shortly.'), None
    age = now - reading['measured_at']
    if age > policy['csi_max_age_s']:
        return check('csi', 'pending', f'Room sensor data is stale ({int(age)} s old). Try again shortly.'), reading
    if reading['measured_at'] < session['starts_at'] - policy['csi_max_age_s']:
        return check('csi', 'pending', 'No room reading since the session started.'), reading
    if (reading['error'] or '').startswith('REPLAY') and os.getenv('CSI_ALLOW_REPLAY') != 'true':
        return check('csi', 'pending', 'Room sensor is sending replayed test data, not live measurements.'), reading
    if reading['status'] == 'UNKNOWN':
        return check('csi', 'pending', 'Room presence is uncertain right now. Try again shortly.'), reading
    if reading['status'] == 'ABSENT':
        return check('csi', 'fail', 'The room sensor does not detect occupancy.'), reading
    return check('csi', 'pass', 'Room presence verified'), reading


def outcome_of(checks):
    if any(c['status'] == 'fail' for c in checks):
        return 'REJECTED'
    if any(c['status'] == 'pending' for c in checks):
        return 'PENDING'
    return 'VERIFIED'


def record_check(engine, session_id, student_id, outcome, reason, checks, reading=None, ssid=None):
    """Persist an attempt in its own transaction so rejected attempts are kept."""
    from .service import uid
    with engine.begin() as conn:
        conn.execute(insert(attendance_checks).values(id=uid(), session_id=session_id or '', student_id=student_id,
            outcome=outcome, reason=reason[:300], checks=json.dumps(checks)[:2000],
            csi_reading_id=reading['id'] if reading else None, wifi_ssid=ssid, created_at=time.time()))


def ingest_reading(engine, token, data, now=None):
    """Validate and store a processed CSI result from an authenticated sensor."""
    from .service import ApiError, digest, uid
    now = time.time() if now is None else now
    if not token:
        raise ApiError('Sensor token required', 401)
    with engine.begin() as conn:
        sensor = conn.execute(select(csi_sensors).where(csi_sensors.c.token_hash == digest(token),
            csi_sensors.c.active == 1)).mappings().first()
        if not sensor:
            raise ApiError('Sensor token is invalid or revoked', 401)
        status = data.get('status')
        if status not in CSI_STATES:
            raise ApiError('status must be PRESENT, ABSENT or UNKNOWN', 422)
        try:
            measured = parse_timestamp(data.get('timestamp'))
        except (ValueError, TypeError):
            raise ApiError('timestamp must be ISO-8601 with timezone or epoch seconds', 422)
        if measured > now + CLOCK_SKEW_S:
            raise ApiError('timestamp is in the future; check the processing host clock', 422)
        confidence = data.get('confidence')
        if confidence is not None:
            if isinstance(confidence, bool) or not isinstance(confidence, (int, float)) or not 0 <= confidence <= 1:
                raise ApiError('confidence must be between 0 and 1', 422)
            confidence = float(confidence)
        packets, window = data.get('packets'), data.get('window_s')
        if packets is not None and (isinstance(packets, bool) or not isinstance(packets, int) or not 0 <= packets <= 10**7):
            raise ApiError('packets must be a non-negative integer', 422)
        if window is not None and (isinstance(window, bool) or not isinstance(window, (int, float)) or not 0 < window <= 3600):
            raise ApiError('window_s must be between 0 and 3600', 422)
        error = data.get('error')
        if error is not None and (not isinstance(error, str) or len(error) > 200):
            raise ApiError('error must be a short string', 422)
        session_id = data.get('session_id')
        if session_id is not None:
            if not isinstance(session_id, str) or len(session_id) > 40:
                raise ApiError('session_id is invalid', 422)
            session = conn.execute(select(class_sessions.c.id, class_sessions.c.status, class_sessions.c.starts_at,
                class_sessions.c.ends_at, courses.c.room).join(courses, courses.c.id == class_sessions.c.course_id).where(
                class_sessions.c.id == session_id)).mappings().first()
            if not session:
                raise ApiError('Session not found', 404)
            if session['room'] != sensor['room']:
                raise ApiError('This sensor is not installed in that session\'s room', 403)
            if session['status'] not in ('open', 'scheduled') or not session['starts_at'] <= now < session['ends_at']:
                raise ApiError('Session is not active', 409)
        max_age = default_csi_max_age()
        stale = now - measured > max_age
        reading = dict(id=uid(), sensor_id=sensor['id'], room=sensor['room'], session_id=session_id,
            status=status, measured_at=measured, received_at=now, confidence=confidence,
            packets=packets, window_s=float(window) if window is not None else None,
            error=error if not stale else f'stale: measured {int(now - measured)} s ago')
        # Stale readings are still logged for diagnosis; csi_check() never accepts them.
        conn.execute(insert(csi_readings).values(**reading))
        conn.execute(update(csi_sensors).where(csi_sensors.c.id == sensor['id']).values(last_seen_at=now))
    if stale:
        raise ApiError(f'Measurement is stale (older than {max_age} s); recorded but not usable', 422)
    return {'accepted': True, 'id': reading['id'], 'room': sensor['room'], 'status': status}


def room_status(conn, rooms, now=None):
    """Latest CSI state per room, summarised for staff dashboards."""
    now = time.time() if now is None else now
    result = {}
    for room in sorted({r for r in rooms if r}):
        sensors = active_sensor_count(conn, room)
        if not sensors:
            continue
        reading = latest_reading(conn, room)
        if not reading:
            result[room] = {'room': room, 'status': 'UNKNOWN', 'fresh': False, 'age_s': None,
                            'confidence': None, 'detail': 'No readings yet'}
            continue
        age = now - reading['measured_at']
        fresh = age <= default_csi_max_age()
        result[room] = {'room': room, 'status': reading['status'] if fresh else 'UNKNOWN', 'fresh': fresh,
                        'age_s': round(age, 1), 'confidence': reading['confidence'],
                        'detail': reading['error'] or ('' if fresh else 'Stale data')}
    return list(result.values())
