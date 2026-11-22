---
name: usage-pacing
description: "Pace token use against the Claude plan's 5-hour limit window: check usage with `claude-usage pace`, and stop and report when burning too fast or speed up when under. Use at session start, before large or parallel work (subagents, workflows, big reads), and whenever a usage-pace hook message appears."
---

# Usage pacing

Goal: use **about all** of the 5-hour usage window, and never hit the limit before it resets.
Running out early is worse than finishing a little under.

## The tool

```bash
claude-usage pace           # report from a sample at most 5 min old (probes if older)
claude-usage pace --fresh   # force a new probe (~15 s; starts a throwaway claude in tmux)
claude-usage ack            # the user said "keep going": no hard stop for this window
claude-usage probe --raw    # the raw /usage screen, for debugging the parser
```

The last line is `VERDICT=`:

| Verdict | Meaning | What you do |
|---|---|---|
| `CRITICAL` | limit hit long before the reset (projected ≥115 %, or ≥90 % used with >30 min left) | **Stop.** Finish only the step in progress, then report the numbers to the user and ask how to proceed. If they say continue, run `claude-usage ack`. |
| `FAST` | projected >100 % at reset, or weekly ≥95 % | Throttle: no new parallel agents or workflows, delegate to Sonnet/Haiku, use targeted reads (offsets, grep) over whole files, shorter turns. Say so in one line. |
| `OK` | on track to finish at 75–100 % | Carry on. |
| `SLOW` | projected <75 % with >30 min of the window gone | Headroom: where the task benefits, be more thorough (verification passes, parallel agents). Don't invent work. |
| `UNKNOWN` | no sample yet | Run `claude-usage pace`. |

## How often

Hooks (installed for every session) do this automatically and speak only when the pace is off:

- every 10 min on Opus/Fable-class models, every 30 min otherwise;
- **divided by (1 + running subagents)**: 10 Opus agents in flight mean a check about every
  minute, because they can burn the window in minutes;
- never longer than 1/6 of the projected time until the limit is hit, and never under 1 min.

**Spawning is gated.** Before every Agent/Task/Workflow call the pace is re-checked (a new
probe if the sample is over 2 min old). `CRITICAL` denies the spawn; `FAST` denies it unless
the subagent runs on `sonnet` or `haiku` (workflows are denied outright).

**CRITICAL is sticky and reaches every agent.** Once a sample is critical, every tool call of
the orchestrator and of every subagent is blocked until a newer sample is no longer critical
or the user acks. A subagent that is blocked returns its partial result at once; the
orchestrator then reports to the user.

## Orchestrating

Before a fan-out, estimate it: N heavy agents burn roughly N times your own rate. If
`claude-usage pace` shows less headroom than that (`at this rate the limit is hit in X
min` divided by N is shorter than the job), use fewer agents, cheaper models, or batches.

Also check yourself:

- before starting subagents, a workflow, or any fan-out;
- before a long autonomous stretch (big refactor, long test/build loop);
- on heavy models, after every few substantial steps if the last verdict was `FAST`.

## Reading the report

`burn rate` is the last hour's rate when there are samples, otherwise the window average.
`projected` is the usage at reset at that rate. The weekly line matters as well: a fine 5h
pace means nothing if the weekly limit is nearly used up. Mention both when you report.

Set `CLAUDE_USAGE_PACING=0` in the environment to switch the hooks off.
