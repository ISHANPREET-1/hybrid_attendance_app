import concurrent.futures
import http.cookiejar
import json
import os
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest.mock import patch

from sqlalchemy import select, update
from backend.server import create_server
from backend.database import class_sessions, users, auth_sessions
from backend.service import code_for

PASSWORD = 'Strong attendance password 2026!'


class Client:
    def __init__(self, url):
        self.url, self.csrf = url, ''
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))

    def request(self, path, data=None, csrf=True, origin=None, raw=False):
        headers = {'Content-Type': 'application/json'}
        if csrf:
            headers['X-CSRF-Token'] = self.csrf
        if origin:
            headers['Origin'] = origin
        request = urllib.request.Request(self.url + '/api/' + path,
            data=json.dumps(data).encode() if data is not None else None, headers=headers)
        try:
            response = self.opener.open(request, timeout=25)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            text = response.read().decode('utf-8-sig')
            result = text if raw else json.loads(text)
            if isinstance(result, dict) and result.get('csrf'):
                self.csrf = result['csrf']
            return response.status, result


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / 'test.sqlite3'
        self.web = Path(self.temp.name) / 'web'
        self.server = create_server(0, self.db, self.web, setup_token='private-setup-token')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.admin, self.teacher, self.student, self.other = [Client(self.url) for _ in range(4)]
        status, result = self.admin.request('auth/setup', dict(email='admin@college.test', name='Admin', password=PASSWORD, setup_token='private-setup-token'))
        self.assertEqual(status, 200, result)
        status, result = self.admin.request('invitations', dict(email='teacher@college.test', role='teacher', purpose='signup'))
        self.assertEqual(status, 200, result)
        status, result = self.teacher.request('auth/register', dict(email='teacher@college.test', name='Teacher', password=PASSWORD, invitation=result['token']))
        self.assertEqual(status, 200, result)
        self.teacher_id = result['user']['id']
        status, result = self.student.request('auth/register', dict(email='student@college.test', name='Student One', password=PASSWORD, roll_no='CS001', role='admin'))
        self.assertEqual(status, 200, result)
        self.student_id = result['user']['id']
        self.assertEqual(result['user']['role'], 'student')
        self.assertEqual(self.other.request('auth/register', dict(email='other@college.test', name='Student Two', password=PASSWORD, roll_no='CS002'))[0], 200)
        self.assertEqual(self.teacher.request('courses', dict(code='OS101', title='Operating Systems', room='Lab 3B'))[0], 200)
        self.course_id = self.teacher.request('state')[1]['courses'][0]['id']
        for address in ['student@college.test', 'other@college.test']:
            self.assertEqual(self.teacher.request('roster/add', dict(course_id=self.course_id, email=address))[0], 200)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.server.service.engine.dispose()
        self.temp.cleanup()

    def state(self, client):
        status, result = client.request('state')
        self.assertEqual(status, 200, result)
        return result

    def open_session(self, **extra):
        status, result = self.teacher.request('sessions/open', dict(course_id=self.course_id, minutes=15, **extra))
        self.assertEqual(status, 200, result)
        session = self.state(self.teacher)['sessions'][0]
        return session['id'], session.get('code')

    def approve(self, client):
        status, result = client.request('devices/request', {'label': 'Test browser'})
        self.assertEqual(status, 200, result)
        device = self.state(client)['devices'][0]
        self.assertEqual(self.admin.request('devices/review', dict(device_id=device['id'], status='approved'))[0], 200)
        return device['id']

    def test_full_workflow_reports_export_and_isolation(self):
        self.approve(self.student)
        sid, code = self.open_session()
        student_state = self.state(self.student)
        self.assertNotIn('code', student_state['sessions'][0])
        self.assertNotIn('code_secret', student_state['sessions'][0])
        self.assertEqual(student_state['reports'][0]['attendance_status'], 'Pending')
        self.assertEqual(len(student_state['roster']), 1)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code, rollNo='CS002'))[0], 200)
        self.assertEqual(self.teacher.request('sessions/close', dict(session_id=sid))[0], 200)
        report = self.state(self.teacher)['reports']
        self.assertEqual({r['roll_no']: r['attendance_status'] for r in report}, {'CS001': 'Present', 'CS002': 'Absent'})
        self.assertEqual(len(self.state(self.student)['reports']), 1)
        status, csv = self.teacher.request('reports.csv', raw=True)
        self.assertEqual(status, 200)
        self.assertIn('Absent', csv)
        self.assertIn('Present', csv)
        self.assertEqual(self.teacher.request('notices', dict(course_id=self.course_id, body='Bring your lab notebook'))[0], 200)
        self.assertEqual(self.state(self.student)['notices'][0]['body'], 'Bring your lab notebook')
        self.assertEqual(self.student.request('profile', dict(name='New Name', department='CS', mobile='1234567890'))[0], 200)
        self.assertEqual(self.state(self.student)['user']['name'], 'New Name')

    def test_anonymous_csrf_origin_role_and_course_permissions(self):
        anonymous = Client(self.url)
        self.assertEqual(anonymous.request('state')[0], 401)
        self.assertEqual(anonymous.request('attendance')[0], 401)
        self.assertEqual(self.student.request('courses', {}, csrf=False)[0], 403)
        self.assertEqual(self.student.request('courses', {}, origin='https://evil.test')[0], 403)
        self.assertEqual(self.student.request('courses', dict(code='X', title='X'))[0], 403)
        self.assertEqual(self.teacher.request('invitations', dict(email='evil@test.com', role='admin', purpose='signup'))[0], 403)
        self.assertEqual(self.student.request('devices/review', dict(device_id='x', status='approved'))[0], 403)
        # Give a second teacher a valid account: ownership still restricts their actions.
        token = self.admin.request('invitations', dict(email='teacher2@college.test', role='teacher', purpose='signup'))[1]['token']
        stranger = Client(self.url)
        self.assertEqual(stranger.request('auth/register', dict(email='teacher2@college.test', name='Stranger', invitation=token, password=PASSWORD))[0], 200)
        self.assertEqual(self.state(stranger)['courses'], [])
        self.assertEqual(stranger.request('roster/add', dict(course_id=self.course_id, email='student@college.test'))[0], 403)
        self.assertEqual(stranger.request('sessions/open', dict(course_id=self.course_id))[0], 403)
        self.assertEqual(self.admin.request('auth/setup', dict(email='second@college.test', name='Admin', password=PASSWORD, setup_token='private-setup-token'))[0], 409)
        for cookie in self.admin.jar:
            self.assertTrue(cookie.has_nonstandard_attr('HttpOnly'))

    def test_device_approval_wrong_code_closure_and_concurrent_duplicates(self):
        sid, code = self.open_session()
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 403)
        device_id = self.approve(self.student)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code='wrong!'))[0], 403)
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.student.request('attendance', dict(session_id=sid, code=code)), range(6)))
        self.assertEqual([status for status, _ in results], [200] * 6, results)
        report = self.state(self.teacher)['reports']
        self.assertEqual(sum(r['attendance_status'] == 'Present' for r in report), 1)
        self.assertEqual(self.admin.request('devices/review', dict(device_id=device_id, status='revoked'))[0], 200)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 403)
        self.assertEqual(self.teacher.request('sessions/close', dict(session_id=sid))[0], 200)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 409)

    def test_geofence_network_expiry_and_roster_snapshot(self):
        self.approve(self.student)
        sid, code = self.open_session(latitude=28.6, longitude=77.2, radius_m=150)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 403)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code, latitude=30, longitude=77, accuracy=5))[0], 403)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code, latitude=28.6, longitude=77.2, accuracy=500))[0], 403)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code, latitude=28.6, longitude=77.2, accuracy=5))[0], 200)
        self.teacher.request('sessions/close', dict(session_id=sid))
        self.assertEqual(self.teacher.request('roster/remove', dict(course_id=self.course_id, email='other@college.test'))[0], 200)
        self.assertEqual(len(self.state(self.teacher)['reports']), 2)  # Past roster kept.
        with patch.dict(os.environ, {'CAMPUS_CIDRS': '203.0.113.0/24'}):
            sid, code = self.open_session(network_required=True)
            self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 403)
        with patch.dict(os.environ, {'CAMPUS_CIDRS': '127.0.0.0/8'}):
            self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 200)
        self.teacher.request('sessions/close', dict(session_id=sid))
        sid, _ = self.open_session()
        with self.server.service.engine.begin() as conn:
            row = conn.execute(select(class_sessions).where(class_sessions.c.id == sid)).mappings().one()
            old_code = code_for(dict(row), time.time() - 120)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=old_code))[0], 403)
        with self.server.service.engine.begin() as conn:
            conn.execute(update(class_sessions).where(class_sessions.c.id == sid).values(ends_at=time.time() - 1))
        self.assertEqual(self.state(self.teacher)['sessions'][0]['status'], 'closed')
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code='123456'))[0], 409)

    def test_password_reset_change_and_revocation(self):
        reset = self.admin.request('invitations', dict(email='student@college.test', role='student', purpose='reset'))[1]['token']
        anonymous = Client(self.url)
        new_password = 'New stronger password 2026!'
        self.assertEqual(anonymous.request('auth/reset', dict(token=reset, password=new_password))[0], 200)
        self.assertEqual(self.student.request('state')[0], 401)
        self.assertEqual(anonymous.request('auth/reset', dict(token=reset, password=new_password))[0], 400)
        self.assertEqual(self.student.request('auth/login', dict(email='student@college.test', password=PASSWORD))[0], 401)
        self.assertEqual(self.student.request('auth/login', dict(email='student@college.test', password=new_password))[0], 200)
        self.assertEqual(self.student.request('password', dict(current_password=new_password, password=PASSWORD))[0], 200)
        self.assertEqual(self.student.request('state')[0], 401)
        self.assertEqual(self.student.request('auth/login', dict(email='student@college.test', password=PASSWORD))[0], 200)
        self.assertEqual(self.student.request('auth/logout', {})[0], 200)
        self.assertEqual(self.student.request('state')[0], 401)
        with self.server.service.engine.connect() as conn:
            hashed = conn.execute(select(users.c.password_hash).where(users.c.id == self.student_id)).scalar()
            self.assertTrue(hashed.startswith('$argon2id$'))

    def test_persistence_across_restart_and_input_validation(self):
        self.approve(self.student)
        sid, code = self.open_session()
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code=code))[0], 200)
        self.assertEqual(self.teacher.request('sessions/open', dict(course_id=self.course_id))[0], 409)
        self.assertEqual(self.student.request('auth/register', dict(email='bad', name='X', password='short', roll_no='X'))[0], 400)
        self.server.shutdown(); self.server.server_close(); self.thread.join(); self.server.service.engine.dispose()
        self.server = create_server(0, self.db, self.web, setup_token='private-setup-token')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.student.url = f'http://127.0.0.1:{self.server.server_port}'
        self.assertEqual(self.state(self.student)['reports'][0]['attendance_status'], 'Present')

    def test_invitation_binding_reuse_and_rate_limit(self):
        token = self.admin.request('invitations', dict(email='newteacher@college.test', role='teacher', purpose='signup'))[1]['token']
        client = Client(self.url)
        self.assertEqual(client.request('auth/register', dict(email='wrong@college.test', name='Wrong', password=PASSWORD, invitation=token))[0], 400)
        self.assertEqual(client.request('auth/register', dict(email='newteacher@college.test', name='Teacher', password=PASSWORD, invitation=token))[0], 200)
        self.assertEqual(client.request('auth/register', dict(email='newteacher@college.test', name='Teacher', password=PASSWORD, invitation=token))[0], 400)
        for _ in range(10):
            self.server.service.rate_limit('test', 'identity', limit=10)
        from backend.service import ApiError
        with self.assertRaises(ApiError) as error:
            self.server.service.rate_limit('test', 'identity', limit=10)
        self.assertEqual(error.exception.status, 429)

    def test_scheduling_cancellation_and_class_editing(self):
        from datetime import datetime, timezone, timedelta
        later = datetime.now(timezone(timedelta(hours=5, minutes=30))) + timedelta(hours=1)
        sid, _ = self.open_session(start_time=later.strftime('%Y-%m-%d %H:%M'))
        session = self.state(self.teacher)['sessions'][0]
        self.assertEqual(session['status'], 'scheduled')
        self.assertNotIn('code', session)
        self.approve(self.student)
        self.assertEqual(self.student.request('attendance', dict(session_id=sid, code='123456'))[0], 409)
        self.assertEqual(self.teacher.request('sessions/close', dict(session_id=sid))[0], 200)
        self.assertTrue(all(r['attendance_status'] == 'Cancelled' for r in self.state(self.teacher)['reports']))
        self.assertEqual(self.teacher.request('courses/update', dict(course_id=self.course_id, code='OS102', title='Updated OS', room='Lab 4'))[0], 200)
        self.assertEqual(self.state(self.student)['courses'][0]['title'], 'Updated OS')
        self.assertEqual(self.student.request('courses/update', dict(course_id=self.course_id, code='X', title='X'))[0], 403)
        self.assertEqual(self.teacher.request('courses/archive', dict(course_id=self.course_id))[0], 200)
        self.assertEqual(self.teacher.request('sessions/open', dict(course_id=self.course_id))[0], 400)

    def test_static_host_health_and_legacy_endpoint_closed(self):
        self.web.mkdir()
        (self.web / 'index.html').write_text('<html>Hybrid Attendance</html>')
        (self.web / 'assets').mkdir()
        with urllib.request.urlopen(self.url + '/') as response:
            self.assertIn(b'Hybrid Attendance', response.read())
        with self.assertRaises(urllib.error.HTTPError):
            urllib.request.urlopen(self.url + '/assets/')
        self.assertEqual(self.student.request('profiles', {})[0], 404)
        self.assertEqual(Client(self.url).request('health')[1]['version'], 2)
        with urllib.request.urlopen(self.url + '/api?route=auth/status') as response:
            self.assertFalse(json.load(response)['setup_required'])
        with patch.dict(os.environ, {'VERCEL': '1', 'DATABASE_URL': ''}):
            from backend.database import make_engine
            with self.assertRaises(RuntimeError):
                make_engine()
        # Existing demo files remain untouched by the versioned schema.
        self.assertTrue(self.db.is_file())


if __name__ == '__main__':
    unittest.main()
