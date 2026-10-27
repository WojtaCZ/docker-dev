#!/usr/bin/env bash
# dev-doctor checks for the documentation tooling (firmware API docs, manuals).
set -uo pipefail

emit() { echo "$1|$2|$3"; }
have() { command -v "$1" >/dev/null 2>&1; }

need() {
    if have "$1"; then emit OK "$1" "$(command -v "$1")"
    else emit FAIL "$1" "not found on PATH"; fi
}

for b in doxygen dot typst mkdocs pandoc pdftoppm docs-init docs-build; do
    need "$b"
done

for f in manual.lua manualtool.py template/Doxyfile template/manual/mkdocs.yml \
         template/manual/pdf/manual.typ template/manual/pdf/lib.typ; do
    if [ -f "/opt/doctools/$f" ]; then emit OK "doctools:$f" "present"
    else emit FAIL "doctools:$f" "missing from /opt/doctools"; fi
done

have doxygen && emit OK "doxygen-version" "$(doxygen --version 2>/dev/null)"
have typst   && emit OK "typst-version"   "$(typst --version 2>/dev/null)"
have pandoc  && emit OK "pandoc-version"  "$(pandoc --version 2>/dev/null | head -1)"

# The material theme lives inside mkdocs' uv tool env; a bare mkdocs without it
# fails every `theme: material` site at build time.
if have mkdocs; then
    py="$(dirname "$(readlink -f "$(command -v mkdocs)")")/python"
    if [ -x "$py" ] && "$py" -c 'import material' 2>/dev/null; then
        emit OK "mkdocs-material" "theme importable"
    else
        emit FAIL "mkdocs-material" "mkdocs is installed without the material theme"
    fi
fi

# Doxygen call graphs need dot to have a font to lay out text with.
if have fc-list; then
    if [ -n "$(fc-list 2>/dev/null | head -1)" ]; then
        emit OK "fonts" "$(fc-list 2>/dev/null | wc -l) font file(s)"
    else
        emit WARN "fonts" "no fonts found; graphviz output will show empty boxes"
    fi
fi
