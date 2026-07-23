#!/usr/bin/env python3
"""Validate and report on Localizable.xcstrings.

As a CI gate (default, no arguments) it fails on the mistakes that actually
ship broken localizations:

1. A translation whose format specifiers disagree with its key. Foundation
   formats the *translated* value against the arguments the call site passed,
   so `%@` in a translation of a `%lld` key makes it read an integer as an
   object pointer — an immediate EXC_BAD_ACCESS, in that language only.
2. A translatable key that is missing a translation in any supported language,
   which silently ships as Russian there.
3. (warning) A Russian literal that reaches the UI through
   `LocalizedStringKey(variable)` but was never added to the catalog. The
   compiler cannot extract those keys, so nothing else notices; the lookup
   just returns the Russian key itself.

Modes:
    python3 scripts/check_string_catalog.py               # CI gate (exit 1 on error)
    python3 scripts/check_string_catalog.py --report      # per-language completeness table
    python3 scripts/check_string_catalog.py --todo [lang] # keys still missing a translation
    python3 scripts/check_string_catalog.py --orphans     # Russian literals not in the catalog
"""
import json
import re
import sys
import glob
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"

# Every language the app ships (see CFBundleLocalizations in project.yml), minus
# the Russian source. A translatable key must be present in all of them.
TARGET_LANGS = ["en", "zh-Hans", "es", "fr", "de", "ja", "pt-BR", "ko", "it", "tr", "ar", "hi"]

SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|u|d|f|%)")


def specifiers(text):
    """Specifier types in order. Literal `%%` is not an argument."""
    return [m.group(2) for m in SPEC.finditer(text) if m.group(2) != "%"]


def load():
    return json.loads(CATALOG.read_text(encoding="utf-8"))


def translatable(strings):
    """(key, entry) pairs that should carry translations."""
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        if key == "":
            continue
        yield key, entry


def translation(entry, lang):
    """The translated value for `lang`, or None if absent/empty."""
    unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {})
    value = unit.get("value")
    return value if value else None


def dynamic_key_candidates():
    """Russian string literals in source that are not interpolated.

    An interpolated literal cannot be a catalog key, so only plain ones count.
    This is a heuristic — it over-reports strings that never reach the UI.
    """
    literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
    cyrillic = re.compile(r"[а-яА-ЯёЁ]")
    found = {}
    for pattern in ("App/**/*.swift", "Shared/**/*.swift", "Packages/NetworkKit/Sources/**/*.swift"):
        for path in glob.glob(str(ROOT / pattern), recursive=True):
            for number, line in enumerate(open(path, encoding="utf-8"), 1):
                if line.lstrip().startswith("//"):
                    continue
                for match in literal.finditer(line):
                    value = match.group(1)
                    if len(value) < 2 or not cyrillic.search(value):
                        continue
                    if "\\(" in value:
                        continue
                    found.setdefault(value, f"{Path(path).name}:{number}")
    return found


# MARK: Modes

def report(strings):
    """Per-language completeness / quality table."""
    keys = list(translatable(strings))
    total = len(keys)
    print(f"String catalog — {total} translatable keys, {len(TARGET_LANGS)} target languages\n")
    print(f"{'lang':8} {'done':>6} {'missing':>8} {'review':>7} {'complete':>9}")
    print("-" * 42)
    worst = 0
    for lang in TARGET_LANGS:
        done = missing = review = 0
        for _, entry in keys:
            unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {})
            if not unit.get("value"):
                missing += 1
            else:
                done += 1
                if unit.get("state") == "needs_review":
                    review += 1
        pct = 100.0 * done / total if total else 100.0
        worst = max(worst, missing)
        print(f"{lang:8} {done:>6} {missing:>8} {review:>7} {pct:>8.1f}%")
    return worst


def todo(strings, only_lang=None):
    """Keys still missing a translation, grouped by language."""
    langs = [only_lang] if only_lang else TARGET_LANGS
    for lang in langs:
        missing = [k for k, e in translatable(strings) if translation(e, lang) is None]
        print(f"# {lang}: {len(missing)} missing")
        for k in missing:
            print(f"  {k!r}")


def orphans(strings):
    cands = {k: v for k, v in dynamic_key_candidates().items() if k not in strings}
    print(f"{len(cands)} Russian literals not in the catalog "
          f"(shown via LocalizedStringKey(variable) they stay Russian):")
    for key, where in sorted(cands.items()):
        print(f"  {where}: {key!r}")


def gate(strings):
    """CI gate: specifier mismatches and per-language completeness."""
    mismatched, missing = [], []
    for key, entry in translatable(strings):
        want = specifiers(key)
        for lang in TARGET_LANGS:
            value = translation(entry, lang)
            if value is None:
                missing.append((key, lang))
                continue
            got = specifiers(value)
            if got != want:
                mismatched.append((key, lang, value, want, got))

    for key, lang, value, want, got in mismatched:
        print(f"specifier mismatch [{lang}] {key!r} -> {value!r}: expected {want}, got {got}")
    if missing:
        per = {}
        for _, lang in missing:
            per[lang] = per.get(lang, 0) + 1
        print("missing translations: " + ", ".join(f"{l}={n}" for l, n in sorted(per.items())))

    if mismatched or missing:
        print(f"\nFAILED: {len(mismatched)} specifier mismatches, {len(missing)} missing translations")
        print("Run: python3 scripts/check_string_catalog.py --report        (per-language overview)")
        print("     python3 scripts/check_string_catalog.py --todo <lang>   (what to translate)")
        return 1

    print(f"OK: {len(list(translatable(strings)))} keys complete across {len(TARGET_LANGS)} languages, "
          f"no specifier mismatches")
    stray = {k: v for k, v in dynamic_key_candidates().items() if k not in strings}
    if stray:
        print(f"\nwarning: {len(stray)} Russian literals are not in the catalog "
              f"(see --orphans). Any shown via LocalizedStringKey(variable) stays Russian.")
    return 0


def main():
    args = sys.argv[1:]
    strings = load()["strings"]
    if args and args[0] == "--report":
        report(strings)
        return 0
    if args and args[0] == "--todo":
        todo(strings, args[1] if len(args) > 1 else None)
        return 0
    if args and args[0] == "--orphans":
        orphans(strings)
        return 0
    return gate(strings)


if __name__ == "__main__":
    sys.exit(main())
