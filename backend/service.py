"""Authenticated attendance workflows, independent of the HTTP host."""
import csv
import hashlib
import hmac
import io
import ipaddress
import math
import os
import re
import secrets
import time
from datetime import datetime, timezone, timedelta

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
from sqlalchemy import select, insert, update, delete, and_, func
from sqlalchemy.exc import IntegrityError
from .database import (users, auth_sessions, invites, courses, enrollments,
    class_sessions, session_roster, devices, attendance, notices, audit, attempts)

PASSWORDS = PasswordHasher()
IST = timezone(timedelta(hours=5, minutes=30))


class ApiError(Exception):
    def __init__(self, message, status=400):
        self.message, self.status = message, status
        super().__init__(message)


def uid():
    return secrets.token_hex(16)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def field(data, key, limit=160, optional=False):
    value = data.get(key, '')
    if not isinstance(value, str) or len(value) > limit:
        raise ApiError(f'{key} is invalid')
    value = value.strip()
    if not value and not optional:
        raise ApiError(f'{key} is required')
    return value


def email(data):
    value = field(data, 'email', 254).lower()
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
        raise ApiError('Enter a valid email address')
    return value


def password(data, key='password'):
    value = data.get(key)
    if not isinstance(value, str) or not 12 <= len(value) <= 128:
        raise ApiError('Use a password between 12 and 128 characters')
    return value


def one(conn, query):
    row = conn.execute(query).mappings().first()
    return dict(row) if row else None


def rows(conn, query):
    return [dict(r) for r in conn.execute(query).mappings()]


def public_user(user):
    return {key: user[key] for key in ('id', 'email', 'name', 'role', 'roll_no', 'department', 'mobile')}


def log(conn, actor, action, target):
    conn.execute(insert(audit).values(id=uid(), actor_id=actor, action=action,
        target_id=target, created_at=time.time()))


def code_for(session, stamp=None):
    stamp = time.time() if stamp is None else stamp
    value = hmac.new(session['code_secret'].encode(), str(int(stamp // 30)).encode(), hashlib.sha256).digest()
    return f'{int.from_bytes(value[:4], "big") % 1000000:06d}'


class Service:
    def __init__(self, engine, setup_token=None):
        self.engine = engine
        self.setup_token = setup_token if setup_token is not None else os.getenv('ADMIN_SETUP_TOKEN', '')

    def rate_limit(self, scope, identity, limit=10, seconds=900):
        # A persistent fixed-window counter also works across serverless instances.
        key = digest(f'{scope}:{identity}')
        now = time.time()
        with self.engine.begin() as conn:
            conn.execute(delete(attempts).where(attempts.c.reset_at < now))
            # Dialect-specific upsert is atomic for both supported databases.
            if self.engine.dialect.name == 'postgresql':
                from sqlalchemy.dialects.postgresql import insert as upsert
            else:
                from sqlalchemy.dialects.sqlite import insert as upsert
            statement = upsert(attempts).values(key=key, count=1, reset_at=now + seconds)
            conn.execute(statement.on_conflict_do_update(index_elements=['key'],
                set_={'count': attempts.c.count + 1}))
            attempt = one(conn, select(attempts).where(attempts.c.key == key))
        if attempt['count'] > limit:
            raise ApiError('Too many attempts. Please try again later.', 429)

    def authenticate(self, token):
        if not token:
            raise ApiError('Please sign in', 401)
        with self.engine.begin() as conn:
            session = one(conn, select(auth_sessions).where(
                auth_sessions.c.token_hash == digest(token), auth_sessions.c.expires_at > time.time()))
            if not session:
                raise ApiError('Your session expired. Please sign in again.', 401)
            user = one(conn, select(users).where(users.c.id == session['user_id']))
        return user, session

    def session(self, conn, user):
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(24)
        conn.execute(delete(auth_sessions).where(auth_sessions.c.expires_at < time.time()))
        conn.execute(insert(auth_sessions).values(token_hash=digest(token), user_id=user['id'],
            csrf=csrf, expires_at=time.time() + 43200))
        return {'user': public_user(user), 'csrf': csrf}, token

    def auth(self, action, data, ip):
        if action == 'status':
            with self.engine.connect() as conn:
                return {'setup_required': not bool(conn.execute(select(users.c.id).where(users.c.role == 'admin')).first())}, None
        self.rate_limit('auth-ip', ip, 40)
        if action == 'login':
            address = email(data)
            self.rate_limit('login-email', address, 10)
            raw = data.get('password')
            if not isinstance(raw, str) or not 1 <= len(raw) <= 128:
                raise ApiError('Enter your password')
            with self.engine.begin() as conn:
                user = one(conn, select(users).where(users.c.email == address))
                try:
                    # Hashing a dummy password avoids a fast account-existence response.
                    encoded = user['password_hash'] if user else PASSWORDS.hash(secrets.token_urlsafe(32))
                    PASSWORDS.verify(encoded, raw)
                    if not user:
                        raise VerificationError('Invalid credentials')
                except (VerificationError, InvalidHashError):
                    raise ApiError('Email or password is incorrect', 401)
                if PASSWORDS.check_needs_rehash(user['password_hash']):
                    conn.execute(update(users).where(users.c.id == user['id']).values(password_hash=PASSWORDS.hash(raw)))
                return self.session(conn, user)
        if action == 'reset':
            token = field(data, 'token', 200)
            encoded = PASSWORDS.hash(password(data))
            with self.engine.begin() as conn:
                invite = one(conn, select(invites).where(invites.c.token_hash == digest(token),
                    invites.c.purpose == 'reset', invites.c.used_at.is_(None), invites.c.expires_at > time.time()))
                if not invite:
                    raise ApiError('Reset token is invalid or expired')
                changed = conn.execute(update(invites).where(invites.c.token_hash == digest(token),
                    invites.c.used_at.is_(None)).values(used_at=time.time()))
                if changed.rowcount != 1:
                    raise ApiError('Reset token was already used')
                user = one(conn, select(users).where(users.c.email == invite['email']))
                conn.execute(update(users).where(users.c.id == user['id']).values(password_hash=encoded))
                conn.execute(delete(auth_sessions).where(auth_sessions.c.user_id == user['id']))
                log(conn, user['id'], 'password_reset', user['id'])
            return {'message': 'Password reset. Sign in with your new password.'}, None
        if action not in ('register', 'setup'):
            raise ApiError('Unknown endpoint', 404)
        address, name, encoded = email(data), field(data, 'name', 120), PASSWORDS.hash(password(data))
        with self.engine.begin() as conn:
            role = 'student'
            if action == 'setup':
                if not self.setup_token or not hmac.compare_digest(field(data, 'setup_token', 200), self.setup_token):
                    raise ApiError('Setup token is invalid', 403)
                role = 'admin'
                # A unique fixed id makes first-admin creation safe under concurrent setup requests.
                if conn.execute(select(users.c.id).where(users.c.id == 'initial-admin')).first():
                    raise ApiError('Administrator setup is already complete', 409)
            invitation = field(data, 'invitation', 200, True)
            if invitation and action != 'setup':
                invite = one(conn, select(invites).where(invites.c.token_hash == digest(invitation),
                    invites.c.email == address, invites.c.purpose == 'signup', invites.c.used_at.is_(None),
                    invites.c.expires_at > time.time()))
                if not invite:
                    raise ApiError('Invitation is invalid, expired or belongs to another email')
                role = invite['role']
                used = conn.execute(update(invites).where(invites.c.token_hash == digest(invitation),
                    invites.c.used_at.is_(None)).values(used_at=time.time()))
                if used.rowcount != 1:
                    raise ApiError('Invitation was already used')
            roll = field(data, 'roll_no', 100) if role == 'student' else None
            user = dict(id='initial-admin' if action == 'setup' else uid(), email=address,
                name=name, role=role, roll_no=roll, password_hash=encoded,
                department=field(data, 'department', 120, True), mobile='', created_at=time.time())
            conn.execute(insert(users).values(**user))
            log(conn, user['id'], 'account_created', user['id'])
            return self.session(conn, user)

    @staticmethod
    def require(user, *roles):
        if user['role'] not in roles:
            raise ApiError('You do not have permission for this action', 403)

    def course(self, conn, user, course_id, manage=False):
        course = one(conn, select(courses).where(courses.c.id == course_id))
        if not course:
            raise ApiError('Course not found', 404)
        if user['role'] == 'admin' or (user['role'] == 'teacher' and course['teacher_id'] == user['id']):
            return course
        if not manage and user['role'] == 'student' and conn.execute(select(enrollments.c.id).where(
                enrollments.c.course_id == course_id, enrollments.c.student_id == user['id'],
                enrollments.c.left_at.is_(None))).first():
            return course
        raise ApiError('You do not have access to this course', 403)

    def visible_courses(self, conn, user):
        query = select(courses)
        if user['role'] == 'teacher':
            query = query.where(courses.c.teacher_id == user['id'])
        elif user['role'] == 'student':
            query = query.join(enrollments, enrollments.c.course_id == courses.c.id).where(
                enrollments.c.student_id == user['id'], enrollments.c.left_at.is_(None))
        return rows(conn, query.order_by(courses.c.created_at))

    def snapshot(self, user, device_token):
        with self.engine.begin() as conn:
            result_courses = self.visible_courses(conn, user)
            ids = [c['id'] for c in result_courses]
            sessions = rows(conn, select(class_sessions).where(class_sessions.c.course_id.in_(ids)).order_by(class_sessions.c.starts_at.desc()))
            for item in sessions:
                if item['status'] in ('open', 'scheduled') and item['ends_at'] <= time.time():
                    conn.execute(update(class_sessions).where(class_sessions.c.id == item['id'],
                        class_sessions.c.status.in_(['open', 'scheduled'])).values(status='closed', closed_at=item['ends_at']))
                    current = one(conn, select(class_sessions.c.status, class_sessions.c.closed_at).where(class_sessions.c.id == item['id']))
                    item.update(current)
                elif item['status'] == 'scheduled' and item['starts_at'] <= time.time():
                    conn.execute(update(class_sessions).where(class_sessions.c.id == item['id'],
                        class_sessions.c.status == 'scheduled').values(status='open'))
                    current = one(conn, select(class_sessions.c.status, class_sessions.c.closed_at).where(class_sessions.c.id == item['id']))
                    item.update(current)
                secret = item.pop('code_secret')
                if user['role'] != 'student' and item['status'] == 'open':
                    item['code'] = code_for({**item, 'code_secret': secret})
                    item['code_expires_at'] = (int(time.time() // 30) + 1) * 30
            roster_query = select(enrollments.c.id, enrollments.c.course_id, enrollments.c.student_id,
                users.c.name, users.c.email, users.c.roll_no).join(users, users.c.id == enrollments.c.student_id).where(
                    enrollments.c.course_id.in_(ids), enrollments.c.left_at.is_(None))
            if user['role'] == 'student':
                roster_query = roster_query.where(enrollments.c.student_id == user['id'])
            roster = rows(conn, roster_query)
            dev_query = select(devices.c.id, devices.c.user_id, devices.c.label, devices.c.status,
                devices.c.created_at, users.c.name, users.c.email).join(users, users.c.id == devices.c.user_id)
            if user['role'] != 'admin':
                dev_query = dev_query.where(devices.c.user_id == user['id'])
            device_rows = rows(conn, dev_query.order_by(devices.c.created_at.desc()))
            if device_token:
                current = one(conn, select(devices).where(devices.c.user_id == user['id'], devices.c.token_hash == digest(device_token)))
            else:
                current = None
            announcements = rows(conn, select(notices).where(notices.c.course_id.in_(ids)).order_by(notices.c.created_at.desc()).limit(100))
            return dict(user=public_user(user), courses=result_courses, sessions=sessions, roster=roster,
                devices=device_rows, current_device_id=current['id'] if current else None,
                reports=self.reports(conn, user), notices=announcements,
                users=rows(conn, select(users.c.id, users.c.email, users.c.name, users.c.role, users.c.roll_no)) if user['role'] == 'admin' else [],
                audit=rows(conn, select(audit).order_by(audit.c.created_at.desc()).limit(100)) if user['role'] == 'admin' else [],
                campus_network_available=bool(os.getenv('CAMPUS_CIDRS')),
                server_time=time.time())

    def reports(self, conn, user):
        query = select(session_roster.c.student_id, users.c.name, users.c.roll_no,
            courses.c.id.label('course_id'), courses.c.code.label('course_code'), courses.c.title,
            class_sessions.c.id.label('session_id'), class_sessions.c.starts_at, class_sessions.c.ends_at,
            class_sessions.c.status, attendance.c.recorded_at).select_from(session_roster.join(users,
                users.c.id == session_roster.c.student_id).join(class_sessions,
                class_sessions.c.id == session_roster.c.session_id).join(courses,
                courses.c.id == class_sessions.c.course_id).outerjoin(attendance, and_(
                    attendance.c.session_id == session_roster.c.session_id,
                    attendance.c.student_id == session_roster.c.student_id)))
        if user['role'] == 'student':
            query = query.where(session_roster.c.student_id == user['id'])
        elif user['role'] == 'teacher':
            query = query.where(courses.c.teacher_id == user['id'])
        result = rows(conn, query.order_by(class_sessions.c.starts_at.desc(), users.c.name))
        for row in result:
            ended = row['status'] == 'closed' or row['ends_at'] <= time.time()
            row['attendance_status'] = ('Cancelled' if row['status'] == 'cancelled' else
                'Present' if row['recorded_at'] is not None else ('Absent' if ended else 'Pending'))
            row['date'] = datetime.fromtimestamp(row['starts_at'], IST).strftime('%Y-%m-%d')
        return result

    def mutate(self, user, action, data, device_token, ip):
        new_device_token = None
        if action == 'attendance':
            self.rate_limit('checkin', user['id'], 15, 300)
        with self.engine.begin() as conn:
            if action == 'profile':
                values = dict(name=field(data, 'name', 120), department=field(data, 'department', 120, True), mobile=field(data, 'mobile', 20, True))
                conn.execute(update(users).where(users.c.id == user['id']).values(**values))
                log(conn, user['id'], 'profile_updated', user['id'])
            elif action == 'password':
                current = data.get('current_password')
                if not isinstance(current, str) or not 1 <= len(current) <= 128:
                    raise ApiError('Enter your current password')
                try:
                    PASSWORDS.verify(user['password_hash'], current)
                except VerificationError:
                    raise ApiError('Current password is incorrect', 403)
                conn.execute(update(users).where(users.c.id == user['id']).values(password_hash=PASSWORDS.hash(password(data))))
                conn.execute(delete(auth_sessions).where(auth_sessions.c.user_id == user['id']))
                log(conn, user['id'], 'password_changed', user['id'])
                return {'message': 'Password changed. Please sign in again.'}, None
            elif action == 'invitations':
                self.require(user, 'admin')
                address, role = email(data), field(data, 'role', 20)
                purpose = field(data, 'purpose', 20)
                if role not in ('teacher', 'admin', 'student') or purpose not in ('signup', 'reset'):
                    raise ApiError('Invalid invitation')
                existing = one(conn, select(users).where(users.c.email == address))
                if purpose == 'reset' and not existing:
                    raise ApiError('No account has that email')
                if purpose == 'signup' and existing:
                    raise ApiError('Account already exists')
                if existing:
                    role = existing['role']
                token = secrets.token_urlsafe(32)
                conn.execute(insert(invites).values(token_hash=digest(token), email=address, role=role,
                    purpose=purpose, expires_at=time.time() + (3600 if purpose == 'reset' else 172800)))
                log(conn, user['id'], f'{purpose}_token_created', address)
                return {'token': token, 'message': 'Share this one-time token privately with the account holder.'}, None
            elif action == 'courses':
                self.require(user, 'teacher', 'admin')
                teacher_id = user['id'] if user['role'] == 'teacher' else field(data, 'teacher_id', 40)
                teacher = one(conn, select(users).where(users.c.id == teacher_id, users.c.role == 'teacher'))
                if not teacher:
                    raise ApiError('Choose a teacher account')
                course_id = uid()
                conn.execute(insert(courses).values(id=course_id, code=field(data, 'code', 40), title=field(data, 'title', 160),
                    teacher_id=teacher_id, room=field(data, 'room', 120, True), created_at=time.time(), archived=0))
                log(conn, user['id'], 'course_created', course_id)
            elif action in ('roster/add', 'roster/remove'):
                course = self.course(conn, user, field(data, 'course_id', 40), True)
                # Lock the parent on PostgreSQL, serializing roster edits and session snapshots.
                conn.execute(update(courses).where(courses.c.id == course['id']).values(room=course['room']))
                student = one(conn, select(users).where(users.c.email == email(data), users.c.role == 'student'))
                if not student:
                    raise ApiError('The student must register before being enrolled')
                enrollment = one(conn, select(enrollments).where(enrollments.c.course_id == course['id'], enrollments.c.student_id == student['id']))
                if action.endswith('add'):
                    if course['archived']:
                        raise ApiError('This course is archived')
                    if enrollment:
                        conn.execute(update(enrollments).where(enrollments.c.id == enrollment['id']).values(left_at=None))
                    else:
                        conn.execute(insert(enrollments).values(id=uid(), course_id=course['id'], student_id=student['id'], joined_at=time.time()))
                elif enrollment:
                    conn.execute(update(enrollments).where(enrollments.c.id == enrollment['id']).values(left_at=time.time()))
                log(conn, user['id'], action, student['id'])
            elif action == 'courses/update':
                course = self.course(conn, user, field(data, 'course_id', 40), True)
                conn.execute(update(courses).where(courses.c.id == course['id']).values(
                    code=field(data, 'code', 40), title=field(data, 'title', 160), room=field(data, 'room', 120, True)))
                log(conn, user['id'], 'course_updated', course['id'])
            elif action == 'courses/archive':
                course = self.course(conn, user, field(data, 'course_id', 40), True)
                conn.execute(update(courses).where(courses.c.id == course['id']).values(archived=1))
                conn.execute(update(class_sessions).where(class_sessions.c.course_id == course['id'], class_sessions.c.status == 'open').values(status='closed', closed_at=time.time()))
                conn.execute(update(class_sessions).where(class_sessions.c.course_id == course['id'], class_sessions.c.status == 'scheduled').values(status='cancelled', closed_at=time.time()))
                log(conn, user['id'], 'course_archived', course['id'])
            elif action == 'sessions/open':
                course = self.course(conn, user, field(data, 'course_id', 40), True)
                conn.execute(update(courses).where(courses.c.id == course['id']).values(room=course['room']))
                if course['archived']:
                    raise ApiError('This course is archived')
                try:
                    minutes = int(data.get('minutes', 15))
                    radius = int(data.get('radius_m', 150))
                    lat = float(data['latitude']) if data.get('latitude') is not None else None
                    lon = float(data['longitude']) if data.get('longitude') is not None else None
                    if not 1 <= minutes <= 240 or not 30 <= radius <= 5000:
                        raise ValueError()
                    if (lat is None) != (lon is None) or (lat is not None and (not math.isfinite(lat) or not math.isfinite(lon) or not -90 <= lat <= 90 or not -180 <= lon <= 180)):
                        raise ValueError()
                except (ValueError, TypeError, OverflowError):
                    raise ApiError('Invalid duration, radius or coordinates')
                now = time.time()
                starts_at = now
                scheduled_time = field(data, 'start_time', 30, True)
                if scheduled_time:
                    try:
                        starts_at = datetime.strptime(scheduled_time, '%Y-%m-%d %H:%M').replace(tzinfo=IST).timestamp()
                        if not now - 60 <= starts_at <= now + 365 * 86400:
                            raise ValueError()
                    except ValueError:
                        raise ApiError('Start time must be YYYY-MM-DD HH:MM in IST, within the next year')
                ends_at = starts_at + minutes * 60
                if conn.execute(select(class_sessions.c.id).where(class_sessions.c.course_id == course['id'],
                    class_sessions.c.status.in_(['open', 'scheduled']), class_sessions.c.starts_at < ends_at,
                    class_sessions.c.ends_at > starts_at)).first():
                    raise ApiError('This course has an overlapping attendance session', 409)
                network = data.get('network_required') is True
                if network and not os.getenv('CAMPUS_CIDRS'):
                    raise ApiError('An administrator must configure CAMPUS_CIDRS first')
                session_id = uid()
                conn.execute(insert(class_sessions).values(id=session_id, course_id=course['id'], starts_at=starts_at,
                    ends_at=ends_at, status='scheduled' if starts_at > now else 'open', code_secret=secrets.token_urlsafe(32),
                    latitude=lat, longitude=lon, radius_m=radius, network_required=int(network)))
                members = conn.execute(select(enrollments.c.student_id).where(enrollments.c.course_id == course['id'], enrollments.c.left_at.is_(None))).scalars().all()
                for student_id in members:
                    conn.execute(insert(session_roster).values(id=uid(), session_id=session_id, student_id=student_id))
                log(conn, user['id'], 'session_opened', session_id)
            elif action == 'sessions/close':
                session = one(conn, select(class_sessions).where(class_sessions.c.id == field(data, 'session_id', 40)))
                if not session:
                    raise ApiError('Session not found', 404)
                self.course(conn, user, session['course_id'], True)
                conn.execute(update(class_sessions).where(class_sessions.c.id == session['id']).values(
                    status='cancelled' if session['starts_at'] > time.time() else 'closed', closed_at=time.time()))
                log(conn, user['id'], 'session_closed', session['id'])
            elif action == 'devices/request':
                self.require(user, 'student')
                label = field(data, 'label', 120)
                if not device_token:
                    device_token = secrets.token_urlsafe(32)
                    new_device_token = device_token
                item = one(conn, select(devices).where(devices.c.user_id == user['id'], devices.c.token_hash == digest(device_token)))
                if item:
                    if item['status'] != 'approved':
                        conn.execute(update(devices).where(devices.c.id == item['id']).values(status='pending', label=label))
                else:
                    count = conn.execute(select(func.count()).select_from(devices).where(devices.c.user_id == user['id'])).scalar()
                    if count >= 10:
                        raise ApiError('Device limit reached. Ask an administrator to review your devices.')
                    conn.execute(insert(devices).values(id=uid(), user_id=user['id'], token_hash=digest(device_token),
                        label=label, status='pending', created_at=time.time()))
                log(conn, user['id'], 'device_requested', user['id'])
            elif action == 'devices/review':
                self.require(user, 'admin')
                item = one(conn, select(devices).where(devices.c.id == field(data, 'device_id', 40)))
                status = field(data, 'status', 20)
                if not item or status not in ('approved', 'rejected', 'revoked'):
                    raise ApiError('Invalid device review')
                if status == 'approved':
                    conn.execute(update(users).where(users.c.id == item['user_id']).values(name=users.c.name))
                    conn.execute(update(devices).where(devices.c.user_id == item['user_id'], devices.c.status == 'approved').values(status='revoked'))
                conn.execute(update(devices).where(devices.c.id == item['id']).values(status=status))
                log(conn, user['id'], f'device_{status}', item['id'])
            elif action == 'attendance':
                self.require(user, 'student')
                session_id = field(data, 'session_id', 40)
                # A write lock serializes check-in with close; row locking works on Postgres too.
                conn.execute(update(class_sessions).where(class_sessions.c.id == session_id).values(status=class_sessions.c.status))
                session = one(conn, select(class_sessions).where(class_sessions.c.id == session_id))
                if not session or session['status'] not in ('open', 'scheduled') or not session['starts_at'] <= time.time() < session['ends_at']:
                    raise ApiError('This attendance session is closed', 409)
                if not conn.execute(select(session_roster.c.id).where(session_roster.c.session_id == session_id,
                    session_roster.c.student_id == user['id'])).first():
                    raise ApiError('You were not on the roster when this session opened', 403)
                self.course(conn, user, session['course_id'])
                conn.execute(update(users).where(users.c.id == user['id']).values(name=users.c.name))
                device = one(conn, select(devices).where(devices.c.user_id == user['id'],
                    devices.c.token_hash == digest(device_token or ''), devices.c.status == 'approved'))
                if not device:
                    raise ApiError('This browser needs administrator device approval', 403)
                code = field(data, 'code', 6)
                if not any(hmac.compare_digest(code, code_for(session, time.time() - offset)) for offset in (0, 30)):
                    raise ApiError('The classroom code is incorrect or expired', 403)
                distance = None
                if session['latitude'] is not None:
                    try:
                        lat, lon, accuracy = float(data['latitude']), float(data['longitude']), float(data['accuracy'])
                        if not all(math.isfinite(v) for v in (lat, lon, accuracy)) or not -90 <= lat <= 90 or not -180 <= lon <= 180 or not 0 <= accuracy <= min(100, session['radius_m']):
                            raise ValueError()
                        delta_lat = math.radians(lat - session['latitude'])
                        delta_lon = math.radians(lon - session['longitude'])
                        value = math.sin(delta_lat / 2) ** 2 + math.cos(math.radians(lat)) * math.cos(math.radians(session['latitude'])) * math.sin(delta_lon / 2) ** 2
                        distance = 6371000 * 2 * math.asin(math.sqrt(min(1, value)))
                    except (KeyError, ValueError, TypeError):
                        raise ApiError('A sufficiently accurate browser location is required', 403)
                    if distance > session['radius_m']:
                        raise ApiError('Your reported location is outside the classroom area', 403)
                if session['network_required']:
                    try:
                        allowed = any(ipaddress.ip_address(ip) in ipaddress.ip_network(c.strip()) for c in os.environ['CAMPUS_CIDRS'].split(','))
                    except (ValueError, KeyError):
                        allowed = False
                    if not allowed:
                        raise ApiError('Connect through the configured campus network', 403)
                if not conn.execute(select(attendance.c.id).where(attendance.c.session_id == session_id, attendance.c.student_id == user['id'])).first():
                    conn.execute(insert(attendance).values(id=uid(), session_id=session_id, student_id=user['id'],
                        device_id=device['id'], recorded_at=time.time(), distance_m=distance,
                        network_checked=session['network_required']))
                    log(conn, user['id'], 'attendance_recorded', session_id)
            elif action == 'notices':
                course = self.course(conn, user, field(data, 'course_id', 40), True)
                conn.execute(insert(notices).values(id=uid(), course_id=course['id'], body=field(data, 'body', 1000), created_at=time.time()))
                log(conn, user['id'], 'announcement_posted', course['id'])
            else:
                raise ApiError('Unknown endpoint', 404)
        return {'message': 'Saved successfully'}, new_device_token

    def export(self, user):
        with self.engine.connect() as conn:
            report = self.reports(conn, user)
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(['Course', 'Subject', 'Session date (IST)', 'Roll number', 'Student', 'Status', 'Recorded at (IST)'])
        for row in report:
            values = [row['course_code'], row['title'], row['date'], row['roll_no'], row['name'], row['attendance_status'],
                datetime.fromtimestamp(row['recorded_at'], IST).isoformat() if row['recorded_at'] else '']
            # Prevent formula execution if spreadsheet software opens a user-controlled value.
            writer.writerow(["'" + str(v) if str(v).startswith(('=', '+', '-', '@', '\t', '\r')) else v for v in values])
        return output.getvalue()
