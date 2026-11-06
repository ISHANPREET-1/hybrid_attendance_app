"""Portable schema shared by local SQLite and hosted PostgreSQL."""
import os
from pathlib import Path
from sqlalchemy import (create_engine, MetaData, Table, Column, String, Integer,
                        Float, ForeignKey, UniqueConstraint, event)
from sqlalchemy.pool import NullPool
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / '.env.local')
metadata = MetaData()


def table(name, *columns, **kwargs):
    return Table(name, metadata, *columns, **kwargs)


users = table('users_v2',
    Column('id', String(40), primary_key=True),
    Column('email', String(254), nullable=False, unique=True),
    Column('password_hash', String(500), nullable=False),
    Column('name', String(120), nullable=False),
    Column('role', String(20), nullable=False),
    Column('roll_no', String(100), unique=True),
    Column('department', String(120), nullable=False, default=''),
    Column('mobile', String(20), nullable=False, default=''),
    Column('created_at', Float, nullable=False))
auth_sessions = table('auth_sessions_v2',
    Column('token_hash', String(64), primary_key=True),
    Column('user_id', ForeignKey(users.c.id), nullable=False),
    Column('csrf', String(100), nullable=False),
    Column('expires_at', Float, nullable=False))
invites = table('invites_v2',
    Column('token_hash', String(64), primary_key=True),
    Column('email', String(254), nullable=False),
    Column('role', String(20), nullable=False),
    Column('purpose', String(20), nullable=False),
    Column('expires_at', Float, nullable=False),
    Column('used_at', Float))
courses = table('courses_v2',
    Column('id', String(40), primary_key=True),
    Column('code', String(40), nullable=False, unique=True),
    Column('title', String(160), nullable=False),
    Column('teacher_id', ForeignKey(users.c.id), nullable=False),
    Column('room', String(120), nullable=False, default=''),
    Column('created_at', Float, nullable=False),
    Column('archived', Integer, nullable=False, default=0))
enrollments = table('enrollments_v2',
    Column('id', String(40), primary_key=True),
    Column('course_id', ForeignKey(courses.c.id), nullable=False),
    Column('student_id', ForeignKey(users.c.id), nullable=False),
    Column('joined_at', Float, nullable=False),
    Column('left_at', Float),
    UniqueConstraint('course_id', 'student_id'))
class_sessions = table('class_sessions_v2',
    Column('id', String(40), primary_key=True),
    Column('course_id', ForeignKey(courses.c.id), nullable=False),
    Column('starts_at', Float, nullable=False),
    Column('ends_at', Float, nullable=False),
    Column('closed_at', Float),
    Column('status', String(20), nullable=False),
    Column('code_secret', String(100), nullable=False),
    Column('latitude', Float), Column('longitude', Float),
    Column('radius_m', Integer, nullable=False, default=150),
    Column('network_required', Integer, nullable=False, default=0))
# Snapshot the roster per session: later roster edits never rewrite history.
session_roster = table('session_roster_v2',
    Column('id', String(40), primary_key=True),
    Column('session_id', ForeignKey(class_sessions.c.id), nullable=False),
    Column('student_id', ForeignKey(users.c.id), nullable=False),
    UniqueConstraint('session_id', 'student_id'))
devices = table('devices_v2',
    Column('id', String(40), primary_key=True),
    Column('user_id', ForeignKey(users.c.id), nullable=False),
    Column('token_hash', String(64), nullable=False),
    Column('label', String(120), nullable=False),
    Column('status', String(20), nullable=False),
    Column('created_at', Float, nullable=False),
    UniqueConstraint('user_id', 'token_hash'))
attendance = table('attendance_v2',
    Column('id', String(40), primary_key=True),
    Column('session_id', ForeignKey(class_sessions.c.id), nullable=False),
    Column('student_id', ForeignKey(users.c.id), nullable=False),
    Column('device_id', ForeignKey(devices.c.id), nullable=False),
    Column('recorded_at', Float, nullable=False),
    Column('distance_m', Float),
    Column('network_checked', Integer, nullable=False, default=0),
    UniqueConstraint('session_id', 'student_id'))
notices = table('notices_v2',
    Column('id', String(40), primary_key=True),
    Column('course_id', ForeignKey(courses.c.id), nullable=False),
    Column('body', String(1000), nullable=False),
    Column('created_at', Float, nullable=False))
audit = table('audit_v2',
    Column('id', String(40), primary_key=True),
    Column('actor_id', String(40)),
    Column('action', String(80), nullable=False),
    Column('target_id', String(100), nullable=False),
    Column('created_at', Float, nullable=False))
attempts = table('attempts_v2',
    Column('key', String(64), primary_key=True),
    Column('count', Integer, nullable=False),
    Column('reset_at', Float, nullable=False))


def make_engine(url=None):
    url = url or os.getenv('DATABASE_URL')
    if not url:
        if os.getenv('VERCEL'):
            raise RuntimeError('DATABASE_URL is required on Vercel. Local SQLite is development only.')
        path = ROOT / 'backend/data/attendance.sqlite3'
        path.parent.mkdir(parents=True, exist_ok=True)
        url = 'sqlite:///' + str(path)
    if url.startswith(('postgres://', 'postgresql://')):
        url = 'postgresql+psycopg://' + url.split('://', 1)[1]
    if os.getenv('VERCEL') and not url.startswith('postgresql'):
        raise RuntimeError('Vercel requires a hosted PostgreSQL DATABASE_URL')
    kwargs = {'pool_pre_ping': True, 'hide_parameters': True}
    if url.startswith('sqlite:'):
        kwargs['connect_args'] = {'check_same_thread': False, 'timeout': 20}
    else:
        kwargs['poolclass'] = NullPool
    engine = create_engine(url, **kwargs)
    if url.startswith('sqlite:'):
        @event.listens_for(engine, 'connect')
        def configure(dbapi_connection, _):
            dbapi_connection.execute('PRAGMA foreign_keys=ON')
    return engine


def migrate(engine):
    # Versioned table names preserve all data from the original local demo.
    metadata.create_all(engine)
