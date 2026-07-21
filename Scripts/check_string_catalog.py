#!/usr/bin/env python3
"""Validate Localizable.xcstrings.

Two failures this catches, both of which have actually happened:

1. A translation whose format specifiers disagree with its key. Foundation
   formats the *translated* value against the arguments the call site passed,
   so `%@` in a translation of a `%lld` key makes it read an integer as an
   object pointer — an immediate EXC_BAD_ACCESS, in that language only.
2. A translatable key with no translations at all, which silently ships as
   Russian in every other language.

Run: python3 Scripts/check_string_catalog.py
"""
import json
import re
import sys
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "App/Resources/Localizable.xcstrings"
SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|u|d|f|%)")


def specifiers(text):
    """Specifier types in order. Literal `%%` is not an argument."""
    return [m.group(2) for m in SPEC.finditer(text) if m.group(2) != "%"]


def main():
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    mismatched, untranslated = [], []

    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        want = specifiers(key)
        localizations = entry.get("localizations", {})
        if not localizations:
            untranslated.append(key)
        for lang, loc in localizations.items():
            value = loc.get("stringUnit", {}).get("value", "")
            got = specifiers(value)
            if got != want:
                mismatched.append((key, lang, value, want, got))

    for key, lang, value, want, got in mismatched:
        print(f"specifier mismatch [{lang}] {key!r} -> {value!r}: expected {want}, got {got}")
    for key in untranslated:
        print(f"no translations: {key!r}")

    if mismatched or untranslated:
        print(f"\nFAILED: {len(mismatched)} mismatched, {len(untranslated)} untranslated")
        return 1

    langs = {l for e in strings.values() for l in e.get("localizations", {})}
    print(f"OK: {len(strings)} keys, {len(langs)} languages, no specifier mismatches")
    return 0


if __name__ == "__main__":
    sys.exit(main())
