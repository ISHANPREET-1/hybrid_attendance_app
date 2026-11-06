"""HTTP host shared by local development and Vercel's Python runtime."""
import argparse
import json
import logging
import os
from functools import partial
from http.cookies import SimpleCookie
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

if __package__ in (None, ''):
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from backend.database import ROOT, make_engine, migrate, auth_sessions
from backend.service import ApiError, Service, digest


class Handler(SimpleHTTPRequestHandler):
    service = None

    def __init__(self, *args, service=None, directory=None, **kwargs):
        self.service = service or type(self).service
        self.out_cookies = []
        super().__init__(*args, directory=str(directory or ROOT / 'build/web'), **kwargs)

    def end_headers(self):
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'same-origin')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Permissions-Policy', 'geolocation=(self), camera=(), microphone=()')
        super().end_headers()

    def cookie(self, name):
        try:
            jar = SimpleCookie(self.headers.get('Cookie', ''))
            return jar[name].value if name in jar else None
        except Exception:
            return None

    def set_cookie(self, name, value, max_age):
        jar = SimpleCookie()
        jar[name] = value
        jar[name]['path'] = '/'
        jar[name]['httponly'] = True
        jar[name]['samesite'] = 'Lax'
        jar[name]['max-age'] = str(max_age)
        if os.getenv('VERCEL') or os.getenv('COOKIE_SECURE') == 'true':
            jar[name]['secure'] = True
        self.out_cookies.append(jar[name].OutputString())

    def respond(self, status, body, content_type='application/json; charset=utf-8', download=False):
        payload = json.dumps(body).encode() if content_type.startswith('application/json') else body.encode('utf-8-sig')
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(payload)))
        self.send_header('Cache-Control', 'no-store')
        for cookie in self.out_cookies:
            self.send_header('Set-Cookie', cookie)
        if download:
            self.send_header('Content-Disposition', 'attachment; filename="attendance.csv"')
        self.end_headers()
        self.wfile.write(payload)

    def client_ip(self):
        # Vercel overwrites x-real-ip; never trust proxy headers on the local server.
        if os.getenv('VERCEL'):
            return self.headers.get('x-real-ip', '')
        return self.client_address[0]

    def check_origin(self):
        origin = self.headers.get('Origin')
        if not origin:
            return
        host = self.headers.get('Host', '')
        allowed = os.getenv('APP_ORIGIN', '').rstrip('/')
        if not allowed:
            allowed = ('https://' if os.getenv('VERCEL') or os.getenv('COOKIE_SECURE') == 'true' else 'http://') + host
        if origin != allowed:
            raise ApiError('Cross-origin requests are disabled. Use the same host for the app and API.', 403)

    def api(self, method):
        self.out_cookies = []
        parsed = urlsplit(self.path)
        path = parsed.path.removeprefix('/api/').strip('/')
        if parsed.path == '/api':
            path = parse_qs(parsed.query).get('route', [''])[0].strip('/')
        try:
            if method == 'GET' and path == 'health':
                with self.service.engine.connect() as conn:
                    conn.execute(select(1)).first()
                return self.respond(200, {'status': 'ok', 'storage': self.service.engine.dialect.name, 'version': 2})
            if method == 'GET' and path == 'auth/status':
                return self.respond(200, self.service.auth('status', {}, self.client_ip())[0])
            data = {}
            if method == 'POST':
                self.check_origin()
                if self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
                    raise ApiError('Use application/json', 415)
                try:
                    length = int(self.headers.get('Content-Length', '0'))
                    if not 0 < length <= 16384:
                        raise ValueError()
                    data = json.loads(self.rfile.read(length))
                    if not isinstance(data, dict):
                        raise ValueError()
                except (ValueError, UnicodeError):
                    raise ApiError('Expected a JSON object of at most 16384 bytes')
                if path in ('auth/login', 'auth/register', 'auth/setup', 'auth/reset'):
                    result, token = self.service.auth(path.split('/')[1], data, self.client_ip())
                    if token:
                        # Rotate the existing session rather than leaving a prior login active.
                        old_token = self.cookie('ha_session')
                        if old_token:
                            with self.service.engine.begin() as conn:
                                conn.execute(delete(auth_sessions).where(auth_sessions.c.token_hash == digest(old_token)))
                        self.set_cookie('ha_session', token, 43200)
                    return self.respond(200, result)
            user, session = self.service.authenticate(self.cookie('ha_session'))
            if method == 'GET':
                if path == 'auth/me':
                    from backend.service import public_user
                    return self.respond(200, {'user': public_user(user), 'csrf': session['csrf']})
                if path == 'state':
                    return self.respond(200, self.service.snapshot(user, self.cookie('ha_device')))
                if path == 'reports.csv':
                    return self.respond(200, self.service.export(user), 'text/csv; charset=utf-8', True)
                raise ApiError('Unknown endpoint', 404)
            import hmac
            if not hmac.compare_digest(self.headers.get('X-CSRF-Token', ''), session['csrf']):
                raise ApiError('Session security check failed. Refresh the page.', 403)
            if path == 'auth/logout':
                with self.service.engine.begin() as conn:
                    conn.execute(delete(auth_sessions).where(auth_sessions.c.token_hash == session['token_hash']))
                self.set_cookie('ha_session', '', 0)
                return self.respond(200, {'message': 'Signed out'})
            result, device = self.service.mutate(user, path, data, self.cookie('ha_device'), self.client_ip())
            if device:
                self.set_cookie('ha_device', device, 31536000)
            if path == 'password':
                self.set_cookie('ha_session', '', 0)
            self.respond(200, result)
        except ApiError as error:
            self.respond(error.status, {'error': error.message})
        except IntegrityError:
            self.respond(409, {'error': 'An account, roll number, course or record with those details already exists.'})
        except SQLAlchemyError:
            logging.exception('Database operation failed')
            self.respond(503, {'error': 'Database unavailable. Please retry.'})
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            logging.exception('Request failed')
            self.respond(500, {'error': 'The request could not be completed.'})

    def do_GET(self):
        if urlsplit(self.path).path == '/api' or urlsplit(self.path).path.startswith('/api/'):
            return self.api('GET')
        root = Path(self.directory).resolve()
        target = Path(self.translate_path(self.path)).resolve()
        if not target.is_relative_to(root):
            return self.respond(403, {'error': 'Forbidden'})
        if not (root / 'index.html').is_file():
            return self.respond(503, {'error': 'Build the Flutter app using run.ps1 first'})
        if target.is_dir() and not (target / 'index.html').is_file():
            return self.respond(404, {'error': 'Not found'})
        try:
            super().do_GET()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_HEAD(self):
        if urlsplit(self.path).path == '/api' or urlsplit(self.path).path.startswith('/api/'):
            self.send_response(405)
            self.end_headers()
        else:
            super().do_HEAD()

    def do_POST(self):
        if urlsplit(self.path).path != '/api' and not urlsplit(self.path).path.startswith('/api/'):
            return self.respond(404, {'error': 'Unknown endpoint'})
        self.api('POST')


def create_server(port=8080, db_path=None, web_dir=None, setup_token=None):
    engine = make_engine('sqlite:///' + str(db_path) if db_path else None)
    migrate(engine)
    service = Service(engine, setup_token)
    if not service.setup_token:
        import secrets
        token_file = ROOT / '.tools/setup-token.txt'
        token_file.parent.mkdir(exist_ok=True)
        if not token_file.exists():
            token_file.write_text(secrets.token_urlsafe(32))
        service.setup_token = token_file.read_text().strip()
    handler = partial(Handler, service=service, directory=web_dir or ROOT / 'build/web')
    server = ThreadingHTTPServer(('127.0.0.1', port), handler)
    server.service = service
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    server = create_server(args.port)
    print(f'Hybrid Attendance: http://127.0.0.1:{server.server_port}', flush=True)
    print('First administrator setup token: .tools/setup-token.txt (or ADMIN_SETUP_TOKEN from .env.local)', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        server.service.engine.dispose()
