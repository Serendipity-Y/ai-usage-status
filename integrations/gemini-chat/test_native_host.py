import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone, timedelta

HOST = Path(__file__).with_name("native_host.py")
ORIGIN = "chrome-extension://adknhodjhiendoaooadaiigomipfcbgj/"


class ReportOrderTests(unittest.TestCase):
    def test_parallel_writers_and_newer_reset(self):
        with tempfile.TemporaryDirectory() as home:
            env = dict(os.environ, HOME=home)
            now = datetime.now(timezone.utc)

            def send(offset, used):
                stamp = (now + timedelta(seconds=offset)).isoformat()
                data = json.dumps({"fetchedAt": stamp, "pools": [
                    {"poolType": kind, "percentageUsed": used, "windowRefreshesAt": None}
                    for kind in ("GXU_FIVE_HOURLY", "GXU_WEEKLY")]}).encode()
                child = subprocess.Popen([sys.executable, HOST, ORIGIN], env=env,
                                         stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                child.stdin.write(struct.pack("=I", len(data)) + data)
                child.stdin.close()
                return child

            def finish(child):
                with child, child.stdout:
                    reply = child.stdout.read()
                    self.assertTrue(json.loads(reply[4:])["ok"])
                    self.assertEqual(child.wait(timeout=5), 0)

            dest = Path(home) / "Library/Application Support/CodexUsageStatus/gemini-chat-chrome.json"
            finish(send(-10, 0.25))
            older = [send(-i, 0.10) for i in range(20, 28)]
            for child in older:
                finish(child)
            self.assertEqual(json.loads(dest.read_text())["weekly"]["used"], 25)
            finish(send(0, 0))
            self.assertEqual(json.loads(dest.read_text())["weekly"]["used"], 0)


if __name__ == "__main__":
    unittest.main()
