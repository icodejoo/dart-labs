"""Offline HTTP fixture contract tests. Never imports or calls adb/Flutter."""
import functools
import http.server
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

from coverage_gap_media import Handler


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.payload=bytes(range(256))*4
        Path(self.tmp.name,'long.mp4').write_bytes(self.payload)
        Path(self.tmp.name,'master.m3u8').write_text('#EXTM3U\nlow/index.m3u8\n',encoding='utf-8')
        self.server=http.server.ThreadingHTTPServer(('127.0.0.1',0),
            functools.partial(Handler,directory=self.tmp.name))
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()
        self.base='http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        self.tmp.cleanup()

    def request(self,path,byte_range=None):
        request=urllib.request.Request(self.base+path,
            headers={'Range':byte_range} if byte_range else {})
        return urllib.request.urlopen(request,timeout=10)

    def test_ranges_and_cache_busting(self):
        for value,expected in [('bytes=12-34',self.payload[12:35]),
                               ('bytes=1000-',self.payload[1000:]),
                               ('bytes=-17',self.payload[-17:])]:
            with self.subTest(value=value),self.request('/long.mp4?t=123',value) as response:
                self.assertEqual(response.status,206)
                self.assertEqual(response.read(),expected)
                self.assertEqual(int(response.headers['Content-Length']),len(expected))
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request('/long.mp4','bytes=2000-')
        self.assertEqual(error.exception.code,416)
        error.exception.close()

    def test_delayed_manifest_keeps_relative_paths(self):
        with self.request('/delayed/master.m3u8?t=123') as response:
            self.assertIn(b'low/index.m3u8?t=123',response.read())
            self.assertEqual(response.headers['Cache-Control'],'no-store')

    def test_late_error_is_explicit_and_observable(self):
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request('/late-error?t=123')
        self.assertEqual(error.exception.code,404)
        error.exception.close()
        self.assertTrue(self.server.late_error)


if __name__=='__main__':
    unittest.main(verbosity=2)
