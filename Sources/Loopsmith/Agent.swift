import Foundation

struct AgentResult: Equatable {
    var sessionId: String?
    var text: String
    var structured: Data?
    var cost: Double?
    var tokens: Int? = nil
    var isError: Bool
}

enum AgentEvent: Equatable {
    case session(String)
    case delta(String)
    case log(String)
    case result(AgentResult)
}

/// Reassembles streamed `.delta` pieces (Gemini CLI, Antigravity CLI) into the latest assistant message without inserting line breaks mid-token.
struct ReplyBuffer {
    private(set) var text = ""
    private var inDelta = false

    mutating func take(_ event: AgentEvent) -> Bool {
        switch event {
        case .delta(let piece):
            let continues = inDelta
            if !continues { text = "" }
            text += piece
            inDelta = true
            return continues
        case .log(let line):
            inDelta = false
            if !line.hasPrefix("→ ") && !line.hasPrefix("✗ ") {
                text = line
            }
            return false
        case .session, .result:
            return false
        }
    }
}

extension Array where Element == String {
    mutating func appendLog(_ text: String, continuing: Bool) {
        if continuing, !isEmpty {
            self[count - 1] += text
        } else {
            append(text)
            if count > AgentRun.maxLogLines { removeFirst(count - AgentRun.maxLogLines) }
        }
    }
}

/// MCP servers and skills a `claude` session gets in a folder (user, project and plugin ones).
struct ToolInventory: Equatable {
    struct Server: Hashable {
        var name: String
        var status: String
    }
    var servers: [Server]
    var skills: [String]
}

/// The angle a review or QA agent looks from. Two per stage, so the two agents do not report the same things.
struct Lens {
    let name: String
    let brief: String
}

/// Everything that talks to the AI agent CLIs (`claude -p`, `gemini -p`, `agy --print`; stream-json output).
enum Agent {
    private static let identifierRegex = try! Regex(#"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"#)

    /// Rejects CLI flag injection (leading `-`, whitespace, control chars) in model names and session IDs (AML.T0053).
    static func isValidIdentifier(_ value: String) -> Bool {
        value.trimmed.wholeMatch(of: identifierRegex) != nil
    }

    static func sanitizePermissionMode(_ mode: String) -> String {
        ["auto", "acceptEdits", "bypassPermissions"].contains(mode) ? mode : "auto"
    }

    /// What the CLI reads on stdin: the prompt, except for Antigravity, which takes it in `--print=`.
    static func stdin(model: String, prompt: String) -> String {
        AgentProvider.detect(from: model) == .antigravity ? "" : prompt
    }

    /// `prompt` is only used by Antigravity (the others read it on stdin), `cwd` only by Gemini CLI (its MCP servers).
    static func arguments(model: String, permissionMode: String, systemPrompt: String, resume: String?,
                          schema: String?, readOnly: Bool, disabledMCP: [String], disabledSkills: [String],
                          prompt: String = "", cwd: String = "") -> [String] {
        let provider = AgentProvider.detect(from: model)
        let safeModel = isValidIdentifier(model) ? model.trimmed : provider.defaultModel
        let safeMode = sanitizePermissionMode(permissionMode)
        let safeResume = resume.flatMap { isValidIdentifier($0) ? $0.trimmed : nil }

        switch provider {
        case .claude:
            var args = ["claude", "-p", "--output-format", "stream-json", "--verbose", "--model", safeModel,
                        "--permission-mode", safeMode, "--append-system-prompt", systemPrompt]
            if let safeResume { args += ["--resume", safeResume] }
            if let schema { args += ["--json-schema", schema] }
            let denied = (readOnly ? ["Edit", "Write", "NotebookEdit"] : [])
                + disabledMCP.map { "mcp__" + mcpToolPrefix($0) }
                + disabledSkills.map { "Skill(\($0))" }
            if !denied.isEmpty { args += ["--disallowedTools", denied.joined(separator: ",")] }
            return args

        case .gemini:
            let approvalMode: String
            switch safeMode {
            case "acceptEdits":
                approvalMode = readOnly ? "plan" : "auto_edit"
            default:
                approvalMode = "yolo"
            }
            var instruction = systemPrompt
            if readOnly {
                instruction += "\n\nIMPORTANT: You are in read-only mode. Do NOT modify, write, or delete any repository files."
            }
            if let schema {
                instruction += "\n\nRespond ONLY with a valid JSON object matching this JSON Schema (no surrounding markdown prose):\n\(schema)"
            }
            var args = ["gemini", "-p", instruction, "--output-format", "stream-json", "--model", safeModel,
                        "--approval-mode", approvalMode, "--skip-trust"]
            if let safeResume { args += ["--resume", safeResume] }
            let disabled = Set(disabledMCP)
            let geminiServers = geminiInventory(cwd: cwd).servers.map(\.name)
            if geminiServers.contains(where: disabled.contains) {
                let allowed = geminiServers.filter { !disabled.contains($0) }
                // An empty list means no filter at all: name a server that does not exist instead.
                args += ["--allowed-mcp-server-names"] + (allowed.isEmpty ? ["loopsmith-none"] : allowed)
            }
            return args

        case .antigravity:
            var args = ["agy", "--output-format", "stream-json", "--model", AgentProvider.cliModel(safeModel)]
            if let safeResume { args += ["--conversation", safeResume] }
            if let schema { args += ["--json-schema", schema] }
            // Session-only rules (`--settings`, never saved), globs measured on agy 1.5.6: `*` matches across the `/`
            // of `mcp(server/tool)`, and a deny rule wins over any allow rule.
            var permissions: [String: [String]] = [:]
            switch safeMode {
            case "acceptEdits": args += ["--mode", "accept-edits"]
            // Allow rules rather than --dangerously-skip-permissions, so the deny rules below still hold.
            case "bypassPermissions": permissions["allow"] = ["command(*)", "read_file(*)", "mcp(*)"] + (readOnly ? [] : ["write_file(*)"])
            default: args += ["--mode", "auto"]
            }
            let deny = (readOnly ? ["write_file(*)"] : []) + disabledMCP.map { "mcp(\($0)/*)" }
            if !deny.isEmpty { permissions["deny"] = deny }
            if !permissions.isEmpty, let data = try? JSONSerialization.data(withJSONObject: ["permissions": permissions], options: .sortedKeys) {
                args += ["--settings", String(decoding: data, as: UTF8.self)]
            }
            args.append("--print=\(systemPrompt)\n\n\(prompt)")
            return args
        }
    }

    /// Tool name prefix Claude Code gives a server: "claude.ai Atlassian Rovo (2)" → "claude_ai_Atlassian_Rovo_2".
    static func mcpToolPrefix(_ server: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        var name = String(server.map { allowed.contains($0) ? $0 : "_" })
        while name.contains("__") { name = name.replacingOccurrences(of: "__", with: "_") }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Extracts a JSON object from raw text or a fenced ```json block (used when Gemini CLI returns structured output in text).
    static func extractStructuredJSON(from text: String) -> Data? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           JSONSerialization.isValidJSONObject(obj) {
            return try? JSONSerialization.data(withJSONObject: obj)
        }
        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}"),
              firstBrace <= lastBrace else { return nil }
        let candidate = String(trimmed[firstBrace...lastBrace])
        guard let data = candidate.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              JSONSerialization.isValidJSONObject(obj) else { return nil }
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    /// Turns one stream-json line (Claude Code or Gemini CLI) into what the app shows and keeps.
    static func parse(_ line: String) -> [AgentEvent] {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return line.trimmed.isEmpty ? [] : [.log(line)]
        }
        if let event = obj["event"] as? String { return parseAntigravity(event, obj) }
        switch obj["type"] as? String {
        case "system":
            if obj["subtype"] as? String == "init", let id = obj["session_id"] as? String { return [.session(id)] }
            return []
        case "init":
            if let id = obj["session_id"] as? String { return [.session(id)] }
            return []
        case "assistant":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { item in
                switch item["type"] as? String {
                case "text":
                    return (item["text"] as? String)?.nonEmpty.map { .log($0.trimmed) }
                case "tool_use":
                    return .log("→ \(item["name"] as? String ?? "tool") \(toolDetail(item["input"]))".trimmed)
                default:
                    return nil
                }
            }
        case "message":
            guard obj["role"] as? String == "assistant",
                  let content = obj["content"] as? String, !content.isEmpty else { return [] }
            if obj["delta"] as? Bool == true {
                return [.delta(content)]
            }
            return content.nonEmpty.map { [.log($0.trimmed)] } ?? []
        case "tool_use":
            let name = obj["tool_name"] as? String ?? obj["name"] as? String ?? "tool"
            let detail = toolDetail(obj["parameters"] ?? obj["input"])
            return [.log("→ \(name) \(detail)".trimmed)]
        case "user":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { item in
                guard item["is_error"] as? Bool == true else { return nil }
                let text = item["content"] as? String
                    ?? (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    ?? ""
                return .log("✗ \(text.prefix(400))")
            }
        case "tool_result":
            let isErr = (obj["status"] as? String == "error") || (obj["is_error"] as? Bool == true)
            guard isErr else { return [] }
            let msg = (obj["error"] as? [String: Any])?["message"] as? String
                ?? (obj["output"] as? String)
                ?? "Tool error"
            return [.log("✗ \(msg.prefix(400))")]
        case "error":
            guard let msg = (obj["message"] as? String)?.nonEmpty else { return [] }
            return [.log("✗ \(msg.prefix(400))")]
        case "result":
            let isError = (obj["is_error"] as? Bool ?? false) || (obj["status"] as? String == "error")
            let errObjMsg = (obj["error"] as? [String: Any])?["message"] as? String
            let text = (obj["result"] as? String)
                ?? (obj["response"] as? String)
                ?? errObjMsg
                ?? ""
            var structured: Data?
            if let value = obj["structured_output"], JSONSerialization.isValidJSONObject(value) {
                structured = try? JSONSerialization.data(withJSONObject: value)
            } else if !isError, let extracted = extractStructuredJSON(from: text) {
                structured = extracted
            }
            return [.result(AgentResult(sessionId: obj["session_id"] as? String,
                                        text: text,
                                        structured: structured,
                                        cost: obj["total_cost_usd"] as? Double,
                                        tokens: extractTokens(from: obj),
                                        isError: isError))]
        default:
            return []
        }
    }

    /// Extracts total token usage from Claude Code (`usage`), Gemini CLI (`stats`), or Antigravity CLI (`usage`/`tokens`).
    private static func extractTokens(from obj: [String: Any]) -> Int? {
        if let usage = obj["usage"] as? [String: Any] {
            if let total = usage["total_tokens"] as? Int, total > 0 { return total }
            let input = (usage["input_tokens"] as? Int ?? 0)
                + (usage["cache_read_input_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)
            let output = usage["output_tokens"] as? Int ?? 0
            if input + output > 0 { return input + output }
        }
        if let stats = obj["stats"] as? [String: Any] {
            if let total = stats["total_tokens"] as? Int, total > 0 { return total }
            let input = stats["input_tokens"] as? Int ?? 0
            let output = stats["output_tokens"] as? Int ?? 0
            if input + output > 0 { return input + output }
        }
        if let total = obj["total_tokens"] as? Int, total > 0 { return total }
        return nil
    }

    /// Antigravity CLI (`agy` 1.5): `event` lines, the answer in `text_delta` pieces, tools as step updates,
    /// and a `result` holding the whole response and the structured output.
    private static func parseAntigravity(_ event: String, _ obj: [String: Any]) -> [AgentEvent] {
        switch event {
        case "init":
            return (obj["conversation_id"] as? String)?.nonEmpty.map { [.session($0)] } ?? []
        case "step_update":
            guard let step = obj["step_update"] as? [String: Any] else { return [] }
            let tool = step["tool_name"] as? String ?? "tool"
            let info = step["tool_info"] as? [String: Any]
            switch (step["step_type"] as? String, step["state"] as? String) {
            case ("agent_response", _):
                guard let piece = step["text_delta"] as? String, !piece.isEmpty else { return [] }
                return [.delta(piece)]
            case ("tool", "ACTIVE"):
                return [.log("→ \(tool) \(toolDetail(info?["parameters"]))".trimmed)]
            case ("tool", "ERROR"):
                let why = (info?["output"] as? String)?.nonEmpty ?? "refused or failed"
                return [.log("✗ \(tool): \(why.prefix(400))")]
            default:
                return []
            }
        case "result":
            guard let r = obj["result"] as? [String: Any] else { return [] }
            let isError = r["status"] as? String != "SUCCESS"
            var structured: Data?
            if let value = r["structured_output"], JSONSerialization.isValidJSONObject(value) {
                structured = try? JSONSerialization.data(withJSONObject: value)
            }
            let text = isError ? ((r["error"] as? String)?.nonEmpty ?? "agy failed") : (r["response"] as? String ?? "")
            return [.result(AgentResult(sessionId: (r["conversation_id"] as? String)?.nonEmpty, text: text,
                                        structured: structured, cost: r["total_cost_usd"] as? Double,
                                        tokens: extractTokens(from: r), isError: isError))]
        default:
            return []
        }
    }

    private static func toolDetail(_ input: Any?) -> String {
        guard let input = input as? [String: Any] else { return "" }
        if let server = input["ServerName"] as? String, let name = input["ToolName"] as? String { return "\(server)/\(name)" }
        for key in ["command", "file_path", "pattern", "path", "url", "skill", "description", "query",
                    "CommandLine", "AbsolutePath", "TargetFile", "Path", "Query", "Url"] {
            if let value = input[key] as? String { return String(value.replacingOccurrences(of: "\n", with: " ").prefix(200)) }
        }
        return ""
    }

    /// Checks whether a provider's CLI (`claude` or `gemini`) is installed and reachable on PATH.
    static func cliStatus(_ provider: AgentProvider) async -> (installed: Bool, detail: String) {
        let res = await Shell.run([provider.binary, "--version"])
        let output = (res.out.nonEmpty ?? res.err.nonEmpty ?? "").trimmed
        if res.ok, !output.isEmpty {
            let firstLine = output.components(separatedBy: .newlines).first ?? output
            return (true, firstLine)
        }
        // Fallback: check if binary exists on PATH even if config file warned
        let which = await Shell.run(["which", provider.binary])
        if which.ok, let binPath = which.out.nonEmpty?.trimmed {
            return (true, binPath)
        }
        return (false, "Not found on PATH (`\(provider.binary)`)")
    }

    /// Reads the MCP servers and skills of a folder from Claude Code, Gemini CLI and Antigravity CLI.
    /// Skills come from Claude Code only: the other CLIs cannot switch one off for a session.
    static func inventory(cwd: String) async throws -> ToolInventory {
        var found: ToolInventory?
        var running: Process?
        _ = try? await Shell.stream(["claude", "-p", "--output-format", "stream-json", "--verbose",
                                     "--no-session-persistence", "--model", "claude-haiku-5-5"],
                                    cwd: cwd, input: "ok",
                                    register: { running = $0 }) { line in
            guard found == nil,
                  let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  obj["subtype"] as? String == "init" else { return }
            let servers = (obj["mcp_servers"] as? [[String: Any]] ?? []).compactMap { s in
                (s["name"] as? String).map { ToolInventory.Server(name: $0, status: s["status"] as? String ?? "") }
            }
            found = ToolInventory(servers: servers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
                                  skills: (obj["skills"] as? [String] ?? []).sorted())
            running?.terminate()
        }

        let others = geminiInventory(cwd: cwd).servers + (await antigravityServers(cwd: cwd))
        guard found != nil || !others.isEmpty else {
            throw AppError("Could not list tools (make sure Claude Code, Gemini CLI or Antigravity CLI is installed and logged in)")
        }
        var base = found ?? ToolInventory(servers: [], skills: [])
        for server in others where !base.servers.contains(where: { $0.name == server.name }) {
            base.servers.append(server)
        }
        base.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return base
    }

    /// Headless agy cannot ask for a permission: it refuses the tool and often ends the turn with no output, while the
    /// result still says SUCCESS. Such a run did not do its job (a dev "done" with no change, a review with no verdict).
    static func antigravityRefusal(model: String, stderr: String) -> String? {
        guard AgentProvider.detect(from: model) == .antigravity,
              stderr.contains("auto-denied") || stderr.contains("no output produced") else { return nil }
        let noAuto = stderr.contains("--mode auto is not available") ? " This account has no auto mode." : ""
        return "Antigravity refused a tool it could not ask you about.\(noAuto) Choose Bypass for Antigravity in Settings → Agents, or add allow rules to agy's settings. agy said: \(stderr.trimmed.prefix(500))"
    }

    /// `agy mcp list`: a header, then one server per line (NAME TYPE STATUS COMMAND/URL). No model call.
    static func antigravityServers(cwd: String) async -> [ToolInventory.Server] {
        let r = await Shell.run(["agy", "mcp", "list"], cwd: cwd)
        guard r.ok else { return [] }
        return r.out.split(separator: "\n").compactMap { line in
            let cols = line.split(whereSeparator: \.isWhitespace)
            guard cols.count >= 3, cols[0] != "NAME" else { return nil }
            return ToolInventory.Server(name: String(cols[0]), status: "agy \(cols[2])")
        }
    }

    /// The models this Antigravity account offers (`agy models`: "<id>\t<label>" lines), stored with their prefix.
    static func antigravityModels() async -> [String] {
        let r = await Shell.run(["agy", "models"])
        guard r.ok else { return [] }
        return r.out.split(separator: "\n").compactMap { line in
            guard line.contains("\t"), let id = line.split(separator: "\t").first, isValidIdentifier(String(id)) else { return nil }
            return AgentProvider.antigravity.storedModel(String(id))
        }
    }

    /// Reads the MCP servers configured in `~/.gemini` and `<cwd>/.gemini` without spawning a paid model call.
    static func geminiInventory(cwd: String) -> ToolInventory {
        let home = NSHomeDirectory()
        let settingsFiles = [
            "\(home)/.gemini/settings.json",
            "\(cwd)/.gemini/settings.json"
        ]
        var serverNames = Set<String>()
        for path in settingsFiles {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let mcp = json["mcpServers"] as? [String: Any] {
                serverNames.formUnion(mcp.keys)
            }
        }
        let servers = serverNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ToolInventory.Server(name: $0, status: "gemini") }
        return ToolInventory(servers: servers, skills: [])
    }

    // MARK: Prompts

    static let verdictSchema = """
    {"type":"object","properties":{"summary":{"type":"string"},"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["blocker","major","minor"]},"file":{"type":"string"},"line":{"type":"integer"},"title":{"type":"string"},"detail":{"type":"string"}},"required":["severity","title","detail"]}}},"required":["summary","findings"]}
    """

    static let analysisSchema = """
    {"type":"object","properties":{"feasibility":{"type":"string","enum":["feasible","risky","blocked"]},"summary":{"type":"string"},"approach":{"type":"string"},"impacted":{"type":"array","items":{"type":"string"}},"risks":{"type":"array","items":{"type":"string"}},"assumptions":{"type":"array","items":{"type":"string"}},"acceptanceCriteria":{"type":"array","items":{"type":"string"}}},"required":["feasibility","summary","approach","impacted","risks","assumptions","acceptanceCriteria"]}
    """

    /// Every agent of a project gets its brief after its own instructions.
    static func withBrief(_ system: String, brief: String?) -> String {
        guard let brief = brief?.nonEmpty else { return system }
        return "\(system)\n\nProject brief, written by an agent that read the repository (the code wins if they disagree):\n\(brief)"
    }

    static let projectBriefSystemPrompt = """
    You onboard the other agents of an automated pipeline (analysis, development, code review, QA) on this repository. Do not modify any file.
    Read what matters: README, CLAUDE.md or AGENTS.md, package manifests, CI workflows, the main folders, a few representative files.
    Your final message is the brief itself, in markdown, under 150 lines, with these sections:
    1. What the project is.
    2. Stack and layout: main folders and what lives in each.
    3. Setup in a fresh git worktree: dependencies to install, untracked files needed (.env…), services (database, cache…).
    4. Commands: lint, tests, build, dev server, and which ones gate a merge (CI).
    5. Conventions and rules the code follows.
    6. Pitfalls and known issues.
    State only what you verified in the files. Write "unknown" rather than guess.
    """

    static func analysisSystemPrompt(_ f: Feature) -> String {
        """
        You are the analyst of an automated pipeline: before any code is written, you study a request against this repository so that the developer agent starts with the full picture. Do not modify any file.
        The code is in a git worktree on branch \(f.branch), based on \(f.baseBranch) (commit \(f.baseCommit)).
        Read the code the request touches, its callers and its tests. Then answer:
        - feasibility: feasible, risky (doable but with real risks), or blocked (impossible without a decision, an access or an information the agents do not have);
        - summary: two or three sentences;
        - approach: how to do it in the way this codebase already works;
        - impacted: files and modules involved, each with why;
        - risks: the problems the developer must handle (edge cases, callers, data, migrations, compatibility, performance, security, tests);
        - assumptions: what you decided where the request is unclear, so the developer follows it;
        - acceptanceCriteria: testable statements that say the request is done.
        Be concrete: name files, functions and commands.
        Agents never commit, push or open the pull request (the user does it from the app): leave that out of the approach and the criteria.
        """
    }

    static let reviewLenses = [
        Lens(name: "Correctness", brief: "Hunt for bugs: wrong logic, broken callers, unhandled errors and edge cases, concurrency, security, data loss. Trace every caller of what changed."),
        Lens(name: "Spec & standards", brief: "Check the change against the request: is everything asked done, is anything done that was not asked, does it follow the repository's conventions (CLAUDE.md and the surrounding code), are there tests for new logic."),
    ]

    static let qaLenses = [
        Lens(name: "Quality gates", brief: "Find the project's checks (CLAUDE.md, package.json scripts, Makefile, CI workflows) and run them: lint, tests, build. Install dependencies first if the worktree has none. Each failure caused by the change is a blocker; a failure the repository documents as a known issue is minor."),
        Lens(name: "Behaviour", brief: "Exercise the feature against the request like a tester: main path, edge cases, invalid input, error paths. Use the existing test tooling or throwaway scripts, and compare what happens with what the request asks."),
    ]

    static func devSystemPrompt(_ f: Feature) -> String {
        """
        You are the developer in an automated pipeline: you implement, then independent agents review and test your work, then the user opens a pull request.
        You work in a git worktree created for this feature, on branch \(f.branch), based on \(f.baseBranch) (commit \(f.baseCommit)).
        Rules: stay inside this worktree. Do not commit, push or open a pull request: the user does it from the app. Install dependencies first if the worktree has none. Follow the repository's conventions (CLAUDE.md, surrounding code). Add or update tests for new logic. Run the relevant checks before you finish.
        Your final message becomes the draft of the pull request description: summarise what changed and how you verified it in a few short bullet points.
        """
    }

    static func checkSystemPrompt(_ f: Feature, role: Role) -> String {
        let diff = "The change is the difference between the working tree and commit \(f.baseCommit): see it with `git status` and `git diff \(f.baseCommit)`, and read the untracked files git status lists."
        if role == .review {
            return """
            You are an independent code reviewer in an automated pipeline. You did not write this change and you have no access to the developer's reasoning. Do not modify any file.
            \(diff)
            Report only issues you verified in the code, with the file and line. Severity: blocker (wrong behaviour, crash, data loss, security hole), major (likely bug, missing part of the request, no test for new logic), minor (style, naming, nit). Return no finding rather than a guess.
            """
        }
        return """
        You are a QA engineer in an automated pipeline. You did not write this change. Do not modify the repository's files: put any throwaway script in a temporary directory outside it.
        \(diff)
        Report each problem you reproduced, with the command and its output in the detail. Severity: blocker (a check fails or the feature misbehaves because of this change), major (an edge case breaks), minor (pre-existing failure, cosmetic).
        """
    }

    static func checkPrompt(_ f: Feature, lens: Lens) -> String {
        var prompt = "Your focus: \(lens.brief)\n\nThe request the change implements:\n\(f.request)"
        if let criteria = f.analysis?.acceptanceCriteria, !criteria.isEmpty {
            prompt += "\n\nAcceptance criteria:\n" + criteria.map { "- \($0)" }.joined(separator: "\n")
        }
        if let note = f.userNote { prompt += "\n\nNote from the developer who validates each step:\n\(note)" }
        return prompt
    }

    static func fixPrompt(_ findings: [Finding], from role: Role) -> String {
        let who = role == .review ? "Independent reviewers" : "QA agents"
        return """
        \(who), who have no access to this conversation, reported these issues on your change:

        \(findings.map(\.asText).joined(separator: "\n"))

        Fix every real issue. If you disagree with one, leave the code as is and say why in your final summary. Run the relevant checks again, then end with the updated summary of the whole change.
        """
    }
}
