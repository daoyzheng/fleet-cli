---
name: ship
description: End-to-end change pipeline — implement a fix or feature, verify it with the repo's real commands, get it independently reviewed, then produce a handoff summary that tells the user exactly what to test by hand. Use whenever the user asks to implement, fix, build, or change something and wants it done properly rather than just drafted — including "implement X", "fix this bug", "build this design", "ship it", or any request where the user expects working, reviewed code back. Also use when the user asks for a summary of what changed and what they need to verify themselves.
---

# Ship

A change is not done when the code is written. It is done when it is **verified,
independently reviewed, and handed off with a test plan the user can act on.**

Run the five stages in order. Do not skip stages. Do not report success before
Stage 3 has actually produced passing output.

## Stage 0 — Orient (always, even for "small" changes)

1. Read the repo's `AGENTS.md` (and the parent directory's, if one exists). It
   names the package manager, the real commands, and the conventions. Never guess
   `npm` vs `yarn` vs `pnpm`, or a test command, when the file states it.
2. Identify the **blast radius**. In multi-repo systems a change often spans repos
   (e.g. a CMS schema, its frontend consumer, and a builder that vendors from it).
   If a contract is shared across repos, list every repo that must change *now*,
   before writing code. Say so if a needed repo isn't in the session — offer to
   re-launch with `--add-dir`.
3. Locate the code. Prefer reading the neighbouring implementation over inventing
   a pattern — the surrounding file is the style guide.

If the request is ambiguous in a way that changes what you'd build, ask **now**.
Once Stage 1 starts, proceed on stated assumptions rather than stopping.

## Stage 1 — Plan

Write a short plan before editing: the files you'll touch, what changes in each,
and how you'll prove it works. For anything non-trivial, save it to
`docs/superpowers/plans/YYYY-MM-DD-<slug>.md` if that directory exists in the repo.

Keep it to what the task needs. A one-line CSS fix does not get a design doc.

## Stage 2 — Implement

- Work on a branch. If the repo names branches after tickets, follow that.
- If the repo has a test suite covering the area, write or extend a test **first**
  and watch it fail. If it has no suite, say so plainly rather than pretending.
- Match the surrounding code: its naming, its comment density, its idioms.
- Keep the diff to the requested scope. Note adjacent problems; don't silently fix them.

## Stage 3 — Verify (non-negotiable)

Run the repo's **actual** commands from `AGENTS.md` — typecheck, lint, tests, build,
in whatever combination that repo defines. Then:

- **Paste the real output.** Not "tests pass" — the summary line.
- If something fails, fix it and re-run. Do not proceed to Stage 4 red.
- If a command doesn't exist in the repo, say which verification is unavailable
  instead of substituting a weaker one silently.
- **Run `secret-scan <base-ref>` over the whole branch** and report its output. A
  BLOCK finding is a failed verification — fix it before Stage 4. Warnings
  (focused tests, stray `debugger`, fixture credentials) get reported, and cleaned
  up if they're yours.

Never write "should work", "this fixes it", or "verified" without command output
above it in the same response.

## Stage 4 — Independent review

Get a second pair of eyes that did **not** write the code. In order of preference:

1. Dispatch a review subagent with the diff and the task description, prompted to
   **find defects, not to approve**. Ask specifically for: logic errors, unhandled
   states, broken contracts with other repos, and anything the tests don't cover.
2. For risky changes (auth, money, migrations, anything user-facing at scale), also
   get a cross-model read:
   `git diff <base> | cursor-agent -p --model gpt-5 "Review this diff. Report only real bugs."`
3. Triage what comes back. Fix real defects and re-run Stage 3. Explicitly reject
   findings that are wrong — say why. Do not implement review feedback reflexively.

## Stage 5 — Handoff summary

Output exactly these sections. This is the deliverable the user reads.

```
## What changed
2–4 sentences, plain language. What behaviour is different now.

## Why
The root cause (for a fix) or the design decision (for a feature). One paragraph.

## Files
`path/to/file.ext` — what changed here, one line each. Group by repo if multi-repo.

## Verification
The commands you ran and their real output. State what is NOT covered by
automated tests.

## Test this yourself
The section the user actually needs. Be specific and physical:
- Exact URL / route / screen to open, and how to get there
- The precise click path or input, including any data conditions
  ("a client with alternatives holdings", "an entry with no fr-CA localization")
- What correct looks like — and what the bug looked like before
- Edge cases worth a poke: mobile width, dark mode, empty state, French locale,
  a permission level you can't simulate
Number them. If there is genuinely nothing to check by hand, say so.

## Risks & follow-ups
What could still break, what you deliberately left out of scope, what you'd
want a second opinion on. Be honest here — this is where an omission costs most.
```

## Commits and PRs

- **No agent attribution, ever.** No `Co-Authored-By: Claude`, no
  `Generated with Claude Code`, no `Claude-Session:` trailer, no Cursor equivalent.
  The commit is the user's. Settings enforce this in both CLIs; do not reintroduce it
  in a commit body you write by hand.
- Commit messages describe the change, not the process. Match the repo's existing
  style — read `git log` before writing the first one.
- Use whatever forge the repo actually lives on — `gh pr create` for GitHub,
  `az repos pr create` for Azure DevOps. Check `git remote -v` rather than assuming.
  Fill in the repo's PR template if it has one.
- Only commit or push when the user asks. Never push to a default branch.
- Where a local `pre-commit` hook runs `secret-scan`, respect it.
  Never bypass it with `--no-verify` on the user's behalf — if you believe a finding
  is a false positive, say why and let them decide.
- Respect the project's exclusions for agent tooling (`AGENTS.md`, generated plans,
  `.claude/`, `.cursor/`). Where they live in `.git/info/exclude`, don't `git add -f`
  them and don't move the exclusion into a tracked `.gitignore`.

## Multi-repo changes

When a change spans repos:
- Make the contract change (schema, API, enum) **first**, then the consumers.
- Verify each repo separately with its own commands — a green frontend proves
  nothing about the CMS.
- In the summary, group **Files** by repo and make **Test this yourself** state
  the order to deploy or restart things in.

## Parallel work

If the user asks for several independent changes, don't serialize them. Use a git
worktree per change so the working trees don't collide, run them concurrently, and
produce one Stage 5 summary per change. Only parallelize genuinely independent
work — anything touching a shared contract runs in sequence.
