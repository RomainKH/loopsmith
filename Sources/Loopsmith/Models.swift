import Foundation

/// Where a feature stands in the pipeline: analysis, dev, review (and its fixes), QA (and its fixes), then the pull request.
enum Phase: String, Codable {
    case analysis, dev, review, fixReview, qa, fixQA, ready, prOpened

    var label: String {
        switch self {
        case .analysis: "Analysis"
        case .dev: "Development"
        case .review: "Review"
        case .fixReview: "Fixing review findings"
        case .qa: "QA"
        case .fixQA: "Fixing QA findings"
        case .ready: "Ready for PR"
        case .prOpened: "PR opened"
        }
    }

    /// Step of the strip: 0 analysis, 1 dev, 2 review, 3 QA, 4 PR, 5 all done.
    var step: Int {
        switch self {
        case .analysis: 0
        case .dev: 1
        case .review, .fixReview: 2
        case .qa, .fixQA: 3
        case .ready: 4
        case .prOpened: 5
        }
    }
}

enum Role: String, Codable, CaseIterable {
    case analysis, dev, review, qa

    var title: String {
        switch self {
        case .analysis: "Analysis & Brief"
        case .dev: "Development"
        case .review: "Code Review"
        case .qa: "Quality Assurance"
        }
    }

    var shortTitle: String {
        switch self {
        case .analysis: "Analysis"
        case .dev: "Dev"
        case .review: "Review"
        case .qa: "QA"
        }
    }

    var icon: String {
        switch self {
        case .analysis: "magnifyingglass.circle.fill"
        case .dev: "hammer.fill"
        case .review: "eye.fill"
        case .qa: "checkmark.shield.fill"
        }
    }

    var personaName: String {
        switch self {
        case .analysis: "Nova"
        case .dev: "Atlas"
        case .review: "Orion"
        case .qa: "Aegis"
        }
    }

    var personaTitle: String {
        switch self {
        case .analysis: "Architect & Scout"
        case .dev: "Forge Builder"
        case .review: "Code Inspector"
        case .qa: "QA Sentinel"
        }
    }

    var actionVerb: String {
        switch self {
        case .analysis: "Scanning codebase & blueprint…"
        case .dev: "Forging implementation…"
        case .review: "Inspecting diff & edge cases…"
        case .qa: "Running quality gates & tests…"
        }
    }
}

/// AI CLI connector backing an agent role: `claude -p`, `gemini -p` or the Antigravity CLI `agy --print`.
/// The model string says which: `gemini-*` runs on Gemini CLI, `agy:<model>` on Antigravity (which also serves
/// Claude models, hence the prefix), anything else on Claude Code.
enum AgentProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case gemini
    case antigravity

    static let antigravityPrefix = "agy:"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        case .antigravity: "Antigravity CLI"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        }
    }

    var binary: String {
        switch self {
        case .claude: "claude"
        case .gemini: "gemini"
        case .antigravity: "agy"
        }
    }

    var icon: String {
        switch self {
        case .claude: "bolt.horizontal.fill"
        case .gemini: "sparkles"
        case .antigravity: "arrow.up.right.circle.fill"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: "claude-opus-5-5"
        case .gemini: "gemini-2.5-pro"
        case .antigravity: "agy:gemini-4-argon-medium"
        }
    }

    /// Shown until the CLI lists its own (Antigravity: `agy models`, per account).
    var presetModels: [String] {
        switch self {
        case .claude:
            ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]
        case .gemini:
            ["gemini-2.5-pro", "gemini-2.5-flash"]
        case .antigravity:
            ["agy:gemini-4-argon-high", "agy:gemini-4-argon-medium", "agy:gemini-3.8-flash-medium",
             "agy:claude-opus-5-5-high", "agy:claude-sonnet-5-5-medium"]
        }
    }

    static func detect(from model: String) -> AgentProvider {
        let m = model.trimmed.lowercased()
        if m.hasPrefix(antigravityPrefix) { return .antigravity }
        return m.hasPrefix("gemini") ? .gemini : .claude
    }

    /// The model name the CLI itself takes: "agy:gemini-4-argon-medium" → "gemini-4-argon-medium".
    static func cliModel(_ model: String) -> String {
        let m = model.trimmed
        return m.lowercased().hasPrefix(antigravityPrefix) ? String(m.dropFirst(antigravityPrefix.count)) : m
    }

    /// The model string stored for this provider: Antigravity models get their prefix.
    func storedModel(_ name: String) -> String {
        let bare = Self.cliModel(name)
        return self == .antigravity ? Self.antigravityPrefix + bare : bare
    }
}

enum RunStatus: String, Codable { case running, done, failed, stopped }

/// One issue reported by a reviewer or a QA agent.
struct Finding: Codable, Hashable {
    var severity: String
    var file: String?
    var line: Int?
    var title: String
    var detail: String

    var isBlocking: Bool { severity == "blocker" || severity == "major" }

    var location: String {
        guard let file, !file.isEmpty else { return "" }
        return line.map { "\(file):\($0)" } ?? file
    }

    var asText: String {
        let place = location.isEmpty ? "" : "\(location) "
        return "- [\(severity)] \(place)\(title)\n  \(detail)"
    }
}

/// Structured answer of a review or QA agent.
struct Verdict: Codable {
    var summary: String
    var findings: [Finding]
}

/// What the analysis agent found when it read the request against the codebase, before any code is written.
struct Analysis: Codable, Equatable {
    var feasibility: String
    var summary: String
    var approach: String
    var impacted: [String]
    var risks: [String]
    var assumptions: [String]
    var acceptanceCriteria: [String]

    var isBlocked: Bool { feasibility == "blocked" }

    var asText: String {
        func list(_ title: String, _ items: [String]) -> String {
            items.isEmpty ? "" : "\n\(title):\n" + items.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return "Feasibility: \(feasibility)\n\(summary)\n\nApproach:\n\(approach)\n"
            + list("Files and modules involved", impacted)
            + list("Problems to handle", risks)
            + list("Assumptions", assumptions)
            + list("Acceptance criteria", acceptanceCriteria)
    }
}

/// A repository registered once: its brief, written by an agent, is given to every agent of its features.
struct Project: Codable, Identifiable {
    var id = UUID()
    var path: String
    var name: String
    var baseBranch: String
    var brief: String?
    var briefUpdatedAt: Date?
    /// MCP servers and skills new features of this project start without.
    var disabledMCP: [String] = []
    var disabledSkills: [String] = []
    var scanning = false
    var scanLog: [String] = []
    var scanError: String?
    /// Jira project keys of this repository's tickets, as typed ("APP, WEB"); nil in files saved before.
    var jiraKeys: String?

    var jiraKeyList: [String] {
        (jiraKeys ?? "").split(whereSeparator: { $0 == "," || $0.isWhitespace }).map { $0.uppercased() }
    }

    /// Whether a ticket belongs to this project; every ticket does while no key is set.
    func owns(issueKey: String) -> Bool {
        jiraKeyList.isEmpty || jiraKeyList.contains { issueKey.uppercased().hasPrefix($0 + "-") }
    }
}

struct AgentRun: Codable, Identifiable {
    static let maxLogLines = 600

    var id = UUID()
    var role: Role
    var lens: String
    var model: String
    var status = RunStatus.running
    var startedAt = Date()
    var endedAt: Date?
    var sessionId: String?
    var log: [String] = []
    var summary: String?
    var findings: [Finding]?
    var cost: Double?
    var tokens: Int?
    var error: String?

    /// Cached O(1) counters so SwiftUI views never scan `log` on render.
    var loggedChars: Int?
    var loggedTools: Int?
    var lastActivityLine: String?

    var provider: AgentProvider { AgentProvider.detect(from: model) }

    /// Duration in seconds (live while running).
    var durationSeconds: Int {
        max(Int((endedAt ?? Date()).timeIntervalSince(startedAt)), 0)
    }

    /// Number of tool invocations logged (`→ ...`) in O(1).
    var toolCallsCount: Int {
        if let loggedTools { return loggedTools }
        return log.reduce(0) { $0 + ($1.hasPrefix("→ ") ? 1 : 0) }
    }

    /// Latest tool invocation or log line for live speech bubbles in O(1).
    var latestActivity: String? {
        if let lastActivityLine { return lastActivityLine }
        return log.last { !$0.trimmed.isEmpty }
    }

    /// Reported token count from the CLI, or a conservative O(1) estimate from the streamed transcript.
    var effectiveTokens: Int {
        if let tokens, tokens > 0 { return tokens }
        let chars = (loggedChars ?? log.reduce(0) { $0 + $1.count }) + (summary?.count ?? 0)
        guard chars > 0 else { return status == .running ? 180 : 0 }
        return max(chars / 4, 120)
    }

    var hasExactTokens: Bool {
        (tokens ?? 0) > 0
    }

    mutating func append(log line: String) {
        recordLog(line, continuing: false)
    }

    mutating func recordLog(_ text: String, continuing: Bool) {
        if loggedChars == nil { loggedChars = log.reduce(0) { $0 + $1.count } }
        if loggedTools == nil { loggedTools = log.reduce(0) { $0 + ($1.hasPrefix("→ ") ? 1 : 0) } }
        loggedChars = (loggedChars ?? 0) + text.count
        if !continuing && text.hasPrefix("→ ") {
            loggedTools = (loggedTools ?? 0) + 1
        }
        log.appendLog(text, continuing: continuing)
        if let last = log.last, !last.trimmed.isEmpty {
            lastActivityLine = last
        }
    }
}

struct Feature: Codable, Identifiable {
    var id = UUID()
    var title: String
    var prompt: String
    var jiraKey: String?
    var jiraContext: String?
    var repoPath: String
    var baseBranch: String
    var baseCommit: String
    var branch: String
    var worktreePath: String
    var createdAt = Date()
    var phase = Phase.analysis
    var analysis: Analysis?
    var running = false
    var reviewFixes = 0
    var qaFixes = 0
    var devSessionId: String?
    /// Findings the dev agent must handle next.
    var pending: [Finding] = []
    /// Blocking findings still there when the fix rounds ran out.
    var unresolved: [Finding] = []
    /// MCP server names and skill names the agents of this feature must not use.
    var disabledMCP: [String] = []
    var disabledSkills: [String] = []
    var runs: [AgentRun] = []
    var error: String?
    var prURL: String?
    /// The step before `phase` is done and waits for the developer's approval (nil in files saved before approvals existed).
    var awaitingApproval: Bool?
    /// The developer's note, given to the agents of the next step.
    var userNote: String?

    var isAwaiting: Bool { awaitingApproval == true }

    /// Approves the finished step. Before a fix round, only the findings kept are sent to dev; none kept moves on.
    mutating func approve(note: String?, keeping kept: [Finding]? = nil) {
        awaitingApproval = false
        userNote = note?.nonEmpty?.trimmed
        guard phase == .fixReview || phase == .fixQA, let kept else { return }
        pending = kept
        if kept.isEmpty { phase = phase == .fixReview ? .qa : .ready }
    }

    /// Moves on without fixing: the findings stay as open points for the pull request.
    mutating func skipFixes() {
        awaitingApproval = false
        unresolved += pending
        pending = []
        phase = phase == .fixReview ? .qa : .ready
    }

    /// Sends the dev agent back to work on the developer's request; review and QA run again after it.
    mutating func requestChanges(_ note: String) {
        awaitingApproval = false
        userNote = note.trimmed
        pending = []
        phase = .dev
    }

    /// Runs the analysis again with the developer's note; the new analysis sees the previous one.
    mutating func redoAnalysis(_ note: String) {
        awaitingApproval = false
        userNote = note.trimmed
        phase = .analysis
    }

    /// What the agents are asked to build: the user's prompt and the Jira ticket.
    var request: String {
        guard let jiraContext, !jiraContext.isEmpty else { return prompt }
        return "\(prompt)\n\nJira ticket:\n\(jiraContext)"
    }

    /// The request plus the analysis, for the dev agent.
    var devRequest: String {
        guard let analysis else { return request }
        return "\(request)\n\nAnalysis of this request against the codebase, by another agent (check it in the code before relying on it):\n\(analysis.asText)"
    }

    var lastDevSummary: String? { runs.last { $0.role == .dev && $0.status == .done }?.summary }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { trimmed.isEmpty ? nil : self }
}
