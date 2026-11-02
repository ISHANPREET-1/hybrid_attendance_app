import concurrent.futures
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from server import create_server


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / 'test.sqlite3'
        self.server = create_server(0, self.db, Path(self.temp.name) / 'web')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, path, data=None, origin=None):
        headers = {'Content-Type': 'application/json'}
        if origin:
            headers['Origin'] = origin
        req = urllib.request.Request(self.url + path,
            data=json.dumps(data).encode() if data is not None else None,
            headers=headers)
        try:
            response = urllib.request.urlopen(req)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def register(self):
        return self.request('/api/profiles', {'role': 'student', 'profile': {
            'studentName': 'API Test', 'studentRollNo': 'TEST-1'}})

    def test_persistence_and_concurrent_duplicates(self):
        self.assertEqual(self.register()[0], 200)
        data = {'rollNo': 'TEST-1', 'subject': 'Operating Systems', 'courseCode': '82703', 'date': '1999-01-01'}
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.request('/api/attendance', data), range(6)))
        self.assertEqual(sum(status == 201 for status, _ in results), 1)
        records = self.request('/api/attendance')[1]['records']
        self.assertEqual(len(records), 1)
        self.assertNotEqual(records[0]['date'], '1999-01-01')
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.server = create_server(0, self.db)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.assertEqual(self.request('/api/attendance')[1]['records'], records)

    def test_validation_health_and_origin(self):
        self.assertEqual(self.request('/api/health')[1]['status'], 'ok')
        self.assertEqual(self.request('/api/profiles', {'role': 'admin'})[0], 400)
        self.assertEqual(self.request('/api/attendance', {'rollNo': 'missing', 'subject': 'X', 'courseCode': '1'})[0], 400)
        self.assertEqual(self.request('/api/profiles', {}, 'https://example.com')[0], 403)
        self.assertEqual(self.request('/api/unknown')[0], 404)
        self.assertEqual(self.request('/')[0], 503)

    def test_frontend_host_serves_build_without_directory_listing(self):
        web = Path(self.temp.name) / 'web'
        web.mkdir()
        (web / 'index.html').write_text('<html>Hybrid Attendance</html>')
        (web / 'assets').mkdir()
        with urllib.request.urlopen(self.url + '/') as response:
            self.assertIn(b'Hybrid Attendance', response.read())
        self.assertEqual(self.request('/assets/')[0], 404)
        self.assertEqual(self.request('/api/../server.py')[0], 404)


if __name__ == '__main__':
    unittest.main()
