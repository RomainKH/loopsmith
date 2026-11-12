# Loopsmith

![Loopsmith](brand/banner.svg)

A macOS app and a command-line tool (macOS, Linux, Windows through WSL) that take a feature from a prompt to a
pull request with **Claude Code** or **Antigravity CLI** agents, or with **your own models**: a local
one through Ollama, LM Studio or llama.cpp, or any API behind a gateway such as LiteLLM or OpenRouter.

```
project folder → brief agent writes the project's brief (once, given to every agent)

prompt / Jira ticket
   → git worktree for the feature
   → analysis agent: feasibility, approach, problems to handle, acceptance criteria
   → dev agent (Claude Code, Antigravity CLI or your own model) implements
   → 2 independent review agents, no shared context  ─┐ blocking findings go back to dev,
   → 2 QA agents run the checks and test the feature  ─┘ up to N fix rounds per stage
   → you open the pull request from the app or the terminal

after every step, the pipeline stops until you approve it
```

Everything is organised by project, a git repository on your machine: its overview (what waits for you, what runs,
open pull requests, today's time), its pull requests, its Jira worklog, and its features in progress or shipped.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/RomainKH/loopsmith/main/scripts/install.sh | sh
```

- **macOS 14+**: installs `Loopsmith.app` in Applications (Apple silicon and Intel) and the `loopsmith` command
  in `~/.local/bin`.
- **Linux** (x86_64, arm64, any distribution): installs the `loopsmith` command, one static binary.
- **Windows**: install [WSL](https://learn.microsoft.com/windows/wsl/install) (`wsl --install`), then run the
  command above in its Ubuntu terminal. Agents, git and `gh` run inside WSL.

The installer checks the download against the release checksums. You can also download `Loopsmith-macos.zip` or
`loopsmith-linux-<arch>.tar.gz` from the [releases](https://github.com/RomainKH/loopsmith/releases). The app is
ad-hoc signed, not notarized: if you download the zip with a browser, macOS refuses to open it until you run
`xattr -dr com.apple.quarantine /Applications/Loopsmith.app` (or allow it in System Settings → Privacy & Security).
The installer does this for you.

Then you need, on your `PATH`:

- at least one agent CLI, logged in: [Claude Code](https://code.claude.com/docs) (`claude`, also what runs
  local models and custom APIs) or the Antigravity CLI (`agy`, which also serves the Gemini models);
- `git`, and the [GitHub CLI](https://cli.github.com) logged in (`gh auth login`) for pull requests;
- optionally a Jira Cloud site, your email and an [API token](https://id.atlassian.com/manage-profile/security/api-tokens),
  for tickets and worklogs.

## Quick start

**App (macOS).** Open Loopsmith: the welcome steps ask for a project folder (a git repository), the AI agents,
Jira if you want it, and GitHub. An agent writes the project's brief. Then **New feature** (⌘N), and approve each
step from the feature page.

**Terminal (macOS, Linux, WSL).**

```bash
cd ~/code/my-repo
loopsmith add                      # register the repository; an agent writes its brief
loopsmith new "Free shipping bar" --prompt "Show a bar with the amount left for free shipping"
# streams the agents, then asks after each step: [a]pprove, [n]ote, [c]hanges, [d]iff, [q]uit…
loopsmith status                   # every feature and where it stands
loopsmith run 3f2a9c1e             # continue one (its short id, slug or title)
loopsmith pr 3f2a9c1e              # commit, push and open the pull request
```

`loopsmith new … --yes` approves every step on its own. The app and the command share the same projects, features
and settings, so you can start a feature in one and finish it in the other. `loopsmith help` lists everything.

## Local models and custom APIs

Agents can run on any API that speaks Anthropic's Messages API, which Ollama, LM Studio, llama.cpp, vLLM, LiteLLM and
OpenRouter all do (for an API that only speaks OpenAI's format, put [LiteLLM](https://docs.litellm.ai) in front of it).
The agent is still Claude Code, with its tools and your skills, pointed at that API for the run.

```bash
ollama pull qwen3-coder                      # a model good at tool calls, with a large context
loopsmith endpoint add ollama                # presets: ollama, lmstudio, llamacpp, litellm, openrouter
loopsmith endpoint add corp https://llm.example.com --key sk-…
loopsmith config models api:ollama/qwen3-coder   # every role; or analysisModel, devModel, reviewModel, qaModel
```

In the app: Settings → Agents & AI → Custom APIs & Local Models → **Add a custom API**, then pick **Custom API** for
a role. Adding an endpoint tests it and lists its models (`GET /v1/models`).

- A role's model is written `api:<endpoint>/<model>`, so you can mix them: a local model for QA, Claude for dev.
- For each run Loopsmith sets `ANTHROPIC_BASE_URL`, puts the endpoint's key (or a placeholder for a local server) in
  `ANTHROPIC_AUTH_TOKEN`, removes `ANTHROPIC_API_KEY`, and points every model Claude Code uses on its own (background
  requests, subagents) at the endpoint's model. Your Anthropic login and key are never sent to it.
- Claude Code's auto mode needs a Claude model, so these agents run in **accept edits** (they edit files but cannot run
  commands, so QA cannot run the tests) or **bypass** (they run every command): `loopsmith config customPermissionMode bypassPermissions`.
- MCP servers are off for these agents unless the endpoint switches them on (`--mcp`, or the MCP switch in Settings):
  the tool definitions of a few servers can take 100k tokens, more than a local model holds.
- Pick a model with tool calling and at least 32k tokens of context (Ollama: `OLLAMA_CONTEXT_LENGTH=32768`);
  small models get lost in a real repository. Costs are not shown for these runs.

## How it works

- **Projects.** Add a repository once. An agent reads it and writes a brief: what the project is, stack
  and layout, setup in a fresh worktree, lint/test/build commands and CI gates, conventions, pitfalls.
  Every agent of the project's features gets it. You can edit it or have it rewritten from the project page.
- **One worktree per feature.** Pick a project, a base branch and optionally a Jira ticket.
  Loopsmith fetches the base, creates `feat/<ticket>-<title>` in `<worktrees folder>/<repo>/<slug>` and
  copies the untracked files you list (`.env` by default).
- **Agents are your own CLIs.** Each agent is a `claude -p` or `agy --print` process run in the worktree,
  with your login, settings, `CLAUDE.md`, MCP servers, skills and plugins. Each role (analysis, dev,
  review, QA) picks its model in Settings: `claude-*` runs on Claude Code, `agy:<model>` on the Antigravity CLI
  (`agy:gemini-4-argon-high`, `agy:claude-opus-5-5-high`: the list comes from `agy models`),
  `api:<endpoint>/<model>` on Claude Code pointed at a custom API. Nothing is sent anywhere else.
- **Analysis** comes first: a read-only agent studies the request against the code and answers with its
  feasibility (feasible, risky, blocked), the approach that fits the codebase, the files involved, the problems
  the developer must handle, its assumptions and acceptance criteria. The dev agent gets all of it; review and
  QA get the acceptance criteria. A blocked request pauses the feature until you continue.
- **Dev** works in one session for the whole feature, so fix rounds keep its context (`--resume`).
- **Review**: two fresh sessions that only see the request and the diff against the base commit.
  One hunts bugs, the other checks the change against the request and the repo conventions.
  They cannot edit files and answer with a JSON verdict (`--json-schema`).
- **QA**: two fresh sessions. One finds and runs the project's gates (lint, tests, build),
  the other exercises the feature against the request. They cannot edit files either.
- **You approve each step.** After the analysis, the development, each review and each QA round, the
  feature waits for you. Approve it, with an optional note the next agents get, or send it back: redo the
  analysis, ask the dev agent for changes, untick the findings that are not real before they go to dev, or
  skip the fixes. "Show diff" displays what the agents changed. Settings can turn the approvals off to run
  the whole pipeline in one go.
- Blocker and major findings go back to the dev agent. When the fix rounds run out, what is left is
  listed as open points and copied into the PR description.
- **Pull request**: you review the title and description, then Loopsmith commits the worktree, pushes the
  branch and runs `gh pr create`. Agents never commit or push.
- **Tools per project and per feature**: every MCP server and skill your CLIs have is on by default.
  Switch off the ones a feature does not need (Tools button): Claude Code denies them with `--disallowedTools`,
  Antigravity with session-only `mcp(<server>/.*)` deny rules.
  Skills can only be switched off for Claude Code agents. Each project holds the default set for its new features.
- **Stop / Continue**: stopping kills the agents (Ctrl-C in the terminal); Continue (`loopsmith run`) resumes from
  the current step. Features and agent logs are kept in `~/Library/Application Support/Loopsmith` on macOS and
  `~/.local/share/Loopsmith` on Linux (`LOOPSMITH_HOME` moves them).
- **Secrets** (the Jira token, custom API keys) are in the macOS keychain; on Linux in `secrets.json` next to the
  settings, readable by you only.

## Tips

- In the app's Overview, set the project's Jira keys (`PROJ`) so its worklog and ticket list keep to its tickets.
- The worktree lives in `~/Loopsmith/<repo>/<feature>`: open it in your editor at any time.
- For a cheap first try, pick `claude-sonnet-5-5` or `claude-haiku-5-5` for every role
  (`loopsmith config models claude-haiku-5-5`).
- Try **Create PR** on a repository where pushing a test branch is fine.
- The app reads your login shell's `PATH`, so `claude`, `gh`, `node` or `npm` are found even when it is opened from the Finder.

## Build from source

Swift 6.2 or later: Xcode 26 on macOS, [swift.org](https://www.swift.org/install/) toolchains on Linux.

```bash
swift run                                   # the app (macOS)
swift run Loopsmith help                    # the command, on macOS or Linux
./scripts/build-app.sh --install            # build/Loopsmith.app, copied to /Applications, plus the loopsmith command
./scripts/build-app.sh --universal --zip    # the release zip, Apple silicon and Intel
docker run --rm -v "$PWD":/src -w /src swift:6.2.4-noble ./scripts/build-linux.sh   # static Linux binary
```

On macOS the window app and the command are the same binary: it opens the app unless it gets a command.

## Releases

Bump `Loopsmith.version` in `Sources/Loopsmith/Entry.swift`, then push a matching tag:
`git tag v0.2.0 && git push origin v0.2.0`. The release workflow builds the universal app and the Linux binaries
(x86_64, arm64), and publishes them with their checksums; the installer always takes the latest.

## Settings

| Setting | Default |
|---|---|
| Worktrees folder | `~/Loopsmith` |
| Models (analysis and brief, dev, review, QA) | `claude-opus-5-5` |
| Wait for my approval after each step | on |
| Permission mode | `auto`: Claude Code's classifier approves safe actions. `acceptEdits` denies shell commands the agents would need for tests. `bypassPermissions` runs everything unchecked. |
| Custom API permissions | `acceptEdits`: no auto mode without a Claude model. `bypassPermissions` lets these agents run commands. |
| Custom APIs | none: Settings → Agents & AI, or `loopsmith endpoint add` |
| Antigravity permissions | `auto` uses agy's auto mode. Some accounts have none: headless `agy` then refuses whatever your agy rules do not allow, and the step fails with agy's message. `bypassPermissions` allows every command through session rules (never `--dangerously-skip-permissions`), so analysis, review and QA agents still cannot write files and switched-off MCP servers stay off. |
| Fix rounds after review and after QA | 2 |
| Files copied into new worktrees | `.env, .env.local` |
| My issues (JQL) | `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC` |
| Daily worklog target | 8h |

## Tests

Every push runs the unit tests on macOS and Linux (`.github/workflows/ci.yml`).

```bash
swift test                                                   # unit tests
LOOPSMITH_E2E=1 LOOPSMITH_HOME=$(mktemp -d) swift test --filter EndToEnd
LOOPSMITH_E2E=1 LOOPSMITH_E2E_MODEL=agy:gemini-3.8-flash-low LOOPSMITH_HOME=$(mktemp -d) swift test --filter EndToEnd
```

The end-to-end test runs the whole flow (project brief, analysis, dev, review, QA) with Claude Haiku on a throwaway repository (a few minutes, a few cents).
`LOOPSMITH_HOME` keeps its features and settings away from yours.

## License

MIT
