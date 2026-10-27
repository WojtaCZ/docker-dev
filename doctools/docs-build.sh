#!/usr/bin/env bash
# docs-build — build a project's docs scaffolded by docs-init.
#
# Usage:
#   docs-build [all]   API reference (if docs/Doxyfile), website and PDF
#   docs-build api     doxygen only        -> docs/build/api/html/
#   docs-build web     mkdocs --strict     -> docs/build/site/
#   docs-build pdf     pandoc + typst      -> docs/build/manual.pdf
#   docs-build serve   live website on 0.0.0.0:${DOCS_PORT:-8000} (publish it with DEV_PORTS)
#   docs-build todo    list the TODO markers left in the manual
#
# Finds docs/manual/mkdocs.yml from the current directory upward (or uses
# $DOCS_DIR). The version stamped on the PDF and the API reference is
# $DOCS_VERSION, else `git describe --tags --always --dirty`, else "dev".

set -euo pipefail

TOOLS="${DOCTOOLS_DIR:-/opt/doctools}"

die()  { echo "docs-build: $*" >&2; exit 1; }
info() { echo "== $* =="; }

find_docs() {
    if [ -n "${DOCS_DIR:-}" ]; then
        [ -f "$DOCS_DIR/manual/mkdocs.yml" ] || die "\$DOCS_DIR=$DOCS_DIR has no manual/mkdocs.yml"
        (cd "$DOCS_DIR" && pwd)
        return
    fi
    local d="$PWD"
    while :; do
        if [ -f "$d/docs/manual/mkdocs.yml" ]; then echo "$d/docs"; return; fi
        if [ -f "$d/manual/mkdocs.yml" ]; then echo "$d"; return; fi
        [ "$d" = / ] && break
        d="$(dirname "$d")"
    done
    die "no docs/manual/mkdocs.yml here or above; run docs-init in the project root first"
}

DOCS="$(find_docs)"
PROJECT="$(dirname "$DOCS")"
MANUAL="$DOCS/manual"
BUILD="$DOCS/build"
mkdir -p "$BUILD"

# The mkdocs tool env's python has PyYAML; the system python does not.
PY="$(dirname "$(readlink -f "$(command -v mkdocs)")")/python"
[ -x "$PY" ] || die "cannot find the mkdocs tool environment's python"
tool() { "$PY" "$TOOLS/manualtool.py" "$@"; }

VERSION="${DOCS_VERSION:-$(git -C "$PROJECT" describe --tags --always --dirty 2>/dev/null || echo dev)}"
{ read -r TITLE; read -r LANG_CODE; } < <(tool meta "$MANUAL/mkdocs.yml")

build_api() {
    if [ ! -f "$DOCS/Doxyfile" ]; then
        echo "no $DOCS/Doxyfile; skipping the API reference"
        return 0
    fi
    info "api (doxygen)"
    local log="$BUILD/doxygen-warnings.log"
    rm -rf "$BUILD/api"
    (
        cd "$PROJECT"
        cat "$DOCS/Doxyfile"
        printf '\nOUTPUT_DIRECTORY = "%s"\nPROJECT_NUMBER = "%s"\nWARN_LOGFILE = "%s"\n' \
            "$BUILD/api" "$VERSION" "$log"
    ) | (cd "$PROJECT" && doxygen -)
    local n=0
    [ -f "$log" ] && n="$(grep -c 'warning:' "$log" || true)"
    echo "API reference: $BUILD/api/html/index.html ($n doxygen warning(s), see $log)"
}

build_web() {
    info "web (mkdocs --strict)"
    # Not --quiet: in mkdocs 1.6 it hides warnings from --strict, so broken links pass.
    local log rc=0
    log="$(cd "$MANUAL" && mkdocs build --strict 2>&1)" || rc=$?
    grep -v '^INFO' <<<"$log" || true
    [ "$rc" -eq 0 ] || die "mkdocs reported warnings (strict); fix them and rebuild"
    if [ -d "$BUILD/api/html" ]; then
        rm -rf "$BUILD/site/api"
        cp -r "$BUILD/api/html" "$BUILD/site/api"
    fi
    echo "website: $BUILD/site/index.html"
}

build_pdf() {
    info "pdf (pandoc -> typst)"
    local out="$BUILD/pdf" tmp chapter n=0
    rm -rf "$out"; mkdir -p "$out"
    tmp="$(mktemp -d)"
    : > "$out/chapters.typ"
    while IFS= read -r chapter; do
        [ -n "$chapter" ] || continue
        local src="$MANUAL/docs/$chapter"
        [ -f "$src" ] || die "nav lists $chapter but $src does not exist"
        n=$((n + 1))
        local base; base="$(printf '%02d-%s' "$n" "$(echo "${chapter%.md}" | tr '/' '-')")"
        tool preprocess "$src" "$tmp/$base.md"
        {
            echo '#import "/manual/pdf/lib.typ": *'
            echo
            pandoc "$tmp/$base.md" -f markdown -t typst \
                --lua-filter "$TOOLS/manual.lua" \
                -M chapter="$chapter" -M chapter_dir="$(dirname "$chapter")"
        } > "$out/$base.typ"
        echo "#include \"$base.typ\"" >> "$out/chapters.typ"
    done < <(tool chapters "$MANUAL/mkdocs.yml")
    rm -rf "$tmp"
    [ "$n" -gt 0 ] || die "no chapters found in $MANUAL/mkdocs.yml nav"

    info "pdf (typst compile)"
    typst compile --root "$DOCS" \
        --input title="$TITLE" --input version="$VERSION" \
        --input date="$(date +%Y-%m-%d)" --input lang="$LANG_CODE" \
        "$MANUAL/pdf/manual.typ" "$BUILD/manual.pdf"
    echo "PDF: $BUILD/manual.pdf ($n chapters, version $VERSION)"
}

report_todo() {
    local hits
    hits="$(grep -rn 'TODO' "$MANUAL/docs" --include='*.md' || true)"
    if [ -n "$hits" ]; then
        echo "$hits"
        echo "docs-build: $(wc -l <<<"$hits") TODO marker(s) left in the manual" >&2
        return 1
    fi
    echo "no TODO markers left"
}

case "${1:-all}" in
    all)
        build_api
        build_web
        build_pdf
        report_todo || true
        ;;
    api) build_api ;;
    web) build_web ;;
    pdf) build_pdf ;;
    serve) cd "$MANUAL" && exec mkdocs serve -a "0.0.0.0:${DOCS_PORT:-8000}" ;;
    todo) report_todo ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command '$1' (try: docs-build --help)" ;;
esac
