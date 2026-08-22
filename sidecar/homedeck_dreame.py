"""A small HTTP front door for one robot vacuum.

The vendor disables the local API on cloud-paired models, so reaching this machine means its
cloud: an obfuscated login, then MQTT. Rather than reimplement that in C#, this process uses the
library that already maintains it and exposes three endpoints to the backend. See README.md.

    python fetch_dreame.py                       # once
    pip install -r requirements.txt              # once
    python homedeck_dreame.py --probe            # what does my account see?
    python homedeck_dreame.py                    # serve

Environment:

    DREAME_USERNAME   account e-mail
    DREAME_PASSWORD   account password
    DREAME_COUNTRY    server region, e.g. eu (default)
    DREAME_DEVICE     which robot to control; required when the account has more than one
    DREAME_BIND       interface to listen on (default 127.0.0.1)
    DREAME_PORT       port to listen on (default 5081)
"""

from __future__ import annotations

import json
import logging
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "vendor"))

try:
    from dreame.protocol import DreameVacuumDreameHomeCloudProtocol
except ModuleNotFoundError as missing:
    raise SystemExit(
        f"{missing}\n\nRun 'python fetch_dreame.py' and 'pip install -r requirements.txt' first."
    ) from missing

_LOG = logging.getLogger("homedeck.dreame")

# MIoT addresses, from the vendored types.py. Actions and properties are numbered on the wire.
START = (2, 1)
CHARGE = (3, 1)
STATE = (2, 1)
BATTERY = (3, 1)

# The robot reports far more states than a control surface should show.
_CLEANING = {1, 7, 12, 15, 19, 20, 25, 26, 27}
_RETURNING = {5, 10, 17, 18}
_DOCKED = {2, 6, 13, 24}
_ERROR = {4}

_STATE_NAMES = {
    1: "SWEEPING", 2: "IDLE", 3: "PAUSED", 4: "ERROR", 5: "RETURNING", 6: "CHARGING",
    7: "MOPPING", 8: "DRYING", 9: "WASHING", 10: "RETURNING_TO_WASH", 11: "BUILDING",
    12: "SWEEPING_AND_MOPPING", 13: "CHARGING_COMPLETED", 14: "UPGRADING", 15: "CLEAN_SUMMON",
    16: "STATION_RESET", 17: "RETURNING_INSTALL_MOP", 18: "RETURNING_REMOVE_MOP",
    19: "WATER_CHECK", 20: "CLEAN_ADD_WATER", 21: "WASHING_PAUSED", 22: "AUTO_EMPTYING",
    23: "REMOTE_CONTROL", 24: "SMART_CHARGING", 25: "SECOND_CLEANING", 26: "HUMAN_FOLLOWING",
    27: "SPOT_CLEANING",
}


class VacuumUnavailable(Exception):
    """The cloud said no, or said nothing."""


class Robot:
    """One vacuum, and a cloud session that logs itself back in when the token expires."""

    def __init__(self, username: str, password: str, country: str, device_id: str | None):
        self._username = username
        self._password = password
        self._country = country
        self._wanted = device_id
        self._cloud: DreameVacuumDreameHomeCloudProtocol | None = None
        self._lock = threading.Lock()

    def state(self) -> dict:
        with self._lock:
            cloud = self._connect()
            values = cloud.send(
                "get_properties",
                [
                    {"did": str(cloud.device_id), "siid": STATE[0], "piid": STATE[1]},
                    {"did": str(cloud.device_id), "siid": BATTERY[0], "piid": BATTERY[1]},
                ],
            )

        return _describe(values)

    def start(self) -> dict:
        self._act(*START)
        return self.state()

    def dock(self) -> dict:
        self._act(*CHARGE)
        return self.state()

    def devices(self) -> list[dict]:
        """Every robot on the account, for --probe."""
        with self._lock:
            cloud = self._login()
            records = _records(cloud.get_devices() or {})

        return [_summarise(record) for record in records]

    def _act(self, siid: int, aiid: int) -> None:
        with self._lock:
            cloud = self._connect()
            result = cloud.send(
                "action",
                {"did": str(cloud.device_id), "siid": siid, "aiid": aiid, "in": []},
            )

        if result is None:
            raise VacuumUnavailable("the robot did not acknowledge the command")

    def _connect(self) -> DreameVacuumDreameHomeCloudProtocol:
        if self._cloud is not None and self._cloud.logged_in and self._cloud.device_id:
            return self._cloud

        cloud = self._login()
        records = _records(cloud.get_devices() or {})
        if not records:
            raise VacuumUnavailable("this account has no devices on it")

        chosen = self._choose(records)

        # Hands the library the did, uid and MQTT host it needs for everything afterwards.
        cloud._handle_device_info(chosen)
        cloud.connect()

        self._cloud = cloud
        _LOG.info("Connected to %s", _summarise(chosen))
        return cloud

    def _choose(self, records: list[dict]) -> dict:
        if self._wanted:
            for record in records:
                if str(record.get("did")) == self._wanted:
                    return record
            raise VacuumUnavailable(f"no device with id {self._wanted} on this account")

        # An account can hold robots that are not yours to command — a shared one, a relative's.
        # Guessing from list order would work until the day the order changed.
        if len(records) > 1:
            listing = ", ".join(f"{_summarise(r)['name']} ({r.get('did')})" for r in records)
            raise VacuumUnavailable(f"set DREAME_DEVICE to one of: {listing}")

        return records[0]

    def _login(self) -> DreameVacuumDreameHomeCloudProtocol:
        if self._cloud is not None and self._cloud.logged_in:
            return self._cloud

        cloud = DreameVacuumDreameHomeCloudProtocol(
            self._username, self._password, "dreame", self._country
        )
        if not cloud.login():
            raise VacuumUnavailable("the cloud rejected these credentials")

        self._cloud = cloud
        return cloud


def _summarise(record: dict) -> dict:
    return {
        "did": str(record.get("did")),
        "name": record.get("customName")
        or record.get("deviceInfo", {}).get("displayName")
        or record.get("model"),
        "model": record.get("model"),
        "online": record.get("online"),
    }


def _records(listing: dict) -> list[dict]:
    """Digs the device list out of a reply whose field names the vendor keeps rearranging."""
    for value in listing.values():
        if isinstance(value, dict):
            for inner in value.values():
                if isinstance(inner, list) and inner and isinstance(inner[0], dict):
                    return inner
        elif isinstance(value, list) and value and isinstance(value[0], dict):
            return value
    return []


def _describe(values) -> dict:
    if not values:
        raise VacuumUnavailable("the robot did not report its state")

    readings: dict[tuple[int, int], object] = {}
    for entry in values:
        if isinstance(entry, dict) and entry.get("code") in (0, None):
            readings[(entry.get("siid"), entry.get("piid"))] = entry.get("value")

    raw = readings.get(STATE)
    battery = readings.get(BATTERY)
    code = raw if isinstance(raw, int) else None

    if code in _CLEANING:
        activity = "Cleaning"
    elif code in _RETURNING:
        activity = "Returning"
    elif code in _DOCKED:
        activity = "Docked"
    elif code in _ERROR:
        activity = "Error"
    else:
        activity = "Unknown"

    return {
        "activity": activity,
        "batteryPercent": battery if isinstance(battery, int) else None,
        "raw": _STATE_NAMES.get(code, str(code)),
    }


class Handler(BaseHTTPRequestHandler):
    robot: Robot

    def do_GET(self) -> None:  # noqa: N802 - the stdlib decides this name
        if self.path.rstrip("/") in ("", "/state"):
            self._respond(self.robot.state)
        else:
            self._send(404, {"error": "no such endpoint"})

    def do_POST(self) -> None:  # noqa: N802
        route = {"/start": self.robot.start, "/dock": self.robot.dock}
        action = route.get(self.path.rstrip("/"))
        if action is None:
            self._send(404, {"error": "no such endpoint"})
        else:
            self._respond(action)

    def _respond(self, action) -> None:
        try:
            self._send(200, action())
        except VacuumUnavailable as failure:
            # 503, not 500: the request was fine and the robot was not.
            self._send(503, {"error": str(failure)})
        except Exception as failure:
            _LOG.exception("Unexpected failure")
            self._send(503, {"error": f"{type(failure).__name__}: {failure}"})

    def _send(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt: str, *args) -> None:
        _LOG.debug(fmt, *args)


def robot_from_environment() -> Robot:
    username = os.environ.get("DREAME_USERNAME")
    password = os.environ.get("DREAME_PASSWORD")
    if not username or not password:
        raise SystemExit("Set DREAME_USERNAME and DREAME_PASSWORD first.")

    return Robot(
        username,
        password,
        os.environ.get("DREAME_COUNTRY", "eu"),
        os.environ.get("DREAME_DEVICE") or None,
    )


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    robot = robot_from_environment()

    if "--probe" in sys.argv:
        try:
            found = {"devices": robot.devices()}
            try:
                found["state"] = robot.state()
            except VacuumUnavailable as failure:
                found["state"] = {"error": str(failure)}

            print(json.dumps(found, indent=2))
        except VacuumUnavailable as failure:
            # Every way this fails is a setup question, so a stack trace would be noise.
            print(f"Could not reach the account: {failure}", file=sys.stderr)
            return 1
        return 0

    Handler.robot = robot

    # Loopback by default: this process holds cloud credentials and has no authentication.
    bind = os.environ.get("DREAME_BIND", "127.0.0.1")
    port = int(os.environ.get("DREAME_PORT", "5081"))

    server = ThreadingHTTPServer((bind, port), Handler)
    _LOG.info("Listening on http://%s:%d", bind, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        _LOG.info("Stopping")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
