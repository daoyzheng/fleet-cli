---
name: standup
description: Turn a day's worth of rough task ideas into a dispatch plan — clarify each task, size it, work out which repos it touches, decide what can run in parallel versus what must be sequenced, then emit ready-to-run `fleet run` commands and optionally launch them. Use when the user outlines several things they want done today, asks to plan their day, says "here's what I need to do", pastes a list of tickets, or asks what to work on next. Also use when they want to know what their running agents are doing and what needs their attention.
---

# Standup

Turn a rough list of intentions into parallel agent work. The output is a **dispatch
plan** — a set of tasks that can safely run at the same time, plus the commands to
launch them.

## Step 1 — Collect

Take whatever the user gives you: a bullet list, a paste of ticket keys, or a
sentence. Then fill gaps:

- If a task names a ticket, fetch it (Jira/Linear MCP, `az boards`, `gh issue`) and
  use the real title and description rather than the user's shorthand.
- If a task is vague ("fix the fund table thing"), ask **one** clarifying question —
  or state the interpretation you're going with and move on. Don't interrogate.
- Ask what's already in flight. Run `fleet status` and fold running agents into the
  picture; don't dispatch something an agent is already doing.

## Step 2 — Locate and size

For each task determine:

| | |
|---|---|
| **Repo(s)** | which of the user's repos it touches — read the parent `AGENTS.md` repo map if there is one |
| **Size** | S (< 30 min, one file), M (a feature in one repo), L (multi-repo or migration) |
| **Branch** | the ticket key if there is one, else a short kebab slug |

Be concrete about repos. "Add a testimonial section" is not one task — per the repo
map it may be a change across a CMS, its frontend consumer, and a builder that vendors
from it — one shared contract, so it is **one L task in one session with `--add-dir`**,
not three parallel ones.

## Step 3 — Parallelise

The rule that matters:

- **Different repos, no shared contract → parallel.** Separate worktrees, dispatch together.
- **Same repo → parallel only in separate worktrees**, and only if the diffs won't collide.
- **Shared contract across repos → sequential, one session**, with the contract change first.

Flag any ordering dependency explicitly ("the schema has to land before the frontend
task can be verified").

Don't dispatch more than the user can review. 3–4 concurrent is a realistic morning;
more just moves the queue from the agents to them. Say so if their list exceeds that,
and propose what to hold back.

## Step 4 — Present the plan

Before launching anything, show:

```
## Dispatching now (parallel)
1. PROJ-42  web-client   M  fix the legend on the summary chart
2. PROJ-51  api-service  S  correct the timezone rollover

## Sequential — needs one session
3. testimonial-section  cms → website → page-builder  L
   Contract change first. Run in one session with --add-dir.

## Holding
4. ... (why it's held: blocked, too big, needs your decision first)
```

Then give the exact commands:

```bash
fleet run ~/src/web-client PROJ-42 "/ship fix the legend on the summary chart"
fleet run ~/src/api-service PROJ-51 "/ship correct the timezone rollover"
```

**Wait for the user to confirm before dispatching.** Launching agents spends real
money and creates branches; that's their call, not yours.

## Step 5 — Supervise

Once dispatched, on request (or when the user comes back and asks "what's happening"):

- `fleet status` — everything, blocked-first
- `fleet ready` — only agents waiting on the user
- `fleet read <name>` — pull an agent's recent output and **summarise it**; don't paste
  raw terminal scrollback at them

For each finished agent, report: what it claims it did, whether its verification
actually passed, and what the user needs to test by hand (the `/ship` handoff has
this — surface it, don't re-derive it).

If an agent is `blocked`, say what it's blocked on and what answer would unblock it.

## Notes

- Each dispatched task runs `/ship`, so verification, independent review, and the
  handoff summary happen inside the agent. Standup's job is deciding **what** runs
  and **in what grouping** — not doing the work.
- Prefer the user's own words for the prompt. A prompt they'd recognise is easier to
  audit than one you've reworded.
- End-of-day: `fleet status` plus a one-line-per-task recap of what landed, what's
  still open, and what needs manual testing.
