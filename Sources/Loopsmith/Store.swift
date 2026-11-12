import Foundation
import Observation

struct Settings: Codable, Equatable {
    var worktreesRoot = NSHomeDirectory() + "/Loopsmith"
    /// Model of the project brief and of the analysis of each request.
    var analysisModel = "claude-opus-5-5"
    var devModel = "claude-opus-5-5"
    var reviewModel = "claude-opus-5-5"
    var qaModel = "claude-opus-5-5"
    /// `claude --permission-mode`: auto, acceptEdits or bypassPermissions.
    var permissionMode = "auto"
    /// The same choice for Antigravity agents: an account may have no auto mode, and headless `agy` refuses
    /// whatever its rules do not allow.
    var antigravityPermissionMode = "auto"
    /// Stop after each step until the developer approves it.
    var approveEachStep = true
    /// Dev rounds allowed after each review and each QA before the leftovers become open points.
    var maxFixRounds = 2
    /// Untracked files copied from the repository into each new worktree.
    var copyFiles = ".env, .env.local"
    var jiraSite = ""
    var jiraEmail = ""
    var issueJQL = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC"
    var dailyHours = 8.0

    init() {}

    func permissionMode(for model: String) -> String {
        AgentProvider.detect(from: model) == .antigravity ? antigravityPermissionMode : permissionMode
    }

    /// Missing keys keep their default, so a settings file from an older version still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        worktreesRoot = try c.decodeIfPresent(String.self, forKey: .worktreesRoot) ?? d.worktreesRoot
        analysisModel = try c.decodeIfPresent(String.self, forKey: .analysisModel) ?? d.analysisModel
        devModel = try c.decodeIfPresent(String.self, forKey: .devModel) ?? d.devModel
        reviewModel = try c.decodeIfPresent(String.self, forKey: .reviewModel) ?? d.reviewModel
        qaModel = try c.decodeIfPresent(String.self, forKey: .qaModel) ?? d.qaModel
        permissionMode = try c.decodeIfPresent(String.self, forKey: .permissionMode) ?? d.permissionMode
        antigravityPermissionMode = try c.decodeIfPresent(String.self, forKey: .antigravityPermissionMode) ?? d.antigravityPermissionMode
        approveEachStep = try c.decodeIfPresent(Bool.self, forKey: .approveEachStep) ?? d.approveEachStep
        maxFixRounds = try c.decodeIfPresent(Int.self, forKey: .maxFixRounds) ?? d.maxFixRounds
        copyFiles = try c.decodeIfPresent(String.self, forKey: .copyFiles) ?? d.copyFiles
        jiraSite = try c.decodeIfPresent(String.self, forKey: .jiraSite) ?? d.jiraSite
        jiraEmail = try c.decodeIfPresent(String.self, forKey: .jiraEmail) ?? d.jiraEmail
        issueJQL = try c.decodeIfPresent(String.self, forKey: .issueJQL) ?? d.issueJQL
        dailyHours = try c.decodeIfPresent(Double.self, forKey: .dailyHours) ?? d.dailyHours
    }
}

@MainActor @Observable
final class AppStore {
    var features: [Feature] = []
    var projects: [Project] = []
    var settings: Settings
    var jiraToken: String
    var issues: [JiraIssue] = []
    var inventories: [String: ToolInventory] = [:]

    @ObservationIgnored var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var processes: [UUID: [Process]] = [:]

    /// `LOOPSMITH_HOME` keeps a separate set of features and settings (the end-to-end test uses it).
    static let folder = ProcessInfo.processInfo.environment["LOOPSMITH_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Loopsmith", isDirectory: true)
    private var featuresFile: URL { Self.folder.appendingPathComponent("features.json") }
    private var projectsFile: URL { Self.folder.appendingPathComponent("projects.json") }
    private var settingsFile: URL { Self.folder.appendingPathComponent("settings.json") }

    var jira: Jira { Jira(site: settings.jiraSite, email: settings.jiraEmail, token: jiraToken) }

    init() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.folder.path)
        settings = (try? Data(contentsOf: Self.folder.appendingPathComponent("settings.json")))
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        jiraToken = Keychain.get("jira")
        projects = Self.load(projectsFile) ?? []
        for i in projects.indices where projects[i].scanning {
            projects[i].scanning = false
            projects[i].scanError = "Interrupted when the app quit."
        }
        features = Self.load(featuresFile) ?? []
        // The app quit while agents ran: they are gone, the feature can be continued.
        for i in features.indices where features[i].running {
            features[i].running = false
            features[i].error = "Interrupted when the app quit. Continue to resume."
            for j in features[i].runs.indices where features[i].runs[j].status == .running {
                features[i].runs[j].status = .stopped
            }
        }
    }

    /// An unreadable file is kept aside instead of being overwritten on the next save.
    private static func load<T: Decodable>(_ file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let backup = file.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: backup)
            return nil
        }
    }

    private static func writeSecure(_ data: Data, to file: URL) {
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Blocks path traversal (`..`, absolute paths) and symlinks when copying untracked config files into a worktree.
    nonisolated static func isSafeCopyFile(_ name: String, repo: String, worktree: String) -> Bool {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains(".."),
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { return false }
        let components = (trimmed as NSString).pathComponents
        guard !components.contains(".."), !components.contains("/") else { return false }

        let repoRoot = URL(fileURLWithPath: repo, isDirectory: true).standardizedFileURL.path
        let worktreeRoot = URL(fileURLWithPath: worktree, isDirectory: true).standardizedFileURL.path
        let sourceURL = URL(fileURLWithPath: repoRoot).appendingPathComponent(trimmed).standardizedFileURL
        let targetURL = URL(fileURLWithPath: worktreeRoot).appendingPathComponent(trimmed).standardizedFileURL

        guard sourceURL.path.hasPrefix(repoRoot + "/"),
              targetURL.path.hasPrefix(worktreeRoot + "/") else { return false }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let type = attrs[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            return false
        }
        return true
    }

    func save() {
        if let data = try? JSONEncoder().encode(features) { Self.writeSecure(data, to: featuresFile) }
        if let data = try? JSONEncoder().encode(projects) { Self.writeSecure(data, to: projectsFile) }
    }

    func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        Self.writeSecure(data, to: settingsFile)
    }

    func feature(_ id: UUID) -> Feature? { features.first { $0.id == id } }
    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }
    func project(at path: String) -> Project? { projects.first { $0.path == path } }

    func updateProject(_ id: UUID, _ change: (inout Project) -> Void) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        change(&projects[i])
    }

    /// Registers a repository and has an agent write its brief.
    func addProject(path: String) async throws -> UUID {
        if let known = project(at: path) { return known.id }
        guard await Git.isRepo(path) else { throw AppError("\(path) is not a git repository.") }
        let project = Project(path: path, name: URL(fileURLWithPath: path).lastPathComponent,
                              baseBranch: await Git.defaultBranch(repo: path))
        projects.append(project)
        projects.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
        return project.id
    }

    /// Features stay, listed under "Other projects".
    func removeProject(_ id: UUID) {
        stop(id)
        projects.removeAll { $0.id == id }
        save()
    }

    func update(_ id: UUID, _ change: (inout Feature) -> Void) {
        guard let i = features.firstIndex(where: { $0.id == id }) else { return }
        change(&features[i])
    }

    func updateRun(_ id: UUID, _ runID: UUID, _ change: (inout AgentRun) -> Void) {
        update(id) { f in
            guard let j = f.runs.firstIndex(where: { $0.id == runID }) else { return }
            change(&f.runs[j])
        }
    }

    func refreshIssues() async {
        guard jira.isConfigured else { return }
        if let found = try? await jira.search(settings.issueJQL) { issues = found }
    }

    /// MCP servers and skills available in `folder`, read once per folder.
    func inventory(for folder: String, reload: Bool = false) async throws -> ToolInventory {
        if !reload, let known = inventories[folder] { return known }
        let found = try await Agent.inventory(cwd: folder)
        inventories[folder] = found
        return found
    }

    func createFeature(title: String, prompt: String, repo: String, base: String, issue: JiraIssue?,
                       disabledMCP: [String], disabledSkills: [String]) async throws -> UUID {
        let slug = Git.slug([issue?.key, title].compactMap { $0 }.joined(separator: " "))
        let branch = "feat/\(slug)"
        let root = (settings.worktreesRoot as NSString).expandingTildeInPath
        let path = "\(root)/\(URL(fileURLWithPath: repo).lastPathComponent)/\(slug)"
        let baseCommit = try await Git.addWorktree(repo: repo, base: base, branch: branch, path: path)
        for name in settings.copyFiles.split(separator: ",").map({ String($0).trimmed }) where !name.isEmpty {
            guard Self.isSafeCopyFile(name, repo: repo, worktree: path) else { continue }
            let source = URL(fileURLWithPath: repo).appendingPathComponent(name).standardizedFileURL.path
            let target = URL(fileURLWithPath: path).appendingPathComponent(name).standardizedFileURL.path
            if FileManager.default.fileExists(atPath: source), !FileManager.default.fileExists(atPath: target) {
                try? FileManager.default.copyItem(atPath: source, toPath: target)
            }
        }
        var context: String?
        if let issue {
            context = (try? await jira.issueContext(issue.key)) ?? "\(issue.key): \(issue.summary)"
        }
        let feature = Feature(title: title, prompt: prompt, jiraKey: issue?.key, jiraContext: context,
                              repoPath: repo, baseBranch: base, baseCommit: baseCommit, branch: branch, worktreePath: path,
                              disabledMCP: disabledMCP, disabledSkills: disabledSkills)
        features.insert(feature, at: 0)
        save()
        return feature.id
    }

    func remove(_ id: UUID, deleteWorktree: Bool) async throws {
        guard let f = feature(id) else { return }
        stop(id)
        if deleteWorktree, FileManager.default.fileExists(atPath: f.worktreePath) {
            try await Git.removeWorktree(repo: f.repoPath, path: f.worktreePath)
        }
        features.removeAll { $0.id == id }
        save()
    }

    func openPullRequest(_ id: UUID, title: String, body: String, draft: Bool) async throws {
        guard let f = feature(id) else { return }
        try await Git.commitAndPush(worktree: f.worktreePath, branch: f.branch, message: title)
        let url = try await GitHub.createPullRequest(worktree: f.worktreePath, base: f.baseBranch, branch: f.branch,
                                                     title: title, body: body, draft: draft)
        update(id) { $0.prURL = url; $0.phase = .prOpened }
        save()
    }

    /// Draft PR description: the dev agent's summary, the pipeline's outcome and its open points.
    func pullRequestBody(_ f: Feature) -> String {
        var parts: [String] = []
        if let key = f.jiraKey, let url = jira.browseURL(key) { parts.append("Jira: [\(key)](\(url.absoluteString))") }
        parts.append(f.lastDevSummary ?? f.prompt)
        let reviews = f.runs.filter { $0.role == .review && $0.status == .done }.count / 2
        let qas = f.runs.filter { $0.role == .qa && $0.status == .done }.count / 2
        parts.append("Reviewed by two independent agents (\(reviews) round(s)), tested by two QA agents (\(qas) round(s)).")
        if !f.unresolved.isEmpty {
            parts.append("### Open points\n" + f.unresolved.map(\.asText).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}
