import Foundation

/// `loopsmith <command>`: the same pipeline from a terminal, on macOS and Linux (Windows through WSL).
/// It reads and writes the app's projects, features and settings.
@MainActor
enum CLI {
    nonisolated static let commands: Set<String> = ["help", "--help", "-h", "version", "--version", "add", "projects", "new",
                                                    "run", "status", "diff", "pr", "config", "endpoint"]

    /// On macOS the binary is also the app: only a known command switches it to the terminal.
    nonisolated static func handles(_ args: [String]) -> Bool { args.first.map(commands.contains) ?? false }

    static let usage = """
    Loopsmith \(Loopsmith.version): from a prompt to a pull request with AI coding agents.

    Usage: loopsmith <command> [options]

    Projects
      add [<repo>] [--no-brief]       register a git repository; an agent writes its brief
      projects                        list the projects

    Features
      new <title> [options]           create a feature (branch + worktree) and run its pipeline
          --prompt <text>             what to build (default: the title)
          --prompt-file <file>        read it from a file ("-" for stdin)
          --repo <path>               the repository (default: the current directory)
          --base <branch>             base branch (default: the project's)
          --jira <KEY-123>            Jira ticket to build
          --no-run                    create only
          --yes                       approve every step without asking
      run <feature> [--yes]           start or continue; asks for your approval after each step
      status [<feature>]              list the features, or show one
      diff <feature>                  what the agents changed
      pr <feature> [--title <t>] [--draft] [--yes]
                                      commit, push and open the pull request (GitHub CLI)

    Settings
      config                          show the settings and where they live
      config <key> [<value>]          read or change one (models <model> sets the four roles)
      endpoint [list]                 the custom APIs (local models, gateways)
      endpoint add <name> [<base-url>] [--key <key>] [--mcp]
                                      add one, test it and list its models; --mcp gives its agents
                                      your MCP servers (off: their tools can fill a local model's context);
                                      known names: ollama, lmstudio, llamacpp, litellm, openrouter
      endpoint test <name>            test it again and refresh its models
      endpoint remove <name>

    A feature is named by its short id, its slug or its title. Models: claude-opus-5-5, gemini-2.5-pro,
    agy:<model> (Antigravity), api:<endpoint>/<model> (custom API, e.g. api:ollama/qwen3-coder).
    """

    static func run(_ args: [String]) async -> Int32 {
        guard let command = args.first else {
            out(usage)
            return 0
        }
        let store = AppStore()
        installInterruptHandler(store)
        do {
            var rest = Arguments(Array(args.dropFirst()))
            switch command {
            case "help", "--help", "-h": out(usage)
            case "version", "--version": out("loopsmith \(Loopsmith.version)")
            case "add": try await add(store, &rest)
            case "projects": try projects(store, &rest)
            case "new": return try await new(store, &rest)
            case "run": return try await runFeature(store, &rest)
            case "status": try status(store, &rest)
            case "diff": try await diff(store, &rest)
            case "pr": try await pullRequest(store, &rest)
            case "config": try config(store, &rest)
            case "endpoint": try await endpoint(store, &rest)
            default:
                err("Unknown command: \(command)\n\n\(usage)")
                return 2
            }
            return 0
        } catch {
            endLine()
            err(Term.paint("error: ", .red) + error.localizedDescription)
            return 1
        }
    }

    // MARK: Projects

    private static func add(_ store: AppStore, _ args: inout Arguments) async throws {
        let noBrief = args.flag("--no-brief")
        let path = try await repositoryRoot(args.positional() ?? ".")
        try args.finish()
        let known = store.project(at: path) != nil
        let id = try await store.addProject(path: path)
        out((known ? "Already registered: " : "Registered ") + Term.paint(path, .bold))
        guard !noBrief, !(known && store.project(id)?.brief != nil) else { return }
        try await writeBrief(store, id)
    }

    private static func writeBrief(_ store: AppStore, _ id: UUID) async throws {
        out(Term.paint("Writing the project brief with \(store.settings.analysisModel)…", .dim))
        attachPrinters(store)
        store.scanProject(id)
        await store.tasks[id]?.value
        endLine()
        guard let p = store.project(id) else { return }
        if let error = p.scanError { throw AppError("The brief failed: \(error)") }
        out(Term.paint("✓", .green) + " Brief written: every agent of this project gets it.")
    }

    private static func projects(_ store: AppStore, _ args: inout Arguments) throws {
        try args.finish()
        guard !store.projects.isEmpty else {
            out("No project yet: `loopsmith add <repo>`.")
            return
        }
        for p in store.projects {
            let count = store.features(of: p).count
            out("\(Term.paint(p.name, .bold))  \(p.path)")
            out("  base \(p.baseBranch) · \(count) feature(s) · brief \(p.brief == nil ? "missing" : "written")")
        }
    }

    // MARK: Features

    private static func new(_ store: AppStore, _ args: inout Arguments) async throws -> Int32 {
        let prompt = try args.option("--prompt")
        let promptFile = try args.option("--prompt-file")
        let repoArg = try args.option("--repo")
        let baseArg = try args.option("--base")
        let jiraKey = try args.option("--jira")
        let noRun = args.flag("--no-run")
        let yes = args.flag("--yes")
        guard let title = args.positional()?.trimmed.nonEmpty else { throw AppError("new needs a title: loopsmith new \"<title>\"") }
        try args.finish()

        var request = prompt?.trimmed.nonEmpty
        if let promptFile {
            let data = promptFile == "-" ? FileHandle.standardInput.readDataToEndOfFile()
                : try Data(contentsOf: URL(fileURLWithPath: promptFile))
            request = String(decoding: data, as: UTF8.self).trimmed.nonEmpty
        }
        let repo = try await repositoryRoot(repoArg ?? ".")
        if store.project(at: repo) == nil {
            out("Registering \(Term.paint(repo, .bold)) as a project.")
            let id = try await store.addProject(path: repo)
            try await writeBrief(store, id)
        }
        guard let project = store.project(at: repo) else { throw AppError("Could not register \(repo)") }
        var issue: JiraIssue?
        if let jiraKey {
            guard Jira.isValidIssueKey(jiraKey) else { throw AppError("Invalid Jira key: \(jiraKey)") }
            guard store.jira.isConfigured else {
                throw AppError("Jira is not set up: loopsmith config jiraSite <site>, jiraEmail <email>, jiraToken <token>.")
            }
            issue = JiraIssue(key: jiraKey.uppercased(), summary: title, status: "")
        }
        let id = try await store.createFeature(title: title, prompt: request ?? title, repo: repo,
                                               base: baseArg?.trimmed.nonEmpty ?? project.baseBranch, issue: issue,
                                               disabledMCP: project.disabledMCP, disabledSkills: project.disabledSkills)
        guard let f = store.feature(id) else { return 1 }
        out("Feature \(Term.paint(shortID(f), .bold)) · branch \(f.branch)\nWorktree \(f.worktreePath)")
        if noRun {
            out("Start it with `loopsmith run \(shortID(f))`.")
            return 0
        }
        return try await drive(store, id, yes: yes)
    }

    private static func runFeature(_ store: AppStore, _ args: inout Arguments) async throws -> Int32 {
        let yes = args.flag("--yes")
        let f = try feature(store, args.positional())
        try args.finish()
        return try await drive(store, f.id, yes: yes)
    }

    /// Runs the pipeline and asks for the developer's decision each time it waits, until the feature is ready,
    /// fails, or the developer leaves (it then keeps waiting, like in the app).
    private static func drive(_ store: AppStore, _ id: UUID, yes: Bool) async throws -> Int32 {
        attachPrinters(store)
        while let f = store.feature(id) {
            if f.phase == .prOpened {
                out("Pull request opened: \(f.prURL ?? "")")
                return 0
            }
            if f.isAwaiting || f.phase == .ready {
                endLine()
                let decision = yes ? autoDecision(f) : await ask(store, f)
                switch decision {
                case .quit:
                    if !(yes && f.phase == .ready) { out("Left waiting. `loopsmith run \(shortID(f))` picks it up again.") }
                    return 0
                case .pullRequest:
                    try await openPullRequest(store, f, title: nil, draft: false, confirm: false)
                    return 0
                case .change(let change):
                    store.update(id, change)
                    store.save()
                }
            }
            guard let now = store.feature(id), now.phase != .ready, now.phase != .prOpened else { continue }
            store.start(id)
            await store.tasks[id]?.value
            endLine()
            if let error = store.feature(id)?.error {
                err(Term.paint("Stopped: ", .red) + error)
                err("Fix the cause, then `loopsmith run \(shortID(now))` continues from this step.")
                return 1
            }
        }
        throw AppError("The feature was removed.")
    }

    private enum Decision {
        case change((inout Feature) -> Void)
        case pullRequest
        case quit
    }

    private static func autoDecision(_ f: Feature) -> Decision {
        if f.phase == .ready {
            out(Term.paint("Ready for the pull request.", .green) + " Open it with `loopsmith pr \(shortID(f))`.")
            return .quit
        }
        out(Term.paint("✓ approved (--yes)", .dim))
        return .change { $0.approve(note: nil) }
    }

    private static func ask(_ store: AppStore, _ f: Feature) async -> Decision {
        let devRan = f.runs.contains { $0.role == .dev }
        out("")
        switch f.phase {
        case .dev where !devRan:
            out(Term.paint("Analysis done: your call", .bold))
            if let analysis = f.analysis { out(analysis.asText) }
        case .fixReview, .fixQA:
            out(Term.paint("\(f.phase == .fixReview ? "Review" : "QA") found \(f.pending.count) problem(s) for the dev agent", .bold))
            for (i, finding) in f.pending.enumerated() { out("\(i + 1). \(finding.asText.dropFirst(2))") }
        case .ready:
            out(Term.paint("QA passed: ready for the pull request", .bold))
            if !f.unresolved.isEmpty {
                out("Open points kept for the PR description:\n" + f.unresolved.map(\.asText).joined(separator: "\n"))
            }
        default:
            out(Term.paint("\(f.phase == .review ? "Development" : "Fixes") done: check the change", .bold))
            if let summary = f.lastDevSummary { out(summary) }
            let stat = await Shell.run(["git", "-C", f.worktreePath, "diff", "--stat", f.baseCommit])
            if let text = stat.out.trimmed.nonEmpty { out(Term.paint(text, .dim)) }
        }

        while true {
            let options: [(String, String)]
            switch f.phase {
            case .dev where !devRan: options = [("a", "approve, start development"), ("n", "approve with a note"), ("r", "redo the analysis")]
            case .fixReview, .fixQA: options = [("a", "send them all to dev"), ("k", "keep some"), ("s", "skip the fixes")]
            case .ready: options = [("p", "open the pull request"), ("c", "ask dev for changes")]
            default: options = [("a", "approve, start \(f.phase.label.lowercased())"), ("n", "approve with a note"), ("c", "ask dev for changes")]
            }
            let all = options + (devRan ? [("d", "show the diff")] : []) + [("q", "quit, keep it waiting")]
            out(all.map { "[\(Term.paint($0.0, .bold))] \($0.1)" }.joined(separator: "  "))
            guard let answer = prompt(">") else { return .quit }
            switch answer.lowercased() {
            case "q": return .quit
            case "d" where devRan:
                out(await Git.diff(worktree: f.worktreePath, base: f.baseCommit))
            case "a" where f.phase != .ready:
                return .change { $0.approve(note: nil) }
            case "n" where f.phase != .ready && f.phase != .fixReview && f.phase != .fixQA:
                guard let note = prompt("Note for the next agents:") else { return .quit }
                return .change { $0.approve(note: note) }
            case "r" where f.phase == .dev && !devRan:
                guard let note = prompt("What did the analysis miss?")?.nonEmpty else { continue }
                return .change { $0.redoAnalysis(note) }
            case "c" where f.phase != .fixReview && f.phase != .fixQA && !(f.phase == .dev && !devRan):
                guard let note = prompt("What should the dev agent change?")?.nonEmpty else { continue }
                return .change { $0.requestChanges(note) }
            case "k" where f.phase == .fixReview || f.phase == .fixQA:
                guard let list = prompt("Numbers to send to dev (e.g. 1,3):") else { return .quit }
                let picked = Set(list.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) })
                let kept = f.pending.enumerated().filter { picked.contains($0.offset + 1) }.map(\.element)
                return .change { $0.approve(note: nil, keeping: kept) }
            case "s" where f.phase == .fixReview || f.phase == .fixQA:
                return .change { $0.skipFixes() }
            case "p" where f.phase == .ready:
                return .pullRequest
            default:
                out("Pick one of: \(all.map(\.0).joined(separator: ", ")).")
            }
        }
    }

    private static func status(_ store: AppStore, _ args: inout Arguments) throws {
        if let ref = args.positional() {
            try args.finish()
            show(try feature(store, ref))
            return
        }
        try args.finish()
        guard !store.features.isEmpty else {
            out("No feature yet: `loopsmith new \"<title>\"` in a repository.")
            return
        }
        for p in store.projects {
            let features = store.features(of: p)
            guard !features.isEmpty else { continue }
            out(Term.paint(p.name, .bold))
            for f in features {
                out("  \(Term.paint(shortID(f), .cyan))  \(stateLabel(f).padding(toLength: 30, withPad: " ", startingAt: 0)) \(f.title)")
            }
        }
    }

    private static func show(_ f: Feature) {
        out("\(Term.paint(f.title, .bold))  \(shortID(f))")
        out("State     \(stateLabel(f))")
        out("Branch    \(f.branch) (from \(f.baseBranch) \(f.baseCommit.prefix(8)))")
        out("Worktree  \(f.worktreePath)")
        if let key = f.jiraKey { out("Jira      \(key)") }
        if let url = f.prURL { out("PR        \(url)") }
        if let error = f.error { out(Term.paint("Error     \(error)", .red)) }
        if let analysis = f.analysis { out("\nAnalysis (\(analysis.feasibility)): \(analysis.summary)") }
        if !f.runs.isEmpty {
            out("\nAgents")
            for r in f.runs {
                let tokens = r.effectiveTokens > 0 ? " · \(r.hasExactTokens ? "" : "~")\(r.effectiveTokens) tokens" : ""
                let cost = r.cost.map { String(format: " · $%.2f", $0) } ?? ""
                out("  \(r.role.shortTitle) · \(r.lens) · \(r.model) · \(r.status.rawValue) · \(r.durationSeconds)s\(tokens)\(cost)")
                if let error = r.error { out(Term.paint("    \(error)", .red)) }
            }
        }
        if !f.pending.isEmpty { out("\nFor the dev agent\n" + f.pending.map(\.asText).joined(separator: "\n")) }
        if !f.unresolved.isEmpty { out("\nOpen points\n" + f.unresolved.map(\.asText).joined(separator: "\n")) }
    }

    private static func stateLabel(_ f: Feature) -> String {
        if f.running { return "\(f.phase.label) · running" }
        if f.error != nil { return "\(f.phase.label) · stopped" }
        if f.isAwaiting { return "\(f.phase.label) · waiting for you" }
        return f.phase.label
    }

    private static func diff(_ store: AppStore, _ args: inout Arguments) async throws {
        let f = try feature(store, args.positional())
        try args.finish()
        out(await Git.diff(worktree: f.worktreePath, base: f.baseCommit))
    }

    private static func pullRequest(_ store: AppStore, _ args: inout Arguments) async throws {
        let title = try args.option("--title")
        let draft = args.flag("--draft")
        let yes = args.flag("--yes")
        let f = try feature(store, args.positional())
        try args.finish()
        guard f.phase == .ready else {
            throw AppError("\(shortID(f)) is at \(f.phase.label), not ready for a pull request: `loopsmith run \(shortID(f))`.")
        }
        try await openPullRequest(store, f, title: title, draft: draft, confirm: !yes)
    }

    private static func openPullRequest(_ store: AppStore, _ f: Feature, title: String?, draft: Bool, confirm: Bool) async throws {
        let prTitle = title?.trimmed.nonEmpty ?? [f.jiraKey, f.title].compactMap { $0 }.joined(separator: " ")
        let body = store.pullRequestBody(f)
        if confirm {
            out(Term.paint(prTitle, .bold) + "\n\n" + body + "\n")
            guard let answer = prompt("Commit, push \(f.branch) and open this \(draft ? "draft " : "")pull request? [y/N]"),
                  ["y", "yes"].contains(answer.lowercased()) else {
                out("Nothing pushed.")
                return
            }
        }
        out(Term.paint("Committing, pushing and opening the pull request…", .dim))
        try await store.openPullRequest(f.id, title: prTitle, body: body, draft: draft)
        out("Pull request: \(store.feature(f.id)?.prURL ?? "")")
    }

    // MARK: Settings

    private static func config(_ store: AppStore, _ args: inout Arguments) throws {
        let key = args.positional()
        let value = args.positional()
        try args.finish()
        let settingsFile = AppStore.folder.appendingPathComponent("settings.json").path
        guard let key else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            out("# \(settingsFile)")
            out(String(decoding: try encoder.encode(store.settings), as: UTF8.self))
            out("# jiraToken: \(store.jiraToken.isEmpty ? "not set" : "set")")
            return
        }
        if key == "jiraToken" {
            guard let value else { out(store.jiraToken.isEmpty ? "not set" : "set"); return }
            Keychain.set(value, for: "jira")
            out("jiraToken saved.")
            return
        }
        if key == "models" {
            guard let value else {
                let s = store.settings
                out("analysis \(s.analysisModel)\ndev      \(s.devModel)\nreview   \(s.reviewModel)\nqa       \(s.qaModel)")
                return
            }
            try checkModel(value, store)
            store.settings.analysisModel = value
            store.settings.devModel = value
            store.settings.reviewModel = value
            store.settings.qaModel = value
            store.saveSettings()
            out("Every role now runs \(value).")
            return
        }
        let fields = Mirror(reflecting: store.settings).children.compactMap { child in child.label.map { ($0, child.value) } }
        guard let current = fields.first(where: { $0.0 == key })?.1 else {
            throw AppError("Unknown setting \(key). Settings: \(fields.map(\.0).joined(separator: ", ")), jiraToken, models.")
        }
        guard let value else {
            out("\(current)")
            return
        }
        let typed: Any
        switch current {
        case is Bool:
            guard let b = ["true": true, "yes": true, "on": true, "1": true,
                           "false": false, "no": false, "off": false, "0": false][value.lowercased()] else {
                throw AppError("\(key) takes true or false")
            }
            typed = b
        case is Int:
            guard let n = Int(value) else { throw AppError("\(key) takes a whole number") }
            typed = n
        case is Double:
            guard let n = Double(value) else { throw AppError("\(key) takes a number") }
            typed = n
        case is String:
            if key.hasSuffix("Model") { try checkModel(value, store) }
            typed = value
        default:
            throw AppError("\(key) cannot be set from here: use `loopsmith endpoint` or edit \(settingsFile).")
        }
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(store.settings)) as? [String: Any] ?? [:]
        dict[key] = typed
        store.settings = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: dict))
        store.saveSettings()
        out("\(key) = \(value)")
    }

    private static func checkModel(_ model: String, _ store: AppStore) throws {
        guard Agent.isValidIdentifier(model) else { throw AppError("Invalid model name: \(model)") }
        if AgentProvider.detect(from: model) == .custom {
            _ = try store.agentEnvironment(model: model)
        }
    }

    private static func endpoint(_ store: AppStore, _ args: inout Arguments) async throws {
        let key = try args.option("--key")
        let mcp = args.flag("--mcp")
        let action = args.positional() ?? "list"
        switch action {
        case "list":
            try args.finish()
            guard !store.settings.endpoints.isEmpty else {
                out("No custom API yet. Local models: `loopsmith endpoint add ollama`, then `loopsmith config models api:ollama/<model>`.")
                return
            }
            for e in store.settings.endpoints {
                let hasKey = !Keychain.get(e.keychainAccount).isEmpty
                out("\(Term.paint(e.name, .bold))  \(e.baseURL)  key \(hasKey ? "set" : "none")  MCP servers \(e.loadMCPServers ? "on" : "off")")
                if !e.models.isEmpty { out("  " + e.models.map { "api:\(e.name)/\($0)" }.joined(separator: "\n  ")) }
            }
        case "add":
            guard let name = args.positional()?.lowercased() else { throw AppError("endpoint add <name> [<base-url>] [--key <key>]") }
            let preset = ModelEndpoint.presets.first { $0.name == name }
            guard let url = args.positional() ?? preset?.url else {
                throw AppError("\(name) is no known API: give its base URL, e.g. loopsmith endpoint add \(name) http://localhost:8000")
            }
            try args.finish()
            var e = store.settings.endpoint(named: name) ?? ModelEndpoint(name: name, baseURL: url)
            e.baseURL = ModelEndpoint.normalizedBaseURL(url) ?? url
            e.loadMCPServers = mcp
            if let problem = e.problem(among: store.settings.endpoints) { throw AppError(problem) }
            if let key { Keychain.set(key, for: e.keychainAccount) }
            try await test(store, &e)
        case "test":
            guard let name = args.positional(), var e = store.settings.endpoint(named: name) else {
                throw AppError("endpoint test <name>: see `loopsmith endpoint list`")
            }
            try args.finish()
            try await test(store, &e)
        case "remove", "rm":
            guard let name = args.positional(), let e = store.settings.endpoint(named: name) else {
                throw AppError("endpoint remove <name>: see `loopsmith endpoint list`")
            }
            try args.finish()
            Keychain.set("", for: e.keychainAccount)
            store.settings.endpoints.removeAll { $0.name == name }
            store.saveSettings()
            out("Removed \(name).")
        default:
            throw AppError("endpoint list | add | test | remove")
        }
    }

    /// Saves the endpoint whatever the test says: a local server may simply not be running yet.
    private static func test(_ store: AppStore, _ e: inout ModelEndpoint) async throws {
        defer {
            if let i = store.settings.endpoints.firstIndex(where: { $0.name == e.name }) {
                store.settings.endpoints[i] = e
            } else {
                store.settings.endpoints.append(e)
            }
            store.saveSettings()
        }
        do {
            e.models = try await Agent.endpointModels(e, key: Keychain.get(e.keychainAccount))
            out("\(Term.paint("✓", .green)) \(e.name) answers at \(e.baseURL) with \(e.models.count) model(s):")
            for m in e.models { out("  api:\(e.name)/\(m)") }
            if let first = e.models.first { out("Use one: loopsmith config models api:\(e.name)/\(first)") }
        } catch {
            out("\(Term.paint("✗", .red)) \(e.name) saved, but the test failed: \(error.localizedDescription)")
        }
    }

    // MARK: Helpers

    private static func repositoryRoot(_ path: String) async throws -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        let absolute = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL.path
        let r = await Shell.run(["git", "-C", absolute, "rev-parse", "--show-toplevel"])
        guard r.ok, let root = r.out.trimmed.nonEmpty else { throw AppError("\(absolute) is not inside a git repository.") }
        return root
    }

    private static func shortID(_ f: Feature) -> String { String(f.id.uuidString.lowercased().prefix(8)) }

    private static func feature(_ store: AppStore, _ ref: String?) throws -> Feature {
        guard let ref = ref?.trimmed.nonEmpty else { throw AppError("Name the feature: its id, slug or title (`loopsmith status`).") }
        let r = ref.lowercased()
        let matches = store.features.filter { f in
            f.id.uuidString.lowercased().hasPrefix(r) && r.count >= 4
                || URL(fileURLWithPath: f.worktreePath).lastPathComponent == r
                || f.branch == r
                || f.title.lowercased() == r
        }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw AppError("No feature matches \(ref): see `loopsmith status`.")
        default: throw AppError("\(ref) matches \(matches.count) features: use the id (\(matches.map(shortID).joined(separator: ", "))).")
        }
    }

    // MARK: Terminal

    private static var midLine = false
    private static var lastSource: UUID?
    private static var printersAttached = false
    private static var interruptSource: DispatchSourceSignal?

    /// Streams what the agents write, prefixed with who writes it (review and QA agents run two at a time).
    private static func attachPrinters(_ store: AppStore) {
        guard !printersAttached else { return }
        printersAttached = true
        store.onLog = { [weak store] owner, runID, lines in
            let label: String
            if let runID, let run = store?.feature(owner)?.runs.first(where: { $0.id == runID }) {
                label = "\(run.role.shortTitle) · \(run.lens)"
            } else {
                label = "Brief"
            }
            let source = runID ?? owner
            for line in lines {
                if line.continuing && midLine && lastSource == source {
                    write(line.text)
                    continue
                }
                if midLine { write("\n") }
                write(Term.paint("[\(label)] ", .dim) + line.text)
                midLine = true
                lastSource = source
            }
        }
        store.onNotify = { toast in
            endLine()
            let mark = toast.isError ? Term.paint("✗ ", .red) : Term.paint("▸ ", .cyan)
            out(mark + Term.paint(toast.title, .bold) + Term.paint(" · \(toast.subtitle)", .dim))
        }
    }

    /// Ctrl-C stops the agents and saves the feature, so `loopsmith run` continues it later.
    private static func installInterruptHandler(_ store: AppStore) {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                store.stopAll()
                for f in store.features where f.running {
                    store.update(f.id) { feature in
                        feature.running = false
                        feature.error = "Stopped from the terminal. Continue to resume."
                        for i in feature.runs.indices where feature.runs[i].status == .running {
                            feature.runs[i].status = .stopped
                            feature.runs[i].endedAt = Date()
                        }
                    }
                }
                store.save()
                endLine()
                err("Stopped. `loopsmith run <feature>` continues from the current step.")
                exit(130)
            }
        }
        source.resume()
        interruptSource = source
    }

    private static func prompt(_ question: String) -> String? {
        write(Term.paint(question, .bold) + " ")
        midLine = false
        return readLine()?.trimmed
    }

    private static func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private static func endLine() {
        if midLine { write("\n") }
        midLine = false
    }

    private static func out(_ text: String) {
        endLine()
        write(text + "\n")
    }

    private static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Options anywhere, positionals in order.
struct Arguments {
    private var items: [String]

    init(_ items: [String]) { self.items = items }

    mutating func flag(_ name: String) -> Bool {
        guard let i = items.firstIndex(of: name) else { return false }
        items.remove(at: i)
        return true
    }

    mutating func option(_ name: String) throws -> String? {
        guard let i = items.firstIndex(of: name) else { return nil }
        guard i + 1 < items.count else { throw AppError("\(name) needs a value") }
        let value = items[i + 1]
        items.removeSubrange(i...(i + 1))
        return value
    }

    mutating func positional() -> String? {
        guard let i = items.firstIndex(where: { !$0.hasPrefix("--") || $0 == "-" }) else { return nil }
        return items.remove(at: i)
    }

    func finish() throws {
        if let extra = items.first { throw AppError("Unexpected argument: \(extra)") }
    }
}

enum Term {
    enum Style: String {
        case bold = "1", dim = "2", red = "31", green = "32", cyan = "36"
    }

    static let color = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func paint(_ text: String, _ style: Style) -> String {
        color ? "\u{1B}[\(style.rawValue)m\(text)\u{1B}[0m" : text
    }
}
