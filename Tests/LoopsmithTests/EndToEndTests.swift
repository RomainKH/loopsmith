import Foundation
import Testing
@testable import Loopsmith

/// Runs the real pipeline (claude CLI, Haiku) on a throwaway repository. Opt-in: it costs a few cents and a few minutes.
/// LOOPSMITH_E2E=1 LOOPSMITH_HOME=$(mktemp -d) swift test --filter EndToEnd
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LOOPSMITH_E2E"] == "1"))
@MainActor struct EndToEndTests {
    @Test(.timeLimit(.minutes(20))) func featureGoesFromPromptToReady() async throws {
        let home = try #require(ProcessInfo.processInfo.environment["LOOPSMITH_HOME"])
        let repo = home + "/repo"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        try "export function add(a, b) {\n  return a + b;\n}\n".write(toFile: repo + "/math.js", atomically: true, encoding: .utf8)
        for args in [["init", "-b", "main"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-m", "init"]] {
            try await Shell.check(["git", "-C", repo] + args)
        }

        let store = AppStore()
        store.settings.worktreesRoot = home + "/worktrees"
        store.settings.devModel = "claude-haiku-5-5"
        store.settings.reviewModel = "claude-haiku-5-5"
        store.settings.qaModel = "claude-haiku-5-5"
        store.settings.maxFixRounds = 1

        store.settings.analysisModel = "claude-haiku-5-5"

        let inventory = try await store.inventory(for: repo)
        #expect(!inventory.skills.isEmpty)

        let projectID = try await store.addProject(path: repo)
        store.scanProject(projectID)
        while store.project(projectID)?.scanning == true { try await Task.sleep(for: .seconds(2)) }
        let project = try #require(store.project(projectID))
        #expect(project.scanError == nil, "\(project.scanError ?? "")")
        #expect(project.brief?.contains("math.js") == true)

        let id = try await store.createFeature(title: "Double", prompt: "Add and export a function `double(n)` in math.js that returns n * 2. Keep it in plain JavaScript, no dependency, no test framework.",
                                               repo: repo, base: "main", issue: nil, disabledMCP: inventory.servers.map(\.name), disabledSkills: [])
        store.start(id)
        while store.feature(id)?.running == true { try await Task.sleep(for: .seconds(2)) }

        let f = try #require(store.feature(id))
        #expect(f.error == nil, "\(f.error ?? "")")
        #expect(f.phase == .ready)
        #expect(f.runs.first?.role == .analysis)
        #expect(f.analysis?.acceptanceCriteria.isEmpty == false)
        #expect(f.runs.filter { $0.role == .review }.count >= 2)
        #expect(f.runs.filter { $0.role == .qa }.count >= 2)
        #expect(f.runs.allSatisfy { $0.status == .done })
        let code = try String(contentsOfFile: f.worktreePath + "/math.js", encoding: .utf8)
        #expect(code.contains("double"))
        for run in f.runs { print("[\(run.role.rawValue) · \(run.lens)] \(run.findings?.count ?? 0) finding(s), $\(run.cost ?? 0)") }
    }
}
