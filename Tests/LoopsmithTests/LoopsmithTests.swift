import Foundation
import Testing
@testable import Loopsmith

@Suite struct AgentParsingTests {
    @Test func initGivesTheSession() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc","tools":[]}"#
        #expect(Agent.parse(line) == [.session("abc")])
    }

    @Test func toolUseAndTextBecomeLogLines() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":""},{"type":"text","text":" Done. "},{"type":"tool_use","name":"Bash","input":{"command":"npm test","description":"Run tests"}}]}}"#
        #expect(Agent.parse(line) == [.log("Done."), .log("→ Bash npm test")])
    }

    @Test func onlyFailedToolResultsAreShown() {
        let ok = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"fine"}]}}"#
        let failed = #"{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":[{"type":"text","text":"denied"}]}]}}"#
        #expect(Agent.parse(ok).isEmpty)
        #expect(Agent.parse(failed) == [.log("✗ denied")])
    }

    @Test func resultCarriesTheStructuredVerdict() throws {
        let line = #"{"type":"result","is_error":false,"result":"ok","session_id":"s1","total_cost_usd":0.5,"structured_output":{"summary":"fine","findings":[{"severity":"major","title":"Off by one","detail":"loop ends early"}]}}"#
        guard case .result(let r) = Agent.parse(line).first else { Issue.record("no result"); return }
        #expect(r.sessionId == "s1" && r.cost == 0.5 && !r.isError)
        let verdict = try JSONDecoder().decode(Verdict.self, from: try #require(r.structured))
        #expect(verdict.findings.first?.isBlocking == true)
        #expect(verdict.findings.first?.location == "")
    }

    @Test func plainOutputIsKept() {
        #expect(Agent.parse("not json") == [.log("not json")])
        #expect(Agent.parse("  ").isEmpty)
    }

    /// The real Gemini CLI stream (0.47, nonInteractiveCli): the answer comes as `delta` pieces, cut anywhere, and the
    /// success `result` carries stats only. Joining the pieces with line breaks put a newline inside the JSON strings.
    @Test func geminiStreamGivesBackTheWholeFinalMessage() throws {
        let lines = [
            #"{"type":"init","session_id":"0b6f8a39-2c1e-4c55-9a43-8f1f6d7e2a10","model":"gemini-2.5-pro"}"#,
            #"{"type":"message","role":"user","content":"Review this"}"#,
            #"{"type":"message","role":"assistant","content":"Let me look at ","delta":true}"#,
            #"{"type":"message","role":"assistant","content":"the diff.","delta":true}"#,
            #"{"type":"tool_use","tool_name":"run_shell_command","tool_id":"t1","parameters":{"command":"git diff abc"}}"#,
            #"{"type":"tool_result","tool_id":"t1","status":"success","output":"+x"}"#,
            #"{"type":"message","role":"assistant","content":"{\"summary\":\"Looks g","delta":true}"#,
            #"{"type":"message","role":"assistant","content":"ood\",\"findings\":[]}","delta":true}"#,
            #"{"type":"result","status":"success","stats":{"total_tokens":10}}"#,
        ]
        var reply = ReplyBuffer()
        var log: [String] = []
        var result: AgentResult?
        for line in lines {
            for event in Agent.parse(line) {
                let continues = reply.take(event)
                switch event {
                case .delta(let piece): log.appendLog(piece, continuing: continues)
                case .log(let text): log.appendLog(text, continuing: false)
                case .result(let r): result = r
                case .session: break
                }
            }
        }
        #expect(Agent.parse(lines[0]) == [.session("0b6f8a39-2c1e-4c55-9a43-8f1f6d7e2a10")])
        #expect(log == ["Let me look at the diff.", "→ run_shell_command git diff abc", #"{"summary":"Looks good","findings":[]}"#])
        let done = try #require(result)
        #expect(!done.isError && done.text.isEmpty)
        let verdict = try JSONDecoder().decode(Verdict.self, from: try #require(Agent.extractStructuredJSON(from: reply.text)))
        #expect(verdict.summary == "Looks good")
    }

    @Test func geminiErrorsAreReported() {
        let failed = #"{"type":"result","status":"error","error":{"type":"FatalAuthenticationError","message":"Error authenticating"}}"#
        guard case .result(let r) = Agent.parse(failed).first else { Issue.record("no result"); return }
        #expect(r.isError && r.text == "Error authenticating")
        #expect(Agent.parse(#"{"type":"tool_result","status":"error","error":{"message":"permission denied"}}"#) == [.log("✗ permission denied")])
    }
}

@Suite struct AgentArgumentsTests {
    @Test func providerIsDetectedFromModelName() {
        #expect(AgentProvider.detect(from: "claude-opus-5-5") == .claude)
        #expect(AgentProvider.detect(from: "gemini-2.5-pro") == .gemini)
        #expect(AgentProvider.detect(from: "GEMINI-3-FLASH-PREVIEW") == .gemini)
    }

    @Test func geminiArgumentsUseHeadlessStreamJsonAndResume() {
        let args = Agent.arguments(model: "gemini-2.5-pro", permissionMode: "auto", systemPrompt: "Be concise.",
                                   resume: "gem-session-1", schema: Agent.verdictSchema, readOnly: true,
                                   disabledMCP: [], disabledSkills: [])
        #expect(args.first == "gemini")
        #expect(args.contains("--output-format") && args.contains("stream-json"))
        #expect(args.contains("--skip-trust"))
        #expect(args.contains("--approval-mode") && args.contains("yolo"))
        #expect(args.contains("--resume") && args.contains("gem-session-1"))
        let pIndex = try! #require(args.firstIndex(of: "-p"))
        #expect(args[pIndex + 1].contains("Be concise.") && args[pIndex + 1].contains("read-only mode"))
    }
    @Test func mcpPrefixesMatchClaudeCodeToolNames() {
        #expect(Agent.mcpToolPrefix("claude.ai Atlassian Rovo (2)") == "claude_ai_Atlassian_Rovo_2")
        #expect(Agent.mcpToolPrefix("plugin:claude-mem:mcp-search") == "plugin_claude-mem_mcp-search")
        #expect(Agent.mcpToolPrefix("codebase-memory-mcp") == "codebase-memory-mcp")
    }

    @Test func disabledToolsAndReadOnlyBecomeOneDenyList() {
        let args = Agent.arguments(model: "m", permissionMode: "auto", systemPrompt: "s", resume: "r", schema: nil, readOnly: true,
                                   disabledMCP: ["claude.ai Airtable"], disabledSkills: ["ponytail"])
        let i = try! #require(args.firstIndex(of: "--disallowedTools"))
        #expect(args[i + 1] == "Edit,Write,NotebookEdit,mcp__claude_ai_Airtable,Skill(ponytail)")
        #expect(args.contains("--resume"))
    }

    @Test func devAgentWithEverythingOnHasNoDenyList() {
        let args = Agent.arguments(model: "m", permissionMode: "auto", systemPrompt: "s", resume: nil, schema: nil, readOnly: false,
                                   disabledMCP: [], disabledSkills: [])
        #expect(!args.contains("--disallowedTools") && !args.contains("--resume"))
    }
}

@Suite struct AnalysisTests {
    let analysis = Analysis(feasibility: "risky", summary: "Doable.", approach: "Reuse the helper.", impacted: ["a.js: entry"],
                            risks: ["Old rows have no value"], assumptions: [], acceptanceCriteria: ["double(2) returns 4"])

    func feature(_ analysis: Analysis?) -> Feature {
        Feature(title: "t", prompt: "Add double", repoPath: "/r", baseBranch: "main", baseCommit: "abc", branch: "feat/t",
                worktreePath: "/w", analysis: analysis)
    }

    @Test func devGetsTheWholeAnalysis() {
        let text = feature(analysis).devRequest
        #expect(text.hasPrefix("Add double"))
        #expect(text.contains("Feasibility: risky") && text.contains("- Old rows have no value") && text.contains("- double(2) returns 4"))
        #expect(!text.contains("Assumptions"))
        #expect(feature(nil).devRequest == "Add double")
    }

    @Test func checkersGetTheCriteriaOnly() {
        let prompt = Agent.checkPrompt(feature(analysis), lens: Agent.reviewLenses[0])
        #expect(prompt.contains("- double(2) returns 4") && !prompt.contains("Old rows"))
    }

    @Test func briefIsAppendedWhenThereIsOne() {
        #expect(Agent.withBrief("role", brief: nil) == "role")
        #expect(Agent.withBrief("role", brief: "  ") == "role")
        #expect(Agent.withBrief("role", brief: "Node app").hasSuffix("Node app"))
    }

    @Test func newFeaturesStartWithTheAnalysis() {
        #expect(feature(nil).phase == .analysis)
    }

    @Test func featuresSavedBeforeTheAnalysisExistedStillLoad() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode([feature(nil)])) as! [[String: Any]]
        old[0].removeValue(forKey: "analysis")
        old[0]["phase"] = "dev"
        let loaded = try JSONDecoder().decode([Feature].self, from: JSONSerialization.data(withJSONObject: old))
        #expect(loaded[0].phase == .dev && loaded[0].analysis == nil)
    }
}

@Suite struct ApprovalTests {
    let major = Finding(severity: "major", title: "a", detail: "")
    let blocker = Finding(severity: "blocker", title: "b", detail: "")

    func waiting(at phase: Phase, pending: [Finding] = []) -> Feature {
        var f = Feature(title: "t", prompt: "p", repoPath: "/r", baseBranch: "main", baseCommit: "abc", branch: "feat/t", worktreePath: "/w")
        f.phase = phase
        f.pending = pending
        f.awaitingApproval = true
        return f
    }

    @Test func approveKeepsOnlyTheTickedFindings() {
        var f = waiting(at: .fixReview, pending: [major, blocker])
        f.approve(note: "  only b  ", keeping: [blocker])
        #expect(f.pending == [blocker] && f.phase == .fixReview && !f.isAwaiting && f.userNote == "only b")
    }

    @Test func droppingEveryFindingMovesOn() {
        var review = waiting(at: .fixReview, pending: [major])
        review.approve(note: nil, keeping: [])
        #expect(review.phase == .qa && review.pending.isEmpty && review.unresolved.isEmpty)
        var qa = waiting(at: .fixQA, pending: [major])
        qa.approve(note: "", keeping: [])
        #expect(qa.phase == .ready && qa.userNote == nil)
    }

    @Test func skippedFindingsBecomeOpenPoints() {
        var f = waiting(at: .fixQA, pending: [major])
        f.skipFixes()
        #expect(f.phase == .ready && f.unresolved == [major] && f.pending.isEmpty)
    }

    @Test func changesGoBackToDevAndAnalysisCanBeRedone() {
        var f = waiting(at: .ready)
        f.requestChanges(" rename it ")
        #expect(f.phase == .dev && f.userNote == "rename it" && !f.isAwaiting)
        var g = waiting(at: .dev)
        g.redoAnalysis("missed the callers")
        #expect(g.phase == .analysis && g.userNote == "missed the callers")
    }

    @Test func theNoteReachesReviewAndQA() {
        var f = waiting(at: .review)
        f.approve(note: "check the empty cart")
        #expect(Agent.checkPrompt(f, lens: Agent.qaLenses[1]).hasSuffix("check the empty cart"))
    }

    @Test func approvalsAreOnByDefault() throws {
        #expect(Settings().approveEachStep)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).approveEachStep)
    }
}

@Suite struct PipelineTests {
    let major = Finding(severity: "major", title: "a", detail: "")
    let minor = Finding(severity: "minor", title: "b", detail: "")

    @Test func cleanRoundMovesOn() {
        let next = Pipeline.afterRound([minor], fixesDone: 0, maxFixes: 2)
        #expect(next.fix.isEmpty && next.unresolved.isEmpty)
    }

    @Test func blockingFindingsGoBackToDevWhileRoundsAreLeft() {
        let next = Pipeline.afterRound([major, minor], fixesDone: 1, maxFixes: 2)
        #expect(next.fix == [major] && next.unresolved.isEmpty)
    }

    @Test func leftoversBecomeOpenPointsWhenRoundsRunOut() {
        let next = Pipeline.afterRound([major], fixesDone: 2, maxFixes: 2)
        #expect(next.fix.isEmpty && next.unresolved == [major])
    }
}

@Suite struct FormattingTests {
    @Test func durations() {
        #expect(Jira.parseDuration("1h 30m") == 5400)
        #expect(Jira.parseDuration("1h30") == 5400)
        #expect(Jira.parseDuration("45m") == 2700)
        #expect(Jira.parseDuration("1,5h") == 5400)
        #expect(Jira.parseDuration("90") == 5400)
        #expect(Jira.parseDuration("abc") == nil)
        #expect(Jira.parseDuration("0m") == nil)
        #expect(Jira.formatDuration(5400) == "1h 30m")
        #expect(Jira.formatDuration(7200) == "2h")
        #expect(Jira.formatDuration(900) == "15m")
    }

    @Test func slugs() {
        #expect(Git.slug("APP-42 Barre de livraison offerte") == "app-42-barre-de-livraison-offerte")
        #expect(Git.slug("Été : déjà !") == "ete-deja")
        #expect(Git.slug("???") == "feature")
        #expect(Git.slug(String(repeating: "ab ", count: 30)).count <= 48)
        #expect(!Git.slug(String(repeating: "ab ", count: 30)).hasSuffix("-"))
    }

    @Test func oldSettingsFileStillLoads() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"jiraSite":"x.atlassian.net"}"#.utf8))
        #expect(settings.jiraSite == "x.atlassian.net" && settings.devModel == "claude-opus-5-5")
    }
}

@Suite struct SecurityHardeningTests {
    @Test func gitRefValidationBlocksFlagInjectionAndTraversal() {
        #expect(Git.isSafeRef("main"))
        #expect(Git.isSafeRef("feat/app-42-shipping"))
        #expect(!Git.isSafeRef("-f"))
        #expect(!Git.isSafeRef("--upload-pack=evil"))
        #expect(!Git.isSafeRef("feat/../main"))
        #expect(!Git.isSafeRef("branch.lock"))
        #expect(!Git.isSafeRef("branch with spaces"))
    }

    @Test func jiraRequiresHTTPSAndBlocksSSRFAndPathTraversal() {
        let valid = Jira(site: "yourteam.atlassian.net", email: "dev@example.com", token: "tok")
        #expect(valid.isConfigured)
        #expect(valid.baseURL == "https://yourteam.atlassian.net")
        #expect(valid.browseURL("APP-42")?.absoluteString == "https://yourteam.atlassian.net/browse/APP-42")
        #expect(valid.browseURL("../../rest/api/3/myself") == nil)

        let cleartext = Jira(site: "http://yourteam.atlassian.net", email: "dev@example.com", token: "tok")
        #expect(!cleartext.isConfigured && cleartext.validatedBaseURL == nil)

        let metadataSSRF = Jira(site: "https://169.254.169.254", email: "dev@example.com", token: "tok")
        #expect(!metadataSSRF.isConfigured)

        let localhostSSRF = Jira(site: "https://localhost:8080", email: "dev@example.com", token: "tok")
        #expect(!localhostSSRF.isConfigured)

        #expect(Jira.isValidIssueKey("APP-42"))
        #expect(!Jira.isValidIssueKey("../etc/passwd"))
        #expect(!Jira.isValidIssueKey("APP-42?fields=all"))
    }

    @Test func worktreeCopyBlocksPathTraversal() {
        #expect(AppStore.isSafeCopyFile(".env", repo: "/tmp/repo", worktree: "/tmp/wt"))
        #expect(AppStore.isSafeCopyFile(".env.local", repo: "/tmp/repo", worktree: "/tmp/wt"))
        #expect(!AppStore.isSafeCopyFile("../.ssh/id_rsa", repo: "/tmp/repo", worktree: "/tmp/wt"))
        #expect(!AppStore.isSafeCopyFile("/etc/passwd", repo: "/tmp/repo", worktree: "/tmp/wt"))
        #expect(!AppStore.isSafeCopyFile("~/.aws/credentials", repo: "/tmp/repo", worktree: "/tmp/wt"))
    }

    @Test func agentArgumentsBlockCLIFlagInjection() {
        let args = Agent.arguments(model: "--dangerously-skip-permissions", permissionMode: "--evil",
                                   systemPrompt: "sys", resume: "--injected-flag", schema: nil,
                                   readOnly: true, disabledMCP: [], disabledSkills: [])
        #expect(!args.contains("--dangerously-skip-permissions"))
        #expect(!args.contains("--evil"))
        #expect(!args.contains("--injected-flag"))
        #expect(args.contains("claude-opus-5-5"))
        #expect(args.contains("auto"))
    }

    @Test func githubSafeHTTPSURLRejectsUnsafeSchemes() {
        #expect(GitHub.safeHTTPSURL("https://github.com/org/repo/pull/1") != nil)
        #expect(GitHub.safeHTTPSURL("http://github.com/org/repo/pull/1") == nil)
        #expect(GitHub.safeHTTPSURL("javascript:alert(1)") == nil)
        #expect(GitHub.safeHTTPSURL("file:///etc/passwd") == nil)
    }

    @Test func shellEnvironmentSanitizesInjectionVariables() {
        #expect(Shell.environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(Shell.environment["LD_PRELOAD"] == nil)
        #expect(Shell.environment["GIT_TERMINAL_PROMPT"] == "0")
    }
}
