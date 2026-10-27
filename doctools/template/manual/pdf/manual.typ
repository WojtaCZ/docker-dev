// PDF edition of the manual. The chapters come from ../docs/*.md (the same
// files the website is built from), converted by `docs-build pdf` into
// /build/pdf/. Edit this file for layout, title page and fonts; edit the
// Markdown for content. Paths starting with / are relative to docs/.
#import "lib.typ": *

#let title = sys.inputs.at("title", default: "@PRODUCT@")
#let version = sys.inputs.at("version", default: "dev")
#let date = sys.inputs.at("date", default: datetime.today().display())
#let lang = sys.inputs.at("lang", default: "@LANG@")

#set document(title: title + " user manual")
#set text(lang: lang, size: 10.5pt)
#set par(justify: true)
#set heading(numbering: "1.1")
#show heading.where(level: 1): it => {
  pagebreak(weak: true)
  it
}
#show raw.where(block: true): set block(fill: luma(245), inset: 8pt, width: 100%)
#set table(stroke: 0.5pt + luma(160), inset: 6pt, fill: (_, y) => if y == 0 { luma(235) })
#show table.cell: set align(left)
#show table.cell.where(y: 0): strong
#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.5cm),
  header: context {
    if here().page() > 1 {
      set text(8pt, fill: luma(110))
      title
      h(1fr)
      version
    }
  },
  footer: context {
    if here().page() > 1 {
      set text(8pt, fill: luma(110))
      h(1fr)
      counter(page).display("1 / 1", both: true)
      h(1fr)
    }
  },
)

// ---- Title page ------------------------------------------------------------
#page(header: none, footer: none)[
  #v(28%)
  #text(28pt, weight: "bold", title)
  #v(4pt)
  #text(15pt)[User manual]
  // #v(2cm)
  // #image("/manual/docs/img/product.svg", width: 60%)
  #v(1fr)
  #text(10pt)[Version #version #h(1fr) #date]
]

#outline(depth: 2)

#include "/build/pdf/chapters.typ"
