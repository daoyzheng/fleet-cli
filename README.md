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
cd fleet-cli
./install.sh          # scripts only
./install.sh --ui     # also the launch agent, SwiftBar and Raycast wiring
```

`install.sh` copies `fleet` and `secret-scan` into `~/.local/bin` and the helpers into
`~/.local/libexec`. Make sure `~/.local/bin` is on your `PATH`.

`--ui` additionally loads the babysit launch agent and points SwiftBar at this repo's
`swiftbar/` directory. **The UI integrations read the repo directly** — there is no
second copy, so `git pull` updates the menu bar plugin and Raycast commands with no
further steps. Raycast needs one manual step: Settings → Extensions → Script Commands
→ Add Directory → this repo's `raycast-scripts/`.

To use the skills, symlink them where your agent looks — so they stay versioned
with this repo rather than drifting on one machine:

```bash
ln -s "$PWD/ship-skill"    ~/.claude/skills/ship
ln -s "$PWD/standup-skill" ~/.claude/skills/standup
ln -s ~/.claude/skills/ship    ~/.cursor/skills/ship      # Cursor reads its own dir
ln -s ~/.claude/skills/standup ~/.cursor/skills/standup
```

The skills are deliberately **generic**. Anything specific to your organisation —
which forge you use, which paths are excluded, which repos share a contract —
belongs in an `AGENTS.md` at the root of your projects directory, which both
Claude Code and Cursor read automatically. Skill = process, `AGENTS.md` = org.

Shell completions:

```bash
mkdir -p ~/.zsh/completions
cp completions/_fleet ~/.zsh/completions/
# in ~/.zshrc:  fpath=("$HOME/.zsh/completions" $fpath); autoload -Uz compinit && compinit
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
| `fleet handoff <name>` | The agent's **full** final report from its session transcript |
| `fleet` (no args) | Dashboard: agents, previews, task worktrees |
| `fleet babysit [--keep]` | Keep the machine awake, watch every agent, push to your phone when it settles |
| `fleet space <path> [--agent kind]` | Scaffold a workspace: agent + app + shell, nvim tab, lazygit tab |
| `fleet preview <path>` | Start that repo's dev server on a free port; print the localhost URL |
| `fleet preview --list / --logs <n> / --stop <n> / --stop-all` | Manage running previews |
| `fleet todo [--all]` | Open markdown checkbox tasks from your notes |
| `fleet trees [--all\|--prune\|--rm <branch>]` | Task worktrees with dirty/ahead/merged state and attached agents |

## Workspace layout

`fleet space` builds a consistent workspace for a repo or worktree:

```
tab 1  work   agent  |  app (fleet preview)
                     |  shell
tab 2  edit   nvim
tab 3  git    lazygit
```

```bash
fleet space ~/src/web                      # claude in tab 1
fleet space ~/src/web --agent cursor
fleet space ~/src/web --agent none --no-git
```

Commands are **pre-typed at each prompt, not auto-run** — press Enter to start
them, or edit them first. That needs one hook in your shell rc:

```zsh
# zsh
if [[ -n "${HERDR_PANE_CMD:-}" ]]; then
  print -z -- "$HERDR_PANE_CMD"
  unset HERDR_PANE_CMD
fi
```

`print -z` pushes onto the editor buffer, so nothing is written to stdout during
shell init — which matters if you use powerlevel10k's instant prompt.

## Previewing a worktree

Agents work in worktrees, so several checkouts of the same project can want the same
dev-server port. `fleet preview` picks a free port derived from the worktree name,
starts the dev server in its own process group, and prints the URL:

```bash
$ fleet preview ~/.herdr/worktrees/web/PROJ-42
web-PROJ-42  http://localhost:3361  (nuxt, pid 91943)
  logs: fleet preview --logs web-PROJ-42

$ fleet preview --list
$ fleet preview --stop web-PROJ-42
```

Detects Nuxt, Strapi, Quasar, and generic `npm/yarn/pnpm run dev` projects, using
the repo's own lockfile to pick the package manager. `--dry-run` prints the command
without running it. Stopping kills the whole process group, then anything still
holding the port.

## Unattended runs

Dispatch in the morning, walk away, get a push when it's done.

Reading what an agent produced:

```bash
fleet read <name>       # terminal scrollback, truncated to what fits
fleet handoff <name>    # the full final report, nothing cut off
```

```bash
fleet run ~/src/web PROJ-42 "/ship ..." --mode auto
fleet run ~/src/api PROJ-51 "/ship ..." --mode auto
fleet babysit
```

Claude agents are dispatched with Remote Control enabled and **named after the
branch**, so the phone app lists `CP-3762` and `PROJ-51` rather than auto-generated
topic summaries — you can answer any blocked agent from your phone, not just one.
`--no-remote` opts out. Cursor has no equivalent, so cursor agents are desk-only.

`--mode` sets the agent's permission mode so it doesn't stall on approval prompts;
`FLEET_PERMISSION_MODE` sets a default. Each CLI spells this differently and fleet
translates: Claude/Codex get `--permission-mode`, Cursor gets `--auto-review --trust`
for `auto` or `--force --trust` for the more permissive modes.

`fleet babysit` holds `caffeinate` for as long as it runs, polls every 30s, and pushes
via [ntfy.sh](https://ntfy.sh) — once per agent that becomes **blocked** (it needs you
now) and once when **everything settles**.

Notifications are situation-specific and carry context pulled from the agent itself:

| Situation | Push |
|---|---|
| An agent blocks on a question | `❓ <name> needs an answer`, the task topic, and the agent's **own last message** (up to ~1.4KB) so you have the reasoning, options and trade-offs in hand |
| All settled, none blocked | `✅ ready for your review` + one line per agent |
| All settled, some blocked | `⚠️ fleet done, N still need you` |

**One instance watches every agent across every project** — it is not per-repo. It
requires two consecutive quiet polls before declaring the fleet settled, and will not
declare it at all until it has seen work actually happen (or `--grace`, default 120s,
expires), so it can't fire the moment you dispatch. `--keep` stays up after settling so
you can add tasks through the day. Install the ntfy app, subscribe to your
topic, and set it in the config. `fleet babysit --test` sends one notification so you
can confirm delivery before relying on it.

Topics are public to anyone who knows the name — use something unguessable, and
remember agent names travel in the notification body.

## Agent names vs branch names

herdr agent names must be lowercase `[a-z0-9_-]`, 1–32 characters. Branch names
routinely are not — `CP-3762`, `feature/Foo`. `fleet run` derives a valid agent name
from the branch and tells you when they differ:

```
probe-billingservice  (branch probe-billingService, cursor in w18:p1)
```

The branch keeps its real name; the agent name is what you use with `fleet read`,
`fleet handoff`, and phone replies — and the relay matches case-insensitively, so
`CP-3762: ...` finds `cp-3762`.

## Configuration

`~/.config/fleet/config` is sourced if present:

```sh
# Colon-separated directories whose immediate children are git repos.
FLEET_ROOTS="$HOME/src:$HOME/work"
FLEET_NTFY_TOPIC="something-unguessable"
FLEET_PERMISSION_MODE="auto"

# Default agent per project tree; longest matching prefix wins.
FLEET_AGENT_DEFAULTS="$HOME/work=cursor:$HOME/personal=claude"
FLEET_AGENT="claude"
FLEET_TODO_PATHS="$HOME/notes"
```

`fleet run` and `fleet space` pick the agent from `FLEET_AGENT_DEFAULTS` unless you
pass `-k`/`--agent`. Notifications are prefixed with the agent kind (`[claude]`,
`[cursor]`) so a mixed fleet stays legible on your phone.

### Menu bar (SwiftBar)

`swiftbar/fleet.10s.sh` renders live fleet state in the macOS menu bar:

```
◆ 2 needs you     red    — an agent is blocked
◐ 3 working       amber  — agents are running
✓ 4 ready         green  — finished, waiting on your review
◇ fleet           grey   — nothing dispatched
```

Clicking through gives each agent's topic, its kind and worktree, **Focus this
agent**, **Copy full handoff** (the complete report to your clipboard), clickable
preview URLs, and a babysit on/off toggle.

```bash
brew install --cask swiftbar
./install.sh --ui     # points SwiftBar at swiftbar/ in this repo
open -a SwiftBar
```

Refreshes every 10s (the `.10s.` in the filename — rename to change it).

### Raycast commands

`raycast-scripts/` holds three script commands — point Raycast at the directory
(Settings → Extensions → Script Commands → Add Directory):

| Command | Does |
|---|---|
| **Toggle Fleet Babysit** | Start/stop the daemon, with inline confirmation |
| **Fleet Status** | Every agent, preview and task worktree, plus daemon state |
| **Fleet — What Needs Me** | Agents waiting on you, and live preview URLs |

Assign a hotkey to the toggle if you flip it often.

### Answering an agent from your phone

`babysit` also polls an **inbound** topic — your outbound topic with `-in` appended —
and feeds anything it finds to the named agent:

```
nav-menu-builder: yes, use a separate tab for navigation
```

Publish that from the ntfy app (or any HTTP client) and the agent receives it as a
prompt. It works for **every agent kind**, including ones with no native remote
control of their own, because the transport is the terminal, not the vendor.

Addressing is designed for typing on a phone:

| You send | Goes to |
|---|---|
| `use a separate tab` | the agent that last asked you something, or the only one running |
| `2: use a separate tab` | agent #2 from the roster |
| `nav: use a separate tab` | the only agent whose name contains `nav` |
| `?` (or `who`, `list`, `status`) | nothing — pushes back the numbered roster with each agent's state |

Roster numbers are stable (agents sorted by name) so the number you read in a push is
the number you reply with. A bare message that could go to several agents is not
guessed at — it asks. Every relayed message is echoed to the log and acknowledged
with a push.

**Treat the inbound topic as a credential.** Anyone who knows it can put words in your
agents' mouths. It is a separate topic from the outbound one so you can rotate it
alone, and agents run in isolated worktrees, but do not share it.

### Running it as a daemon

`fleet babysit` only notifies while it is running. To never miss a completion, load it
as a launch agent (macOS):

```bash
./install.sh --ui     # renders the plist for your $HOME and loads it
```

Starts at login, restarts if it dies, logs to `~/.local/state/fleet/babysit.log`.
`fleet babysit --toggle` starts or stops the daemon (this is what the menu bar and
Raycast call), `--status` prints `on`/`off`, and `--stop` kills a foreground instance.

Only one `fleet babysit` can run at a time — a second one refuses rather than sending
every notification twice.

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
- **`/standup`** — gathers the day's candidate work from your ticket tracker and your
  notes (`fleet todo`), shows one numbered list to pick from, then turns the picks
  into a dispatch plan: what runs in
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
