---
name: user-manual-writing
description: "Process for writing a hardware/firmware product user manual that is correct: extract facts from the firmware (buttons, LEDs, USB/MIDI descriptors, settings, error codes, timeouts) instead of inventing them, keep an open-questions list for specs only the user knows (voltage, temperature, certifications), chapter structure after IEC/IEEE 82079-1, step and safety-message style, then build and visually check web + PDF. Use when asked to write, update or review a user manual, quick-start guide, operating instructions or product documentation."
---

# Writing a user manual

Tooling (docs-init, docs-build, Markdown rules) is in the skill `firmware-docs`.
This is the method. Follow the phases in order; do not start writing prose before
phase 1 is done.

## 1. Facts first, from the source

Read the firmware and the repo and write `docs/manual/facts.md` (not in `nav`, so not
published): every user-visible fact with **where it came from** (`src/ui.c:142`).

| Look for | Where it usually is |
|---|---|
| Product name, USB VID/PID, device class, MIDI port names | USB descriptors |
| Buttons: short/long/double press, combos, hold times | input / debounce / state machine code |
| LEDs, display messages: colour, blink pattern, meaning | indicator code, error handlers |
| Settings: name, range, default, where stored, how reset | config struct, flash/EEPROM layer, defaults table |
| Modes and transitions, power-on behaviour, timeouts, sleep | main loop, state machine, low-power code |
| Error and fault codes, watchdog/brown-out behaviour | fault handlers, assert paths |
| Firmware update procedure, bootloader entry | bootloader, `.mcu-profile.json`, README |
| Connectors, pinout, supply | board header, schematics/datasheets in the repo |

Rules:
- **Never invent a number.** Electrical ratings, temperature range, dimensions,
  weight, certifications, warranty: if the repo does not state it, it goes in an
  **Open questions** section of `facts.md` and stays a `TODO` in the chapter.
  Ask the user these in one batch, not one at a time.
- If code and README disagree, the code wins; note the conflict as a question.
- Behaviour the code allows but is clearly unintended is a bug to report, not a
  feature to document.

## 2. Audience and scope

Settle before writing (ask if not obvious): who reads it (musician, installer,
technician), what they already know, which language, print or web first, one
manual or a separate quick-start. Default: end user, no electronics knowledge.

## 3. Structure

`docs-init` gives the standard order (IEC/IEEE 82079-1 style): Introduction (intended
use, conventions, package contents), Safety, Getting started (device overview with a
labelled figure, first setup), Operation (one section per user task), Configuration
(every setting + firmware update), Troubleshooting (indicator codes, problem/cause/
solution table), Specifications (+ compliance, maintenance, disposal). Rename, merge
or drop chapters to fit the product; keep `nav` in `mkdocs.yml` in step.

## 4. Style

- **Task headings** say the goal: "Change the MIDI channel", not "MIDI channel menu".
- **Steps**: numbered, one action each, imperative ("Hold **SHIFT** for 2 s."), the
  result after the action that causes it ("The LED blinks green."). Prerequisites
  before step 1.
- **Labels exactly as printed** on the device or screen, in bold. One term per
  thing throughout; no synonyms.
- **Safety messages** precede the step they protect: signal word (DANGER / WARNING /
  CAUTION / NOTICE), the hazard, its consequence, how to avoid it. Use `!!! danger`
  only for death/serious injury, `!!! warning` for injury or equipment damage,
  `!!! note` for everything else. Do not dilute: no warnings for trivia.
- Second person, present tense, short sentences, no marketing, no "simply"/"just".
- Units: SI, a space before the unit (`5 V`, `20 ms`), ranges as `0–127`.
- Every figure is referenced in the text; every control in the overview figure is
  numbered and appears in the table under it.

## 5. Build and verify

1. `docs-build` must finish with no MkDocs warnings and no doxygen warnings.
2. `docs-build todo`: every remaining TODO must be an open question you have
   reported to the user, nothing else.
3. Look at the PDF: render pages with
   `pdftoppm -png -r 60 docs/build/manual.pdf /tmp/pg` and read the PNGs. Check
   page breaks, figures, tables and warning boxes, not just that it compiled.
4. Re-check every number and label in the manual against `facts.md`.
5. Report to the user: what was written, the open questions, and the build paths
   (`docs/build/manual.pdf`, `docs/build/site/index.html`). Preview the site with
   `docs-build serve` (port 8000; the container needs `DEV_PORTS=8000`).

## Keeping it current

A firmware change that alters anything user-visible (button, LED pattern, setting,
default, error code) updates the manual and `facts.md` in the same change. Tag
releases so the PDF carries the firmware version.
