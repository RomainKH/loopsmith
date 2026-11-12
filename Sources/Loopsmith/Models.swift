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

enum Role: String, Codable { case analysis, dev, review, qa }

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
}

struct AgentRun: Codable, Identifiable {
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
    var error: String?

    mutating func append(log line: String) {
        log.append(line)
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
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
