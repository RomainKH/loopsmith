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
}

@Suite struct AgentArgumentsTests {
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
