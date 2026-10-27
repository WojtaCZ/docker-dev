Write or update the user manual (website + PDF) for the product in this repo.

Arguments: $ARGUMENTS (optional: product name, language, which chapters, or "review").

1. Load the skills `user-manual-writing` (method) and `firmware-docs` (tooling) and
   follow them; they override anything below that conflicts.
2. If `docs/manual/mkdocs.yml` does not exist, find the project root (where the
   firmware sources are) and run `docs-init --name "<product>" --lang <lang>`.
   Take the product name from the USB descriptors or README; ask only if neither
   has it. Language defaults to the one the user writes in.
3. Phase 1 of the method: build `docs/manual/facts.md` from the source, with file:line
   for every fact and an **Open questions** list. Show the user the open questions
   in one batch and keep going with everything that does not depend on them.
4. Write the chapters, then `docs-build`, render the PDF pages to PNG and look at them.
5. Finish with: chapters written, open questions still blocking TODOs, paths to
   `docs/build/manual.pdf` and `docs/build/site/index.html`. Do not commit unless asked.

With "review": skip writing; check the existing manual against the firmware and the
style rules, and report discrepancies with file:line on both sides.
