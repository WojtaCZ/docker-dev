#!/usr/bin/env bash
# Documentation tooling: each tool actually produces output, not just --version.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "  ok  $*"; }

echo "== binaries =="
for b in doxygen dot typst mkdocs pandoc; do
    command -v "$b" >/dev/null || fail "missing: $b"
    pass "$b"
done

work=$(mktemp -d); cd "$work"

echo "== doxygen + call graph =="
cat > led.c <<'EOF'
/** @file led.c  @brief LED driver. */
/** @brief Set the LED level. @param on non-zero to light it. */
void led_set(int on) { (void)on; }
/** @brief Toggle twice. */
void led_blink(void) { led_set(1); led_set(0); }
EOF
cat > Doxyfile <<'EOF'
INPUT = led.c
OUTPUT_DIRECTORY = api
GENERATE_LATEX = NO
EXTRACT_ALL = YES
HAVE_DOT = YES
CALL_GRAPH = YES
QUIET = YES
EOF
doxygen Doxyfile >/dev/null 2>doxy.err || { cat doxy.err; fail "doxygen failed"; }
[ -f api/html/index.html ] || fail "doxygen produced no HTML"
ls api/html/*_cgraph.* >/dev/null 2>&1 || fail "doxygen produced no call graph (dot not working)"
pass "doxygen HTML with call graph"

echo "== typst PDF =="
printf '= Manual\nHello, *device*.\n' > manual.typ
typst compile manual.typ manual.pdf || fail "typst compile failed"
[ "$(head -c4 manual.pdf)" = "%PDF" ] || fail "typst output is not a PDF"
pass "typst compile"

echo "== pandoc markdown -> typst -> PDF =="
printf '# Setup\n\nPress **RESET** for 3 s.\n' > setup.md
pandoc setup.md -s -t typst -o setup.typ || fail "pandoc -t typst failed"
typst compile setup.typ setup.pdf || fail "pandoc's typst output does not compile"
pass "pandoc -> typst"

echo "== mkdocs material =="
mkdir -p site-src/docs
printf 'site_name: Smoke\ntheme:\n  name: material\n' > site-src/mkdocs.yml
printf '# Hello\n' > site-src/docs/index.md
(cd site-src && mkdocs build --strict -q) || fail "mkdocs build with material theme failed"
grep -q 'material' site-src/site/index.html || fail "site was not built with the material theme"
pass "mkdocs build (material)"

echo "== docs kit: docs-init + docs-build =="
mkdir -p proj/src; cd proj
git init -q
cp ../led.c src/
docs-init --name "Smoke Ovladač" --lang cs >/dev/null || fail "docs-init failed"
[ -f docs/manual/mkdocs.yml ] && [ -f docs/Doxyfile ] && [ -f docs/manual/pdf/manual.typ ] \
    || fail "docs-init did not scaffold docs/"
grep -q '^INPUT *= src$' docs/Doxyfile || fail "docs-init did not detect src/ as Doxygen INPUT"
pass "docs-init scaffold"
docs-init >/dev/null
grep -q 'Smoke Ovladač' docs/manual/mkdocs.yml || fail "docs-init rerun overwrote an existing file"
pass "docs-init rerun keeps existing files"

cat > docs/manual/docs/operation.md <<'EOF'
# Operation

See [the channel](#channel) and [updates](configuration.md#firmware-update).

## Set the channel { #channel }

!!! warning "Disconnect "power" first"
    Unplug the cable.

    !!! note
        Nested.

![Overview](img/overview.svg)
EOF
printf '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="30"><rect width="80" height="30"/></svg>' \
    > docs/manual/docs/img/overview.svg
sed -i 's/^## Firmware update$/## Firmware update { #firmware-update }/' docs/manual/docs/configuration.md

out=$(docs-build all 2>&1) || { echo "$out"; fail "docs-build all failed"; }
[ -f docs/build/api/html/index.html ] || fail "docs-build made no API reference"
[ -f docs/build/site/index.html ] || fail "docs-build made no website"
[ -f docs/build/site/api/index.html ] || fail "API reference not copied into the website"
[ "$(head -c4 docs/build/manual.pdf)" = "%PDF" ] || fail "docs-build made no PDF"
pass "docs-build: api, site, PDF"
op=docs/build/pdf/04-operation.typ
grep -q '#admonition(kind: "warning", title: "Disconnect \\"power\\" first")\[' "$op" \
    || fail "admonition not converted for the PDF: $(cat "$op")"
grep -q '#admonition(kind: "note", title: "Note")\[' "$op" || fail "nested admonition lost"
grep -q '#xref("channel")' "$op" || fail "same-page link not converted"
grep -q '#xref("firmware-update")' "$op" || fail "cross-chapter link not converted"
grep -q 'image("/manual/docs/img/overview.svg"' "$op" || fail "image path not rewritten"
pass "MkDocs features carried into the PDF"
pdftoppm -png -r 30 -f 1 -l 1 docs/build/manual.pdf page >/dev/null || fail "pdftoppm cannot render the PDF"
pass "pdftoppm renders the PDF"

echo '[broken](#nope)' >> docs/manual/docs/operation.md
if docs-build web >/dev/null 2>&1; then fail "a link to a missing anchor did not fail the build"; fi
pass "broken anchors fail the build"
docs-build todo >/dev/null 2>&1 && fail "docs-build todo should report the template's TODOs"
pass "docs-build todo reports TODO markers"
cd ..

cd /; rm -rf "$work"

echo
echo "section 80-docs passed"
