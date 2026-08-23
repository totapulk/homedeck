"""Fetches the third-party Dreame cloud client this sidecar is built on.

A script rather than committed files: this is someone else's work (MIT, Tasshack) and dropping
3,700 lines of it into a portfolio repository would blur what was written here and what was
borrowed. Only three of the eight modules are taken; the rest is a map decoder needing Pillow,
NumPy and a V8 engine, which a button does not.

    python fetch_dreame.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "https://github.com/Tasshack/dreame-vacuum.git"

# Pinned: the v2 line is the one that speaks to Dreamehome accounts at all, and floating on a
# branch would mean the vacuum breaking on a day nobody touched this repository.
COMMIT = "3720223e11353aba622f8da34c9041586865aa48"

SOURCE = "custom_components/dreame_vacuum/dreame"
MODULES = ("protocol.py", "types.py", "exceptions.py")

VENDOR = Path(__file__).parent / "vendor" / "dreame"

# Upstream's __init__ imports the device and map modules we are here to avoid. protocol.py needs
# one name from it, so supply that and nothing else.
INIT = '''"""Minimal package init: upstream's own pulls in the map decoder we deliberately skip."""

VERSION = "v2.0.0b25"
'''

# protocol.py subclasses MiIOProtocol for DreameVacuumDeviceProtocol — the *local* protocol, the
# one the vendor switches off on cloud-paired models and which this sidecar therefore never
# instantiates. Installing python-miio to obtain it costs cryptography, zeroconf and netifaces,
# the last of which is an unmaintained C extension with no wheel for current Pythons. So the
# import gets a class to find, and nothing more.
MIIO_INIT = '''"""Not python-miio. See fetch_dreame.py for why this stands in for it."""
'''

MIIO_PROTOCOL = '''"""A stand-in for python-miio's local-protocol base class.

The vendored dreame client subclasses this to speak to a robot over the local network. HomeDeck
reaches its robot through the vendor cloud instead, because the local API is switched off on
paired devices, so the subclass is defined and never used. Anything that does try to use it
should say so loudly rather than fail somewhere subtler.
"""


class MiIOProtocol:
    def __init__(self, *args, **kwargs):
        raise NotImplementedError(
            "The local MiIO protocol is not available in this sidecar: it speaks to the vendor "
            "cloud. See sidecar/README.md."
        )
'''


def main() -> int:
    with tempfile.TemporaryDirectory() as scratch:
        checkout = Path(scratch) / "dreame-vacuum"

        print(f"Cloning {REPO} at {COMMIT[:10]}…")
        run(["git", "init", "--quiet", str(checkout)])
        run(["git", "remote", "add", "origin", REPO], cwd=checkout)
        run(["git", "fetch", "--quiet", "--depth", "1", "origin", COMMIT], cwd=checkout)
        run(["git", "checkout", "--quiet", "FETCH_HEAD"], cwd=checkout)

        VENDOR.mkdir(parents=True, exist_ok=True)
        for module in MODULES:
            source = checkout / SOURCE / module
            if not source.exists():
                print(f"error: {module} is not where it used to be", file=sys.stderr)
                return 1

            shutil.copy2(source, VENDOR / module)
            print(f"  {module}")

        shutil.copy2(checkout / "LICENSE", VENDOR / "LICENSE")
        (VENDOR / "__init__.py").write_text(INIT, encoding="utf-8")

        miio = VENDOR.parent / "miio"
        miio.mkdir(parents=True, exist_ok=True)
        (miio / "__init__.py").write_text(MIIO_INIT, encoding="utf-8")
        (miio / "miioprotocol.py").write_text(MIIO_PROTOCOL, encoding="utf-8")
        print("  miio (stand-in)")

    print(f"\nDone. {VENDOR} is ignored by git; rerun this after a clean checkout.")
    return 0


def run(command: list[str], cwd: Path | None = None) -> None:
    subprocess.run(command, cwd=cwd, check=True)


if __name__ == "__main__":
    raise SystemExit(main())
