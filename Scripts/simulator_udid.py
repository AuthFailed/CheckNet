#!/usr/bin/env python3
"""Print the udid of an iPhone simulator to run the UI tests on.

Which iPhones a CI image ships changes over time, and naming a device that is
missing does not fail loudly: xcodebuild falls back to the device SDK and dies
on code signing, so an absent simulator reads like a signing problem.

A "Max" is preferred because it is the phone that reports a *regular*
horizontal size class in landscape — the case the landscape tests pin down.
"""

import json
import subprocess
import sys


def main() -> int:
    listing = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "--json"],
        capture_output=True, text=True, check=True,
    ).stdout
    phones = [
        device
        for runtime in json.loads(listing)["devices"].values()
        for device in runtime
        if device["name"].startswith("iPhone")
    ]
    if not phones:
        print("no iPhone simulator is available on this machine", file=sys.stderr)
        return 1
    phones.sort(key=lambda device: "Max" not in device["name"])
    print(phones[0]["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
