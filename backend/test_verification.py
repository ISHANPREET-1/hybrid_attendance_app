"""End-to-end API tests for the hybrid verification layers (guide Step 42).

Scenarios: valid student/device/Wi-Fi/CSI; unregistered and replaced devices;
wrong Wi-Fi; CSI ABSENT, UNKNOWN, stale and missing; unauthenticated sensors;
closed sessions; duplicates; teacher visibility of verification failures.
"""
import json
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone

from backend import test_server
from backend.test_server import Client

PHONE_A = dict(install_uuid=str(uuid.uuid4()), device_hash='a' * 64, platform='android', model='Pixel 7')
PHONE_B = dict(install_uuid=str(uuid.uuid4()), device_hash='b' * 64, platform='android', model='Galaxy A52')
WIFI_OK = dict(wifi_ssid='"ATTENDANCE_WIFI"', wifi_permission='granted')


class VerificationTests(test_server.ApiTests):
    # Reuse the fixture (admin, teacher, two enrolled students, course in "Lab 3B")
    # without re-running the original suite's tests under this class.
    test_full_workflow_reports_export_and_isolation = None
    test_anonymous_csrf_origin_role_and_course_permissions = None
    test_device_approval_wrong_code_closure_and_concurrent_duplicates = None
    test_geofence_network_expiry_and_roster_snapshot = None
    test_password_reset_change_and_revocation = None
    test_persistence_across_restart_and_input_validation = None
    test_invitation_binding_reuse_and_rate_limit = None
    test_scheduling_cancellation_and_class_editing = None
    test_static_host_health_and_legacy_endpoint_closed = None

    def sensor(self, room='Lab 3B'):
        status, result = self.admin.request('csi/sensors', dict(name='ESP32 bench', room=room))
        self.assertEqual(status, 200, result)
        return result['token']

    def post_csi(self, token, status='PRESENT', stamp=None, **extra):
        body = dict(status=status, timestamp=stamp if stamp is not None else
                    datetime.now(timezone.utc).isoformat(), **extra)
        headers = {'Content-Type': 'application/json'}
        if token is not None:
            headers['Authorization'] = 'Bearer ' + token
        request = urllib.request.Request(self.url + '/api/csi/verification', data=json.dumps(body).encode(), headers=headers)
        try:
            response = urllib.request.urlopen(request, timeout=10)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.loads(response.read())

    def approve_phone(self, client, phone):
        status, result = client.request('devices/request', dict(label='Phone', **phone))
        self.assertEqual(status, 200, result)
        device = self.state(client)['devices'][0]
        self.assertEqual(device['platform'], 'android')
        self.assertEqual(self.admin.request('devices/review', dict(device_id=device['id'], status='approved'))[0], 200)
        return device['id']

    def checkin(self, sid, phone=PHONE_A, wifi=WIFI_OK, client=None, **extra):
        return (client or self.student).request('attendance', dict(session_id=sid, **phone, **wifi, **extra))

    def full_session(self):
        token = self.sensor()
        self.approve_phone(self.student, PHONE_A)
        sid, _ = self.open_session(code_required=False, wifi_required=True, csi_required=True, csi_max_age_s=30)
        return token, sid

    def test_sensor_authentication_and_payload_validation(self):
        token = self.sensor()
        self.assertEqual(self.post_csi(None)[0], 401)
        self.assertEqual(self.post_csi('forged-token')[0], 401)
        self.assertEqual(self.post_csi(token, 'MAYBE')[0], 422)
        self.assertEqual(self.post_csi(token, stamp='yesterday')[0], 422)
        self.assertEqual(self.post_csi(token, stamp=time.time() + 120)[0], 422)
        self.assertEqual(self.post_csi(token, confidence=1.7)[0], 422)
        status, result = self.post_csi(token, stamp=time.time() - 300)
        self.assertEqual(status, 422)
        self.assertIn('stale', result['error'])
        status, result = self.post_csi(token, confidence=0.91, packets=480, window_s=5)
        self.assertEqual(status, 200, result)
        self.assertEqual(result['room'], 'Lab 3B')
        # Students cannot provision sensors, and revoked sensors are refused.
        self.assertEqual(self.student.request('csi/sensors', dict(name='x', room='Lab 3B'))[0], 403)
        sensor_id = self.state(self.admin)['csi_sensors'][0]['id']
        self.assertEqual(self.admin.request('csi/sensors/revoke', dict(sensor_id=sensor_id))[0], 200)
        self.assertEqual(self.post_csi(token)[0], 401)

    def test_csi_session_binding(self):
        other_room = self.sensor('Room 204')
        token = self.sensor()
        sid, _ = self.open_session(csi_required=True)
        self.assertEqual(self.post_csi(token, session_id=sid)[0], 200)
        self.assertEqual(self.post_csi(other_room, session_id=sid)[0], 403)
        self.assertEqual(self.post_csi(token, session_id='nope')[0], 404)
        self.teacher.request('sessions/close', dict(session_id=sid))
        self.assertEqual(self.post_csi(token, session_id=sid)[0], 409)

    def test_csi_required_needs_a_sensor_in_the_room(self):
        status, result = self.teacher.request('sessions/open', dict(course_id=self.course_id, csi_required=True))
        self.assertEqual(status, 400)
        self.assertIn('CSI sensor', result['error'])
        status, _ = self.teacher.request('sessions/open', dict(course_id=self.course_id, code_required=False))
        self.assertEqual(status, 400)  # at least one presence check is mandatory

    def test_all_layers_pass_and_duplicate_returns_existing(self):
        token, sid = self.full_session()
        self.assertEqual(self.post_csi(token, confidence=0.9)[0], 200)
        status, result = self.checkin(sid)
        self.assertEqual(status, 200, result)
        self.assertEqual(result['outcome'], 'VERIFIED')
        self.assertEqual({c['name']: c['status'] for c in result['checks']},
                         dict(identity='pass', session='pass', device='pass', wifi='pass', csi='pass'))
        status, again = self.checkin(sid)
        self.assertEqual(status, 200)
        self.assertTrue(again['duplicate'])
        report = self.state(self.teacher)['reports']
        self.assertEqual(sum(r['attendance_status'] == 'Present' for r in report), 1)

    def test_csi_unavailable_unknown_stale_and_absent(self):
        token, sid = self.full_session()
        status, result = self.checkin(sid)  # no reading yet
        self.assertEqual((status, result['outcome']), (202, 'PENDING'))
        self.post_csi(token, 'UNKNOWN', error='serial disconnected')
        status, result = self.checkin(sid)
        self.assertEqual((status, result['outcome']), (202, 'PENDING'))
        self.post_csi(token, 'ABSENT', confidence=0.8)
        status, result = self.checkin(sid)
        self.assertEqual((status, result['outcome']), (403, 'REJECTED'))
        # The newest reading is PRESENT, but it ages past the session's freshness window.
        self.post_csi(token, 'PRESENT')
        with self.server.service.engine.begin() as conn:
            from sqlalchemy import update
            from backend.database import session_policy, csi_readings
            conn.execute(update(csi_readings).values(measured_at=csi_readings.c.measured_at - 25))
            conn.execute(update(session_policy).values(csi_max_age_s=10))
        status, result = self.checkin(sid)
        self.assertEqual((status, result['outcome']), (202, 'PENDING'))
        self.assertIn('stale', result['message'])
        self.assertEqual(self.state(self.student)['reports'][0]['attendance_status'], 'Pending')
        # Teacher sees each attempt and the room state; the CSI state never names a student.
        teacher = self.state(self.teacher)
        self.assertEqual([c['outcome'] for c in teacher['checks']], ['PENDING', 'REJECTED', 'PENDING', 'PENDING'])
        self.assertEqual(teacher['csi_rooms'][0]['room'], 'Lab 3B')

    def test_late_or_stale_reading_never_overrides_fresh_one(self):
        token, sid = self.full_session()
        self.assertEqual(self.post_csi(token, 'PRESENT')[0], 200)
        self.assertEqual(self.post_csi(token, 'ABSENT', stamp=time.time() - 120)[0], 422)  # rejected stale
        self.assertEqual(self.post_csi(token, 'ABSENT', stamp=time.time() - 8)[0], 200)    # late arrival
        status, result = self.checkin(sid)
        self.assertEqual((status, result['outcome']), (200, 'VERIFIED'), result)

    def test_replayed_csi_data_is_not_live_evidence(self):
        token, sid = self.full_session()
        self.post_csi(token, 'PRESENT', error='REPLAY: offline recorded data')
        status, result = self.checkin(sid)
        self.assertEqual((status, result['outcome']), (202, 'PENDING'))
        self.assertIn('replayed', result['message'])

    def test_wrong_or_unreadable_wifi_rejected(self):
        token, sid = self.full_session()
        self.post_csi(token)
        for wifi in (dict(wifi_ssid='Home-WiFi'), dict(wifi_ssid='<unknown ssid>'),
                     dict(wifi_permission='denied'), {}):
            status, result = self.checkin(sid, wifi=wifi)
            self.assertEqual((status, result['outcome']), (403, 'REJECTED'), wifi)
            self.assertEqual(next(c for c in result['checks'] if c['name'] == 'wifi')['status'], 'fail')
        self.assertEqual(self.checkin(sid)[0], 200)

    def test_device_identity_binding_and_replacement(self):
        token, sid = self.full_session()
        self.post_csi(token)
        # Another phone, or the same phone after a reinstall, is not the approved device.
        self.assertEqual(self.checkin(sid, phone=PHONE_B)[0], 403)
        reinstall = dict(PHONE_A, install_uuid=str(uuid.uuid4()))
        status, result = self.checkin(sid, phone=reinstall)
        self.assertEqual(status, 403)
        self.assertIn('reinstalled', result['error'])
        self.assertEqual(self.checkin(sid, phone={})[0], 403)  # identity omitted
        self.assertEqual(self.checkin(sid, phone=dict(install_uuid='x', device_hash='y'))[0], 403)
        # A second student cannot register a phone bound to the first student.
        self.assertEqual(self.other.request('devices/request', dict(label='Borrowed', **PHONE_A))[0], 409)
        # Unregistered device (no approval at all) is rejected.
        status, result = self.checkin(sid, client=self.other, phone=PHONE_B)
        self.assertEqual((status, result['outcome']), (403, 'REJECTED'))
        # Admin-approved replacement: a fresh install requests approval and the old one is revoked.
        fresh = Client(self.url)
        fresh.request('auth/login', dict(email='student@college.test', password='Strong attendance password 2026!'))
        self.approve_phone(fresh, PHONE_B)
        self.assertEqual(self.checkin(sid, client=fresh, phone=PHONE_B)[0], 200)
        devices = {d['model']: d['status'] for d in self.state(self.admin)['devices'] if d['model']}
        self.assertEqual(devices, {'Pixel 7': 'revoked', 'Galaxy A52': 'approved'})

    def test_identity_added_to_old_approval_requires_review(self):
        token = self.sensor()
        self.approve(self.student)  # approved before the app sent identity
        sid, _ = self.open_session(code_required=False, csi_required=True)
        self.post_csi(token)
        self.assertEqual(self.checkin(sid, wifi={})[0], 403)  # identity now supplied, none stored
        self.assertEqual(self.student.request('devices/request', dict(label='Phone', **PHONE_A))[0], 200)
        device = self.state(self.student)['devices'][0]
        self.assertEqual((device['status'], device['platform']), ('pending', 'android'))
        self.assertEqual(self.admin.request('devices/review', dict(device_id=device['id'], status='approved'))[0], 200)
        self.assertEqual(self.checkin(sid, wifi={})[0], 200)

    def test_missing_code_is_a_logged_rejection(self):
        self.approve(self.student)
        sid, _ = self.open_session()
        status, result = self.student.request('attendance', dict(session_id=sid))
        self.assertEqual((status, result['outcome']), (403, 'REJECTED'))
        self.assertEqual(self.state(self.teacher)['checks'][0]['outcome'], 'REJECTED')

    def test_closed_session_rejected_and_logged(self):
        token, sid = self.full_session()
        self.post_csi(token)
        self.teacher.request('sessions/close', dict(session_id=sid))
        status, result = self.checkin(sid)
        self.assertEqual((status, result['outcome']), (409, 'REJECTED'))
        self.assertEqual(self.state(self.teacher)['checks'][0]['outcome'], 'REJECTED')

    def test_legacy_sessions_and_browser_flow_unchanged(self):
        # Code-only sessions with an approved browser still work exactly as before.
        self.approve(self.student)
        sid, code = self.open_session()
        status, result = self.student.request('attendance', dict(session_id=sid, code=code))
        self.assertEqual(status, 200, result)
        self.assertEqual(result['outcome'], 'VERIFIED')


if __name__ == '__main__':
    import unittest
    unittest.main()
