Set up (or refresh) Trail-Code for the project you are working in. Arguments: $ARGUMENTS

`trail-ensure` already runs at the start of every session. Use this command when it
did not (a repo or sub-project added mid-session) or when the user asks for it.

1. Run `trail-ensure $ARGUMENTS` (no argument = the current directory). It prints one
   summary line and always exits 0. It does nothing in a repo containing a `.no-trail`
   file, when `DEV_TRAIL=0`, or outside a git project.
2. Tell the user exactly what the line says. If it lists "Already-tracked files
   modified", name those files: Trail edited something that was already committed
   (typically `.mcp.json` or `.claude/settings.json`) and they should review the diff.
3. **Never commit, stage or push anything.** Trail's new files (`.trail/`, `.claude/`,
   `.mcp.json`, `.gitignore`/`.ignore` edits) are left in the working tree for the
   user to review and commit.
4. Layouts: a repo with submodules or nested clones is handled automatically by
   `trail-ensure`; a folder of separate repos gets one map at the parent plus `init`
   in each child. For a multi-component repo (firmware + software + web) also check
   whether `.dev-components.json` exists at the root and offer to write it.

Heads-up for the user, once per repo: `trail init` reads their past Claude sessions
for the repo and the review comments on the last 50 merged PRs (through `gh`). That
reading uses Claude under their own login and counts toward their usage; none of it
goes to Trail.
