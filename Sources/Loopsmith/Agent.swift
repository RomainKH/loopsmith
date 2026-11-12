import Foundation

struct AgentResult: Equatable {
    var sessionId: String?
    var text: String
    var structured: Data?
    var cost: Double?
    var isError: Bool
}

enum AgentEvent: Equatable {
    case session(String)
    case log(String)
    case result(AgentResult)
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

/// Everything that talks to the Claude Code CLI (`claude -p`, stream-json output).
enum Agent {
    static func arguments(model: String, permissionMode: String, systemPrompt: String, resume: String?,
                          schema: String?, readOnly: Bool, disabledMCP: [String], disabledSkills: [String]) -> [String] {
        var args = ["claude", "-p", "--output-format", "stream-json", "--verbose", "--model", model,
                    "--permission-mode", permissionMode, "--append-system-prompt", systemPrompt]
        if let resume { args += ["--resume", resume] }
        if let schema { args += ["--json-schema", schema] }
        let denied = (readOnly ? ["Edit", "Write", "NotebookEdit"] : [])
            + disabledMCP.map { "mcp__" + mcpToolPrefix($0) }
            + disabledSkills.map { "Skill(\($0))" }
        if !denied.isEmpty { args += ["--disallowedTools", denied.joined(separator: ",")] }
        return args
    }

    /// Tool name prefix Claude Code gives a server: "claude.ai Atlassian Rovo (2)" → "claude_ai_Atlassian_Rovo_2".
    static func mcpToolPrefix(_ server: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        var name = String(server.map { allowed.contains($0) ? $0 : "_" })
        while name.contains("__") { name = name.replacingOccurrences(of: "__", with: "_") }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Turns one stream-json line into what the app shows and keeps.
    static func parse(_ line: String) -> [AgentEvent] {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return line.trimmed.isEmpty ? [] : [.log(line)]
        }
        switch obj["type"] as? String {
        case "system":
            if obj["subtype"] as? String == "init", let id = obj["session_id"] as? String { return [.session(id)] }
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
        case "user":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { item in
                guard item["is_error"] as? Bool == true else { return nil }
                let text = item["content"] as? String
                    ?? (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
                    ?? ""
                return .log("✗ \(text.prefix(400))")
            }
        case "result":
            var structured: Data?
            if let value = obj["structured_output"], JSONSerialization.isValidJSONObject(value) {
                structured = try? JSONSerialization.data(withJSONObject: value)
            }
            return [.result(AgentResult(sessionId: obj["session_id"] as? String,
                                        text: obj["result"] as? String ?? "",
                                        structured: structured,
                                        cost: obj["total_cost_usd"] as? Double,
                                        isError: obj["is_error"] as? Bool ?? false))]
        default:
            return []
        }
    }

    private static func toolDetail(_ input: Any?) -> String {
        guard let input = input as? [String: Any] else { return "" }
        for key in ["command", "file_path", "pattern", "path", "url", "skill", "description"] {
            if let value = input[key] as? String { return String(value.replacingOccurrences(of: "\n", with: " ").prefix(200)) }
        }
        return ""
    }

    /// Reads the MCP servers and skills of a folder from the `init` event, then stops the session before it asks the model anything.
    static func inventory(cwd: String) async throws -> ToolInventory {
        var found: ToolInventory?
        var running: Process?
        _ = try await Shell.stream(["claude", "-p", "--output-format", "stream-json", "--verbose",
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
        guard let found else { throw AppError("claude did not list its tools (is Claude Code installed and logged in?)") }
        return found
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
