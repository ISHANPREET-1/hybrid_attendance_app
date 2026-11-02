"""Local attendance API and Flutter web host. Python standard library only.

Run from the repository: python backend/server.py
This development server deliberately binds to loopback: role selection is not auth.
"""
import argparse
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from functools import partial
from contextlib import contextmanager
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent


@contextmanager
def connect(path):
    db = sqlite3.connect(path, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys = ON')
    try:
        with db:
            yield db
    finally:
        db.close()


def initialize(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with connect(path) as db:
        db.executescript('''
            CREATE TABLE IF NOT EXISTS profiles (
                role TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL,
                PRIMARY KEY (role, id)
            );
            CREATE TABLE IF NOT EXISTS attendance (
                name TEXT NOT NULL, rollNo TEXT NOT NULL,
                subject TEXT NOT NULL, courseCode TEXT NOT NULL,
                date TEXT NOT NULL, time TEXT NOT NULL,
                UNIQUE (rollNo, courseCode, date)
            );
        ''')


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, db_path, directory, **kwargs):
        self.db_path = db_path
        super().__init__(*args, directory=directory, **kwargs)

    def json_response(self, status, body):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/api/health':
            with connect(self.db_path) as db:
                db.execute('SELECT 1').fetchone()
            return self.json_response(200, {'status': 'ok', 'storage': 'sqlite'})
        if path == '/api/attendance':
            with connect(self.db_path) as db:
                rows = db.execute('SELECT * FROM attendance ORDER BY date, time, rowid').fetchall()
            return self.json_response(200, {'records': [dict(row) for row in rows]})
        if path.startswith('/api/'):
            return self.json_response(404, {'error': 'Unknown endpoint'})
        # Never serve the repo, database, logs, or Python source.
        if not (Path(self.directory) / 'index.html').is_file():
            return self.json_response(503, {'error': 'Build the Flutter web app first using run.ps1'})
        target = Path(self.translate_path(self.path)).resolve()
        if not target.is_relative_to(Path(self.directory).resolve()):
            return self.json_response(403, {'error': 'Forbidden'})
        if target.is_dir() and not (target / 'index.html').exists():
            return self.json_response(404, {'error': 'Not found'})
        super().do_GET()

    def do_POST(self):
        # Block cross-origin browser writes to this unauthenticated local service.
        origin = self.headers.get('Origin')
        if origin and origin != 'http://' + self.headers.get('Host', ''):
            return self.json_response(403, {'error': 'Cross-origin requests are disabled'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 16384:
                raise ValueError('Request body must be between 1 and 16384 bytes')
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError('Expected a JSON object')
            path = urlsplit(self.path).path
            if path == '/api/profiles':
                role = self.field(data, 'role')
                if role not in ('student', 'teacher'):
                    raise ValueError('Invalid role')
                profile = data.get('profile')
                if not isinstance(profile, dict):
                    raise ValueError('Expected a profile object')
                identity = self.field(profile, 'studentRollNo' if role == 'student' else 'teacherId')
                self.field(profile, 'studentName' if role == 'student' else 'teacherName')
                with connect(self.db_path) as db:
                    db.execute('INSERT INTO profiles VALUES (?, ?, ?) ON CONFLICT(role, id) DO UPDATE SET data=excluded.data',
                               (role, identity, json.dumps(profile)))
                return self.json_response(200, {'saved': True})
            if path == '/api/attendance':
                roll = self.field(data, 'rollNo')
                course = self.field(data, 'courseCode')
                subject = self.field(data, 'subject')
                # Date and time are authoritative on the server, in the college timezone (IST).
                now = datetime.now(timezone(timedelta(hours=5, minutes=30)))
                with connect(self.db_path) as db:
                    row = db.execute("SELECT data FROM profiles WHERE role='student' AND id=?", (roll,)).fetchone()
                    if row is None:
                        raise ValueError('Save a student profile before recording attendance')
                    profile = json.loads(row['data'])
                    record = dict(name=profile['studentName'], rollNo=roll, subject=subject,
                                  courseCode=course, date=now.strftime('%Y-%m-%d'), time=now.strftime('%H:%M'))
                    cursor = db.execute('INSERT OR IGNORE INTO attendance VALUES (:name,:rollNo,:subject,:courseCode,:date,:time)', record)
                    created = cursor.rowcount == 1
                    saved = db.execute('SELECT * FROM attendance WHERE rollNo=? AND courseCode=? AND date=?',
                                       (roll, course, record['date'])).fetchone()
                return self.json_response(201 if created else 200, {'record': dict(saved), 'created': created})
            return self.json_response(404, {'error': 'Unknown endpoint'})
        except (ValueError, UnicodeError, KeyError) as error:
            self.json_response(400, {'error': str(error)})
        except sqlite3.Error:
            self.json_response(500, {'error': 'Database operation failed'})

    @staticmethod
    def field(data, key):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip() or len(value) > 200:
            raise ValueError(f'{key} must be a nonempty string of at most 200 characters')
        return value.strip()


def create_server(port=8080, db_path=None, web_dir=None):
    db_path = Path(db_path) if db_path else ROOT / 'backend/data/attendance.sqlite3'
    initialize(db_path)
    handler = partial(Handler, db_path=db_path, directory=str(web_dir or ROOT / 'build/web'))
    return ThreadingHTTPServer(('127.0.0.1', port), handler)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    server = create_server(args.port)
    print(f'Hybrid Attendance: http://127.0.0.1:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
