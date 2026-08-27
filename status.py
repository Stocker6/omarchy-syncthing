#!/usr/bin/env python3
"""Syncthing helper for the lee.syncthing Omarchy bar widget.

Reads the GUI address and API key from Syncthing's config, then talks to the
local REST API. Prints exactly one JSON object on stdout so the QML service
only has to parse a single blob.

Usage:
  status.py status    # full status snapshot (default)
  status.py gui-url   # {"ok": true, "url": "..."}
  status.py pause     # pause all devices
  status.py resume    # resume all devices
  status.py scan      # rescan all folders
"""

import json
import shutil
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

CONFIG_CANDIDATES = [
    Path.home() / ".local/state/syncthing/config.xml",
    Path.home() / ".config/syncthing/config.xml",
]
TIMEOUT = 4


def emit(payload):
    print(json.dumps(payload))
    sys.exit(0)


def fail(message, **extra):
    payload = {"ok": False, "lastError": message}
    payload.update(extra)
    emit(payload)


def read_gui():
    """Return (api_key, base_url) from the Syncthing config, or None."""
    for path in CONFIG_CANDIDATES:
        if not path.exists():
            continue
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            continue
        gui = root.find("gui")
        if gui is None:
            continue
        key_el = gui.find("apikey")
        addr_el = gui.find("address")
        key = (key_el.text or "").strip() if key_el is not None and key_el.text else ""
        address = (addr_el.text or "").strip() if addr_el is not None and addr_el.text else "127.0.0.1:8384"
        scheme = "https" if gui.get("tls", "false") == "true" else "http"
        return key, scheme + "://" + address
    return None


def api(method, base, key, path):
    request = urllib.request.Request(
        base + path, headers={"X-API-Key": key}, method=method
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        body = response.read()
    return json.loads(body) if body else {}


def fetch_status(installed):
    gui = read_gui()
    if gui is None:
        fail(
            "Syncthing config not found",
            installed=installed,
            running=False,
        )
    key, base = gui
    try:
        system = api("GET", base, key, "/rest/system/status")
        connections = api("GET", base, key, "/rest/system/connections").get(
            "connections"
        ) or {}
        config = api("GET", base, key, "/rest/config")
    except (urllib.error.URLError, OSError, ValueError):
        fail(
            "Syncthing API unreachable",
            installed=installed,
            running=False,
            api=base,
        )

    my_id = system.get("myID", "")
    config_devices = config.get("devices", [])
    config_folders = config.get("folders", [])

    self_name = ""
    for device in config_devices:
        if device.get("deviceID") == my_id:
            self_name = device.get("name") or ""
    if not self_name:
        self_name = socket.gethostname()

    devices = []
    for device in config_devices:
        device_id = device.get("deviceID", "")
        if device_id == my_id or not device_id:
            continue
        info = connections.get(device_id, {})
        devices.append(
            {
                "id": device_id,
                "name": device.get("name") or (device_id[:7] + "…"),
                "connected": bool(info.get("connected")),
                "paused": bool(device.get("paused")) or bool(info.get("paused")),
                "address": info.get("address") or "",
                "clientVersion": info.get("clientVersion") or "",
                "linkType": info.get("type") or "",
                "completion": None,
            }
        )
    for device in devices:
        if not device["connected"]:
            continue
        try:
            completion = api(
                "GET", base, key, "/rest/db/completion?device=" + device["id"]
            )
            device["completion"] = completion.get("completion")
        except (urllib.error.URLError, OSError, ValueError):
            pass

    folders = []
    for folder in config_folders:
        folder_id = folder.get("id", "")
        row = {
            "id": folder_id,
            "label": folder.get("label") or folder_id,
            "paused": bool(folder.get("paused")),
            "state": "unknown",
            "completion": None,
            "globalBytes": 0,
            "needBytes": 0,
            "errors": 0,
            "invalid": "",
        }
        try:
            if not row["paused"]:
                # /rest/db/status is expensive on the daemon, so skip it for
                # paused folders — the UI renders "Paused" from the flag alone.
                status = api(
                    "GET",
                    base,
                    key,
                    "/rest/db/status?folder=" + urllib.parse.quote(folder_id, safe=""),
                )
                global_bytes = float(status.get("globalBytes") or 0)
                in_sync = float(status.get("inSyncBytes") or 0)
                row["state"] = status.get("state") or "unknown"
                row["globalBytes"] = global_bytes
                row["needBytes"] = float(status.get("needBytes") or 0)
                row["errors"] = int(status.get("pullErrors") or 0)
                row["invalid"] = status.get("invalid") or ""
                if global_bytes > 0:
                    row["completion"] = 100.0 * in_sync / global_bytes
        except (urllib.error.URLError, OSError, ValueError):
            pass
        folders.append(row)

    remotes = devices
    paused_all = len(remotes) > 0 and all(item["paused"] for item in remotes)
    syncing = any(
        item["state"] in ("syncing", "scanning", "sync-preparing", "wait-for-scan")
        and not item["paused"]
        for item in folders
    )
    error_state = any(
        item["errors"] > 0 or item["state"] == "error" or bool(item["invalid"])
        for item in folders
    )

    emit(
        {
            "ok": True,
            "installed": installed,
            "running": True,
            "api": base,
            "myName": self_name,
            "uptime": system.get("uptime", 0),
            "pausedAll": paused_all,
            "syncing": syncing,
            "errorState": error_state,
            "devices": devices,
            "folders": folders,
        }
    )


def run_control(command, folder_id=None):
    gui = read_gui()
    if gui is None:
        fail("Syncthing config not found")
    key, base = gui
    paths = {
        "pause": "/rest/system/pause",
        "resume": "/rest/system/resume",
        "scan": "/rest/db/scan",
    }
    path = paths[command]
    if folder_id:
        path += "?folder=" + urllib.parse.quote(folder_id, safe="")
    try:
        api("POST", base, key, path)
    except (urllib.error.URLError, OSError) as error:
        fail("Syncthing {} failed: {}".format(command, error))
    emit({"ok": True})


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    installed = shutil.which("syncthing") is not None

    if command == "status":
        fetch_status(installed)
    elif command == "gui-url":
        gui = read_gui()
        if gui is None:
            fail("Syncthing config not found")
        emit({"ok": True, "url": gui[1]})
    elif command in ("pause", "resume", "scan"):
        folder_id = sys.argv[2] if len(sys.argv) > 2 else None
        run_control(command, folder_id)
    else:
        fail("Unknown command: {}".format(command))


if __name__ == "__main__":
    main()
