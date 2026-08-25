# fleet

Dispatch and supervise parallel AI coding agents from one terminal, on top of
[herdr](https://herdr.dev).

`fleet` creates a git worktree, starts an agent inside it, submits a prompt, and
then tells you which agents are working, idle, or blocked. It has no opinion about
what the agents do — that's what the bundled `/ship` and `/standup` skills are for.

```bash
fleet run ~/src/api PROJ-42 "/ship fix the timezone rollover"
fleet run ~/src/web PROJ-43 "/ship add the export button" -k cursor

fleet status          # every agent, blocked first
fleet ready           # only the ones waiting on you
fleet read PROJ-42    # an agent's recent output
```

## Why

Running several agents at once is easy. Knowing which one needs you, and reviewing
what they produced, is the hard part. `fleet` handles dispatch and visibility;
`/ship` makes each agent's output reviewable by forcing verification and a handoff
summary that says *what you should test by hand*.

## Requirements

- [`herdr`](https://herdr.dev) — the terminal workspace manager this is built on
- `git`, `bash` 3.2+, `python3` (stdlib only)
- At least one supported agent CLI on `PATH`: `claude`, `cursor-agent`, `codex`,
  `gemini`, `copilot`, `opencode`, `amp`, `droid`

herdr's agent-state integration must be installed for `fleet status` and
`fleet wait` to be accurate:

```bash
herdr integration install claude    # and/or cursor, codex, ...
herdr integration status
```

Without it herdr infers agent state from terminal titles, which is a guess.

## Install

```bash
git clone https://github.com/<you>/fleet-cli.git
cd fleet-cli && ./install.sh
```

Installs `fleet` and `secret-scan` into `~/.local/bin` and the formatter into
`~/.local/libexec`. Make sure `~/.local/bin` is on your `PATH`.

To use the skills, symlink them where your agent looks:

```bash
ln -s "$PWD/ship-skill"    ~/.claude/skills/ship
ln -s "$PWD/standup-skill" ~/.claude/skills/standup
ln -s ~/.claude/skills/ship    ~/.cursor/skills/ship      # Cursor reads its own dir
ln -s ~/.claude/skills/standup ~/.cursor/skills/standup
```

## Commands

| | |
|---|---|
| `fleet run <repo> <branch> <prompt> [-k kind]` | Worktree + agent + prompt, without stealing focus |
| `fleet batch <file>` | Dispatch a plan file — `repo \| branch \| prompt` per line |
| `fleet status` | Every agent: name, kind, state, cwd — blocked first |
| `fleet ready` | Only agents that are idle or blocked |
| `fleet watch` | `status`, refreshed every 5s |
| `fleet wait <name>...` | Block until each agent settles — for scripting |
| `fleet read <name> [lines]` | An agent's recent terminal output |
| `fleet trees [--prune]` | Every git worktree under `$FLEET_ROOTS`; prune dead registrations |

## Configuration

`~/.config/fleet/config` is sourced if present:

```sh
# Colon-separated directories whose immediate children are git repos.
FLEET_ROOTS="$HOME/src:$HOME/work"
```

Defaults to `$HOME/dev`. Only `fleet trees` uses it.

## secret-scan

A standalone credential and test-scaffolding guard, usable with or without `fleet`.

```bash
secret-scan                 # staged changes (use as a pre-commit hook)
secret-scan origin/main     # a whole branch, before opening a PR
```

**Blocks:** private keys, cloud connection strings and account keys, npm/NuGet
`_password=` / `_authToken=`, `ghp_` / `xox*` / `sk-` tokens, JWT literals, and
hardcoded credential assignments in non-test source.

**Warns:** the same assignments inside test/mock/fixture files, plus
`describe.only`, `it.skip`, stray `debugger`, and `tempDisableSecurity` /
`skipAuth` set true.

Install as a hook (local to your clone, never committed):

```bash
printf '#!/usr/bin/env bash\nexec "$HOME/.local/bin/secret-scan"\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

It scans per file so source and fixtures are treated differently, and ignores
Vue/JSX attribute bindings like `@update:password="handler"`. It is a
last-line-of-defence heuristic, not a replacement for a real secret scanner —
pair it with server-side push protection.

## Skills

`ship-skill/` and `standup-skill/` are agent skills (markdown + YAML frontmatter),
read by both Claude Code and Cursor.

- **`/ship`** — one task through orient → plan → implement → verify → review →
  handoff. Stage 3 refuses to claim success without pasted command output; Stage 5
  emits a fixed summary ending in *"test this yourself"*.
- **`/standup`** — turns a day's rough task list into a dispatch plan: what runs in
  parallel, what must be sequenced behind a shared contract, what to hold back. Emits
  the `fleet run` commands and waits for your approval before spending anything.

Both assume an `AGENTS.md` in the repo describing its real commands and conventions.

## Status

Personal tooling, published because it might be useful. Roughly 200 lines of bash
and 30 of python. It is a thin, inspectable wrapper over herdr's socket API — read
it before you run it. No tests, no CI, and it has only been exercised on macOS with
`claude` and `cursor-agent`. Interfaces may change.

Issues and PRs welcome.

## License

MIT
