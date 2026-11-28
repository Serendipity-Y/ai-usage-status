#!/usr/bin/python3
"""Chrome starts this host for one quota report and reads one framed acknowledgement."""
import fcntl
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import tempfile
from datetime import datetime, timezone

ORIGIN = "chrome-extension://adknhodjhiendoaooadaiigomipfcbgj/"
DEST = Path.home() / "Library/Application Support/CodexUsageStatus/gemini-chat-chrome.json"


def parse_time(text):
    normalized = text.strip().replace("Z", "+00:00")
    # Python 3.9 fromisoformat only accepts 0, 3, or 6 fractional digits.
    normalized = re.sub(
        r"\.(\d+)(?=[+-]\d{2}:\d{2}$)",
        lambda m: "." + (m.group(1)[:6].ljust(6, "0")),
        normalized,
    )
    value = datetime.fromisoformat(normalized)
    if value.tzinfo is None:
        raise ValueError("missing timezone")
    return value.timestamp()


def normalize(report, now):
    observed = parse_time(report["fetchedAt"])
    if not -10 <= now - observed <= 180:
        raise ValueError("expired report")
    result = {"observedAt": observed}
    names = {"GXU_FIVE_HOURLY": "current", "GXU_WEEKLY": "weekly"}
    for pool in report["pools"]:
        key = names[pool["poolType"]]
        value = pool["percentageUsed"]
        if key in result or type(value) not in (int, float) or not 0 <= value <= 1:
            raise ValueError("invalid quota")
        reset = pool["windowRefreshesAt"]
        result[key] = {"used": math.floor(value * 100 + 0.5),
                       "resetsAt": parse_time(reset) if reset else None}
    if not all(key in result for key in names.values()):
        raise ValueError("missing quota")
    return result


def receive():
    size, = struct.unpack("=I", sys.stdin.buffer.read(4))
    if not 0 < size <= 16384:
        raise ValueError("invalid message length")
    data = sys.stdin.buffer.read(size)
    if len(data) != size:
        raise ValueError("incomplete message")
    reading = normalize(json.loads(data), datetime.now(timezone.utc).timestamp())
    DEST.parent.mkdir(parents=True, exist_ok=True)
    # Lock a stable sibling: replacing the snapshot changes its inode.
    with DEST.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            previous = json.loads(DEST.read_text())
            stamp = previous["observedAt"]
            usable = all(type(previous[k]["used"]) is int and 0 <= previous[k]["used"] <= 100
                         for k in ("current", "weekly"))
            if usable and reading["observedAt"] <= stamp <= datetime.now(timezone.utc).timestamp() + 10:
                return
        except (FileNotFoundError, ValueError, KeyError, TypeError):
            pass
        with tempfile.NamedTemporaryFile(mode="w", dir=DEST.parent, delete=False) as out:
            try:
                json.dump(reading, out, allow_nan=False)
                out.flush()
                os.replace(out.name, DEST)
            finally:
                if os.path.exists(out.name):
                    os.unlink(out.name)


if __name__ == "__main__":
    if sys.argv[1:2] != [ORIGIN]:
        sys.exit(1)
    try:
        receive()
        ok = True
    except (ValueError, KeyError, TypeError, AttributeError, OverflowError, OSError, struct.error):
        ok = False
    reply = json.dumps({"ok": ok}).encode()
    sys.stdout.buffer.write(struct.pack("=I", len(reply)) + reply)
