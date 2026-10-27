"""Helpers for docs-build, run with the mkdocs tool env's python (it has PyYAML).

    manualtool.py meta <mkdocs.yml>            site_name, then theme.language
    manualtool.py chapters <mkdocs.yml>        chapter paths in nav order
    manualtool.py preprocess <in.md> <out.md>  MkDocs admonitions -> pandoc divs
"""
import os
import re
import sys
import urllib.parse

import yaml


class _Loader(yaml.SafeLoader):
    pass


# mkdocs.yml may carry !!python/name: and !ENV tags; they do not matter here.
_Loader.add_multi_constructor("", lambda loader, suffix, node: None)


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.load(f, Loader=_Loader) or {}


def meta(cfg):
    theme = cfg.get("theme") or {}
    lang = theme.get("language", "en") if isinstance(theme, dict) else "en"
    print(cfg.get("site_name", "Manual"))
    print(lang or "en")


def _walk_nav(items):
    for item in items:
        if isinstance(item, str):
            yield item
        elif isinstance(item, dict):
            for value in item.values():
                if isinstance(value, str):
                    yield value
                elif isinstance(value, list):
                    yield from _walk_nav(value)


def chapters(cfg, cfg_path):
    docs = os.path.join(os.path.dirname(cfg_path), cfg.get("docs_dir", "docs"))
    nav = cfg.get("nav")
    if nav:
        pages = [p for p in _walk_nav(nav) if p.endswith(".md") and "://" not in p]
    else:
        pages = sorted(
            os.path.relpath(os.path.join(root, f), docs)
            for root, _, files in os.walk(docs)
            for f in files
            if f.endswith(".md")
        )
        pages.sort(key=lambda p: p != "index.md")
    for p in pages:
        print(p)


ADMONITION = re.compile(r'^(\s*)(?:!!!|\?\?\?\+?)\s+([\w-]+)(?:\s+[\w-]+)*\s*(?:"(.*)")?\s*$')
FENCE = re.compile(r"^\s*(```|~~~)")


def _title_attr(kind, title):
    if title is None:
        title = kind.replace("-", " ").capitalize()
    if title == "":
        return ""
    # Percent-encoded: pandoc attribute values have no escape for a quote.
    return ' title="%s"' % urllib.parse.quote(title, safe="")


def convert(lines):
    out, i, fence = [], 0, None
    while i < len(lines):
        line = lines[i]
        m = FENCE.match(line)
        if m:
            fence = None if fence == m.group(1) else (fence or m.group(1))
        if fence is None and not m:
            a = ADMONITION.match(line)
            if a:
                indent, kind, title = a.group(1), a.group(2).lower(), a.group(3)
                body_indent = len(indent) + 4
                body, i = [], i + 1
                while i < len(lines) and (
                    not lines[i].strip()
                    or len(lines[i]) - len(lines[i].lstrip()) >= body_indent
                ):
                    body.append(lines[i][body_indent:] if lines[i].strip() else "")
                    i += 1
                while body and not body[-1]:
                    body.pop()
                out.append("")
                out.append("%s::: {.admonition .%s%s}" % (indent, kind, _title_attr(kind, title)))
                out.extend((indent + l) if l else "" for l in convert(body))
                out.append(indent + ":::")
                out.append("")
                continue
        out.append(line)
        i += 1
    return out


def preprocess(src, dst):
    with open(src, encoding="utf-8") as f:
        lines = f.read().split("\n")
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(convert(lines)))


def main(argv):
    if len(argv) >= 3 and argv[1] == "meta":
        meta(load(argv[2]))
    elif len(argv) >= 3 and argv[1] == "chapters":
        chapters(load(argv[2]), argv[2])
    elif len(argv) >= 4 and argv[1] == "preprocess":
        preprocess(argv[2], argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
