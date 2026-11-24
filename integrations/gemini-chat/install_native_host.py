#!/usr/bin/env python3
"""Install the per-user Chrome Native Messaging host for Gemini chat quota."""
import json
from pathlib import Path
import shutil

HOST_NAME = "io.github.codexusagestatus.gemini_chat"
EXTENSION_ORIGIN = "chrome-extension://adknhodjhiendoaooadaiigomipfcbgj/"
HERE = Path(__file__).resolve().parent
SRC_HOST = HERE / "native_host.py"
DST_HOST = Path.home() / "Library/Application Support/CodexUsageStatus/bin/gemini-chat-native-host.py"
CHROME_MANIFEST = Path.home() / f"Library/Application Support/Google/Chrome/NativeMessagingHosts/{HOST_NAME}.json"


def main():
    DST_HOST.parent.mkdir(parents=True, exist_ok=True)
    tmp_host = DST_HOST.with_suffix(".py.new")
    shutil.copy2(SRC_HOST, tmp_host)
    tmp_host.chmod(0o700)
    tmp_host.replace(DST_HOST)

    CHROME_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "name": HOST_NAME,
        "description": "AI Usage Status Gemini chat quota receiver",
        "path": str(DST_HOST),
        "type": "stdio",
        "allowed_origins": [EXTENSION_ORIGIN],
    }
    tmp_manifest = CHROME_MANIFEST.with_suffix(".json.new")
    tmp_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    tmp_manifest.chmod(0o600)
    tmp_manifest.replace(CHROME_MANIFEST)
    print(f"Installed host: {DST_HOST}")
    print(f"Registered manifest: {CHROME_MANIFEST}")


if __name__ == "__main__":
    main()
