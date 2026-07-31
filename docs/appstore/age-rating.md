# Age rating (#90)

Answers to the App Store Connect → **Age Rating** questionnaire. The app is a network-diagnostics
utility with no 17+ content. Expected result: **4+**.

## Questionnaire answers (all "None" unless noted)

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Gambling (simulated) | None |
| Contests | None |
| **Unrestricted Web Access** | **No** |
| **Age Assurance / Kids Category** | not claiming Kids Category |

## Subtle points

- **Unrestricted Web Access = No.** This is about a built-in general-purpose browser (like Safari
  embedded in the app). CheckNet has none: the tools reach specific hosts on command and show the
  result of a check (headers, status, block page when a block is detected) — this is not web
  surfing. If we handed the user arbitrary web navigation, it would be Yes.
- **Kids Category — not claiming it.** The app is not for children; claiming the Kids Category would
  impose strict requirements (no external links, etc.) that don't suit us (we have links to
  bgp.tools/GitHub, etc.).
- Apple computes the final rating itself from the answers; with all "None"/"No" it is **4+**.

## What to click

1. ASC → app → Age Rating → Edit → set the values from the table → Save.
2. Confirm the rating shows as 4+ (or the Apple equivalent per region).
