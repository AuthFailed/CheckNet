# Translations

CheckNet is authored in **Russian** and translated into 12 more languages:
English, 简体中文, Español, Français, Deutsch, 日本語, Português (BR), 한국어,
Italiano, Türkçe, العربية, हिन्दी.

All translations live in one Apple **String Catalog**:
`App/Resources/Localizable.xcstrings`. The Russian text is the *key*; every
other language is a value under it.

## How to contribute

**Easiest — the web editor (Weblate).**
Suggest or fix translations in the browser, no git or Xcode needed. Changes come
back as pull requests automatically:

> 🔗 **<add the Weblate project URL here once it is set up>**

(Weblate is free and open-source, and free to host for public libre projects on
`hosted.weblate.org`. See “Maintainer: setting up Weblate” below.)

**Or — one string at a time.**
Open a [Translation fix issue](../../issues/new?template=translation.yml).

**Or — directly.**
Edit `App/Resources/Localizable.xcstrings` (Xcode’s String Catalog editor, or by
hand) and open a PR. CI validates it (see below).

## The one rule that must never break

Format placeholders — `%@`, `%lld`, `%1$@`, `%2$@` … — must appear in a
translation **the same number and kind** as in the Russian key. Only their
*order* may change (use the positional `%1$…`, `%2$…` forms to reorder).

Why it matters: Foundation formats the *translated* string against the arguments
the code passed. A `%@` where the key had `%lld` reads an integer as a pointer —
an instant crash, in that one language. CI blocks this.

## Checking translations locally

```sh
python3 scripts/check_string_catalog.py            # CI gate: completeness + placeholders
python3 scripts/check_string_catalog.py --report   # per-language completeness table
python3 scripts/check_string_catalog.py --todo de  # keys still missing a German translation
python3 scripts/check_string_catalog.py --orphans  # Russian strings not yet in the catalog
```

The same gate runs in CI on every pull request.

`--orphans` lists Russian strings in the code that are shown through
`LocalizedStringKey(variable)` and were never added to the catalog — the
compiler cannot extract those, so they stay Russian until added by hand.

## Maintainer: setting up Weblate

1. Give the repository an OSI-approved license (required for free libre hosting).
2. Sign up at <https://hosted.weblate.org> and request free hosting for the
   public project.
3. Add a component pointing at `App/Resources/Localizable.xcstrings`
   (format: *Apple String Catalog*), source language **ru**.
4. Connect the GitHub repository and enable “push on commit” so approved
   suggestions arrive as pull requests.
5. Put the project URL in the “web editor” link above.

Self-hosting is also possible — Weblate is AGPL-3.0.
