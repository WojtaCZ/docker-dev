#!/usr/bin/env bash
# docs-init — scaffold a project's docs/ (firmware API docs + user manual).
#
# Usage:
#   docs-init [--name "Product"] [--lang en] [--dir docs]
#
# Run from the project root (the directory that holds the firmware sources).
# Creates <dir>/Doxyfile, <dir>/manual/{mkdocs.yml,docs/*.md,pdf/*.typ} and
# <dir>/.gitignore. Existing files are never overwritten, so it is safe to rerun
# to restore a deleted template file. Build with `docs-build`.

set -euo pipefail

TEMPLATE="${DOCTOOLS_DIR:-/opt/doctools}/template"
name="$(basename "$PWD")"
lang=en
dir=docs

die() { echo "docs-init: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --name) name="${2:?--name needs a value}"; shift 2 ;;
        --lang) lang="${2:?--lang needs a value}"; shift 2 ;;
        --dir)  dir="${2:?--dir needs a value}"; shift 2 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument '$1' (try: docs-init --help)" ;;
    esac
done

[ -d "$TEMPLATE" ] || die "template not found at $TEMPLATE"

# Doxygen INPUT: the usual firmware source folders that exist here, else the
# whole project (EXCLUDE_PATTERNS keeps vendor code and docs/ out).
input=""
for d in src inc include app App Core firmware fw lib; do
    [ -d "$d" ] && input="$input $d"
done
input="${input# }"
[ -n "$input" ] || input="."

c_only=YES
if find ${input} -path ./"$dir" -prune -o \( -name '*.cpp' -o -name '*.hpp' -o -name '*.cc' \) -print -quit 2>/dev/null | grep -q .; then
    c_only=NO
fi

# sed replacement text: escape \, & and the | delimiter.
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

created=0
while IFS= read -r -d '' src; do
    rel="${src#"$TEMPLATE"/}"
    dst="$dir/$rel"
    if [ -e "$dst" ]; then
        echo "  keep    $dst"
        continue
    fi
    mkdir -p "$(dirname "$dst")"
    sed -e "s|@PRODUCT@|$(esc "$name")|g" \
        -e "s|@LANG@|$(esc "$lang")|g" \
        -e "s|@INPUT@|$(esc "$input")|g" \
        -e "s|@C_ONLY@|$c_only|g" \
        "$src" > "$dst"
    echo "  create  $dst"
    created=$((created + 1))
done < <(find "$TEMPLATE" -type f -print0 | sort -z)

echo
echo "docs-init: $created file(s) created under $dir/ (Doxygen INPUT: $input)"
echo "Next: replace every TODO in $dir/manual/docs/, then run: docs-build"
