-- pandoc filter used by docs-build: one MkDocs chapter -> one Typst chapter.
-- Expects -M chapter=<path of the .md> -M chapter_dir=<its dir>, both relative
-- to manual/docs.
-- Helpers it calls (admonition, xref) are defined in manual/pdf/lib.typ.

local chapter_dir = "."
local chapter = "?"

-- MkDocs admonition types -> the four looks lib.typ defines.
local KIND = {
  note = "note", seealso = "note", question = "note", help = "note", faq = "note",
  example = "note", quote = "note", cite = "note",
  abstract = "info", summary = "info", tldr = "info", info = "info", todo = "info",
  tip = "tip", hint = "tip", important = "tip", success = "tip", check = "tip", done = "tip",
  warning = "warning", caution = "warning", attention = "warning",
  danger = "danger", error = "danger", failure = "danger", fail = "danger",
  missing = "danger", bug = "danger",
}

local function typst_string(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function is_external(target)
  return target:match("^%a[%w+.-]*:") ~= nil
end

local function read_meta(meta)
  if meta.chapter_dir then
    chapter_dir = pandoc.utils.stringify(meta.chapter_dir)
  end
  if meta.chapter then
    chapter = pandoc.utils.stringify(meta.chapter)
  end
end

-- Images: paths are relative to the chapter; Typst resolves "/..." from docs/.
local function image(img)
  if not is_external(img.src) and img.src:sub(1, 1) ~= "/" then
    img.src = pandoc.path.normalize(pandoc.path.join({ "/manual/docs", chapter_dir, img.src }))
  end
  return img
end

-- Links between chapters: keep the anchor, drop the file. xref() falls back to
-- plain text when the anchor does not exist in the PDF.
local function link(l)
  local t = l.target
  if is_external(t) then
    return l
  end
  local anchor = t:match("^[^#]*%.md#(.+)$") or t:match("^#(.+)$")
  if not anchor and t:match("%.md$") then
    return l.content
  end
  if not anchor then
    return l
  end
  local out = { pandoc.RawInline("typst", "#xref(" .. typst_string(anchor) .. ")[") }
  for _, inline in ipairs(l.content) do
    table.insert(out, inline)
  end
  table.insert(out, pandoc.RawInline("typst", "]"))
  return out
end

local function div(d)
  if not d.classes:includes("admonition") then
    return nil
  end
  local kind = "note"
  for _, c in ipairs(d.classes) do
    if KIND[c] then
      kind = KIND[c]
    end
  end
  local title = "none"
  if d.attributes.title then
    local t = d.attributes.title:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    title = typst_string(t)
  end
  local out = { pandoc.RawBlock("typst", "#admonition(kind: \"" .. kind .. "\", title: " .. title .. ")[") }
  for _, block in ipairs(d.content) do
    table.insert(out, block)
  end
  table.insert(out, pandoc.RawBlock("typst", "]"))
  return out
end

local function code_block(cb)
  if cb.classes:includes("mermaid") then
    io.stderr:write("docs-build: WARN mermaid diagram in " .. chapter ..
      " is web-only; use an SVG image so it appears in the PDF\n")
    return pandoc.Para({ pandoc.Emph({ pandoc.Str("[Diagram: see the online edition]") }) })
  end
end

-- Meta first: element filters in one table would run before Meta is seen.
return {
  { Meta = read_meta },
  { Image = image, Link = link, Div = div, CodeBlock = code_block },
}
