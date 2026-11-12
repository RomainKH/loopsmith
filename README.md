# Loopsmith

A native macOS app that takes a feature from a prompt to a pull request with Claude Code agents:

```
project folder → brief agent writes the project's brief (once, given to every agent)

prompt / Jira ticket
   → git worktree for the feature
   → analysis agent: feasibility, approach, problems to handle, acceptance criteria
   → dev agent (Claude Opus 5.5) implements
   → 2 independent review agents, no shared context  ─┐ blocking findings go back to dev,
   → 2 QA agents run the checks and test the feature  ─┘ up to N fix rounds per stage
   → you open the pull request from the app
```

It also shows your Jira worklog for the day, lets you log time on a ticket, and lists your open pull requests on GitHub.

## How it works

- **Projects.** Add a repository once. An agent reads it and writes a brief: what the project is, stack
  and layout, setup in a fresh worktree, lint/test/build commands and CI gates, conventions, pitfalls.
  Every agent of the project's features gets it. You can edit it or have it rewritten from the project page.
- **One worktree per feature.** Pick a project, a base branch and optionally a Jira ticket.
  Loopsmith fetches the base, creates `feat/<ticket>-<title>` in `<worktrees folder>/<repo>/<slug>` and
  copies the untracked files you list (`.env` by default).
- **Agents are your own Claude Code.** Each agent is a `claude -p` process run in the worktree, with
  your login, settings, `CLAUDE.md`, MCP servers, skills and plugins. Nothing is sent anywhere else.
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
- Blocker and major findings go back to the dev agent. When the fix rounds run out, what is left is
  listed as open points and copied into the PR description.
- **Pull request**: you review the title and description, then Loopsmith commits the worktree, pushes the
  branch and runs `gh pr create`. Agents never commit or push.
- **Tools per project and per feature**: every MCP server and skill your Claude Code has is on by default.
  Switch off the ones a feature does not need (Tools button); they are denied to its agents with
  `--disallowedTools`. Each project holds the default set for its new features.
- **Stop / Continue**: stopping kills the agents; Continue resumes from the current step. Features and
  agent logs are kept in `~/Library/Application Support/Loopsmith`.

## Requirements

- macOS 14 or later, Xcode 15 or later (or the Swift 5.10+ toolchain)
- [Claude Code](https://docs.claude.com/en/docs/claude-code) installed and logged in (`claude` on your PATH)
- [GitHub CLI](https://cli.github.com) logged in (`gh auth login`), for pull requests
- Optional: a Jira Cloud site, your email and an [API token](https://id.atlassian.com/manage-profile/security/api-tokens), for tickets and worklogs.
  The token is stored in the macOS keychain.

## Build and run

```bash
swift run                         # development
./scripts/build-app.sh            # build/Loopsmith.app (ad-hoc signed)
./scripts/build-app.sh --install  # and copy it to /Applications
```

The app reads your login shell's `PATH`, so `claude`, `gh`, `node` or `npm` are found even when it is opened from the Finder.

## Settings

| Setting | Default |
|---|---|
| Worktrees folder | `~/Loopsmith` |
| Models (analysis and brief, dev, review, QA) | `claude-opus-5-5` |
| Permission mode | `auto` (Claude Code's classifier approves safe actions). `acceptEdits` denies shell commands the agents would need for tests; `bypassPermissions` runs everything unchecked. |
| Fix rounds after review and after QA | 2 |
| Files copied into new worktrees | `.env, .env.local` |
| My issues (JQL) | `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC` |
| Daily worklog target | 8h |

## Tests

```bash
swift test                                                   # unit tests
LOOPSMITH_E2E=1 LOOPSMITH_HOME=$(mktemp -d) swift test --filter EndToEnd
```

The end-to-end test runs the whole flow (project brief, analysis, dev, review, QA) with Claude Haiku on a throwaway repository (a few minutes, a few cents).
`LOOPSMITH_HOME` keeps its features and settings away from yours.

## License

MIT
