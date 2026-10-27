---
name: firmware-docs
description: "How to build firmware and product documentation in this image: docs-init scaffolds docs/ (Doxyfile, MkDocs chapters, Typst PDF layout), docs-build makes the API reference (doxygen + graphviz call graphs), the website (mkdocs-material) and the PDF manual (pandoc -> typst) from the same Markdown. Covers Doxygen comment style for drivers/ISRs, PREDEFINED for __attribute__/__IO, admonitions, images, cross-links, Czech or other languages. Use for API docs, a user manual, docs/, mkdocs.yml, .typ, a PDF or a docs site."
---

# Firmware docs and user manuals: the toolchain

For **what to write** in a user manual and how to gather the facts, load the skill
`user-manual-writing` (or run `/write-manual`). This skill is the mechanics.

## Two commands

```bash
docs-init --name "MIDI Controller" --lang en   # in the project root, once
docs-build            # api + web + pdf, then lists TODO markers left
docs-build pdf        # just the PDF (seconds); also: api, web, serve, todo
```

`docs-init` never overwrites; rerun it to restore a deleted template file.
`docs-build` finds `docs/manual/mkdocs.yml` from the cwd upward (`DOCS_DIR` overrides),
stamps `git describe --tags --always --dirty` as the version (`DOCS_VERSION` overrides),
and fails on any MkDocs warning (`--strict`), including links to missing anchors.
Optional: add `"docs": "docs-build"` to `.mcu-profile.json` so `mcu docs` works.

```
docs/
  Doxyfile               API reference config (paths relative to the project root)
  .gitignore             ignores build/
  build/                 OUTPUT: site/ (with site/api/), manual.pdf, api/html/, pdf/*.typ
  manual/
    mkdocs.yml           site name, language, nav = chapter order of BOTH editions
    docs/*.md            the content, one file per chapter; images in docs/img/
    pdf/manual.typ       PDF layout: page, fonts, title page, header/footer
    pdf/lib.typ          admonition(), xref(): helpers the chapters call
```

Content goes in the Markdown only. Layout goes in `manual.typ` only. Never edit
`build/`; it is regenerated.

## Markdown that survives into both editions

| Use | Notes |
|---|---|
| `#`, `##`, `###` headings | `#` = chapter (one per file), numbered in the PDF |
| `!!! danger/warning/note/tip "Optional title"` + 4-space indented body | coloured boxes in both; nesting works; `??? type` (collapsible) prints expanded |
| Pipe tables | first row is the header |
| `![Caption](img/x.svg)` | SVG or PNG, path relative to the chapter; becomes a numbered figure |
| `[text](other.md#id)`, `[text](#id)` | give target headings an explicit id: `## Reset { #reset }` (diacritics slug differently in MkDocs and pandoc) |
| fenced code with a language | |

Web only, do not use for content the PDF needs: Mermaid (prints a placeholder and
`docs-build` warns; draw an SVG instead), content tabs, raw HTML. Unicode text is fine;
`--lang cs` sets hyphenation, the "Contents" title and figure labels.

## PDF layout changes (manual.typ)

Title page, logo (`#image("/manual/docs/img/logo.svg", width: 4cm)`), paper (`"a4"` /
`"us-letter"`), font (`#set text(font: "DejaVu Sans")`; `typst fonts` lists what
exists; Typst's built-in Libertinus Serif is the default). Inputs available:
`title`, `version`, `date`, `lang`. Check the result by rendering pages:
`pdftoppm -png -r 60 -f 1 -l 4 docs/build/manual.pdf /tmp/pg` and reading the PNGs.

## API reference (Doxygen)

The template's Doxyfile already handles vendor macros (`PREDEFINED` for
`__attribute__`, `__IO`, `__STATIC_INLINE`, ...; without them functions silently
vanish), excludes CMSIS/HAL/ch32fun and builds SVG call/caller graphs. Adjust `INPUT`
if the sources are not in `src`/`include`/`Core`/... Target: zero lines in
`docs/build/doxygen-warnings.log`.

Comment the public API (headers) like this; implementation-only statics briefly:

```c
/**
 * @brief  Start a DMA transfer of @p len bytes to the UART.
 * @param  buf  Data to send; must stay valid until the done callback runs.
 * @param  len  Byte count, 1..UART_TX_MAX.
 * @retval 0        Started.
 * @retval -EBUSY   A transfer is already running.
 * @note   ISR-safe. Non-blocking. Units, timing and ownership belong in the comment.
 */
int uart_send(const uint8_t *buf, size_t len);
```

`@file` + `@brief` at the top of every header, `@defgroup`/`@ingroup` per driver,
`@warning` for preconditions that brick or hang the device.
