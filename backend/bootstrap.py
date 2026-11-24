"""Optional one-time administrator creation from private deployment settings."""
import os
import time
from sqlalchemy import insert, select
from sqlalchemy.exc import IntegrityError
from .database import users
from .service import PASSWORDS, email, password, field, log


def bootstrap_admin(engine, settings=None):
    settings = os.environ if settings is None else settings
    with engine.connect() as conn:
        existing = conn.execute(select(users.c.email).where(users.c.role == 'admin')).scalar()
    if existing:
        return 'already configured'
    values = {key: settings.get(key, '') or '' for key in
              ('INITIAL_ADMIN_EMAIL', 'INITIAL_ADMIN_PASSWORD', 'INITIAL_ADMIN_NAME')}
    if not any(values.values()):
        return 'not configured; use first-administrator setup'
    if not values['INITIAL_ADMIN_EMAIL'] or not values['INITIAL_ADMIN_PASSWORD']:
        raise ValueError('Set both INITIAL_ADMIN_EMAIL and INITIAL_ADMIN_PASSWORD')
    data = {'email': values['INITIAL_ADMIN_EMAIL'], 'password': values['INITIAL_ADMIN_PASSWORD'],
            'name': values['INITIAL_ADMIN_NAME'] or 'Administrator'}
    account = dict(id='initial-admin', email=email(data), name=field(data, 'name', 120),
        password_hash=PASSWORDS.hash(password(data)), role='admin', roll_no=None,
        department='', mobile='', created_at=time.time())
    try:
        with engine.begin() as conn:
            conn.execute(insert(users).values(**account))
            log(conn, account['id'], 'administrator_bootstrapped', account['id'])
    except IntegrityError:
        # A concurrent setup may have won. Never promote an existing student email.
        with engine.connect() as conn:
            if conn.execute(select(users.c.id).where(users.c.id == 'initial-admin', users.c.role == 'admin')).first():
                return 'already configured'
        raise ValueError('The initial administrator email is already registered. Use a different email.') from None
    return 'created'
