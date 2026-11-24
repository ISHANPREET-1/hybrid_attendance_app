import tempfile
import unittest
from pathlib import Path
from sqlalchemy import insert, select
from backend.database import make_engine, migrate, users
from backend.bootstrap import bootstrap_admin
from backend.service import Service, PASSWORDS


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.engine = make_engine('sqlite:///' + str(Path(self.temp.name) / 'test.sqlite3'))
        migrate(self.engine)
        self.settings = dict(INITIAL_ADMIN_EMAIL='admin@attendance.test',
            INITIAL_ADMIN_PASSWORD='Generated first password 2026!', INITIAL_ADMIN_NAME='Administrator')

    def tearDown(self):
        self.engine.dispose()
        self.temp.cleanup()

    def test_creation_login_and_setup_disabled(self):
        self.assertEqual(bootstrap_admin(self.engine, self.settings), 'created')
        service = Service(self.engine, 'setup-secret')
        result, token = service.auth('login', dict(email=self.settings['INITIAL_ADMIN_EMAIL'],
            password=self.settings['INITIAL_ADMIN_PASSWORD']), '127.0.0.1')
        self.assertEqual(result['user']['role'], 'admin')
        self.assertEqual(result['user']['id'], 'initial-admin')
        self.assertTrue(token)
        self.assertFalse(service.auth('status', {}, '')[0]['setup_required'])

    def test_redeploy_never_resets_password(self):
        bootstrap_admin(self.engine, self.settings)
        self.assertEqual(bootstrap_admin(self.engine, {**self.settings,
            'INITIAL_ADMIN_PASSWORD': 'Different password on redeploy'}), 'already configured')
        with self.engine.connect() as conn:
            account = conn.execute(select(users)).mappings().one()
        self.assertTrue(PASSWORDS.verify(account['password_hash'], self.settings['INITIAL_ADMIN_PASSWORD']))

    def test_missing_credentials_keep_manual_setup(self):
        self.assertIn('not configured', bootstrap_admin(self.engine, {}))
        self.assertTrue(Service(self.engine, 'secret').auth('status', {}, '')[0]['setup_required'])
        with self.assertRaises(ValueError):
            bootstrap_admin(self.engine, {'INITIAL_ADMIN_EMAIL': 'admin@attendance.test'})

    def test_cannot_promote_existing_student(self):
        with self.engine.begin() as conn:
            conn.execute(insert(users).values(id='student', email=self.settings['INITIAL_ADMIN_EMAIL'],
                name='Student', role='student', password_hash='unused', roll_no='S1',
                department='', mobile='', created_at=1))
        with self.assertRaises(ValueError):
            bootstrap_admin(self.engine, self.settings)
        with self.engine.connect() as conn:
            self.assertEqual(conn.execute(select(users.c.role)).scalar(), 'student')
