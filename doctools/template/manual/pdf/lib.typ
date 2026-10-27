// Helpers every chapter can use. docs-build prepends `#import "/manual/pdf/lib.typ": *`
// to each generated chapter, so anything defined here is in scope there.

// pandoc's Typst writer emits this for a Markdown `---`.
#let horizontalrule = line(length: 100%, stroke: 0.5pt + luma(170))

// MkDocs admonition types, folded onto four looks. Keep in step with KIND in
// /opt/doctools/manual.lua.
#let admonition-colors = (
  note: rgb("#1f6feb"),
  info: rgb("#0969da"),
  tip: rgb("#1a7f37"),
  warning: rgb("#9a6700"),
  danger: rgb("#cf222e"),
)

#let admonition(kind: "note", title: none, body) = {
  let c = admonition-colors.at(kind, default: admonition-colors.note)
  block(
    width: 100%,
    breakable: true,
    inset: (left: 10pt, rest: 8pt),
    stroke: (left: 3pt + c),
    fill: c.lighten(92%),
    {
      if title != none {
        text(weight: "bold", fill: c.darken(25%), title)
        parbreak()
      }
      body
    },
  )
}

// Cross-reference that degrades to plain text when the target heading is not in
// the PDF (MkDocs and pandoc slug non-ASCII headings differently).
#let xref(target, body) = context {
  let found = query(label(target))
  if found.len() > 0 { link(found.first().location(), body) } else { body }
}
