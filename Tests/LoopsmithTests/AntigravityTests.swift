import Foundation
import Testing
@testable import Loopsmith

/// Lines recorded from real `agy` 1.5.6 runs (2026-11-12), trimmed to the fields the app reads.
@Suite struct AntigravityTests {
    @Test func streamGivesTheReplyTheToolsAndTheVerdict() throws {
        let lines = [
            #"{"event":"init","conversation_id":"433a23d5-3857-43f9-a2ba-80e3f5a3eda2","init":{"model":"gemini-3.8-flash-low","permission_mode":"request-review"}}"#,
            #"{"event":"step_update","step_update":{"step_index":0,"state":"DONE","step_type":"user_input"}}"#,
            #"{"event":"step_update","step_update":{"step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"Let me check "}}"#,
            #"{"event":"step_update","step_update":{"step_index":1,"state":"DONE","step_type":"agent_response","text_delta":"the file."}}"#,
            #"{"event":"step_update","step_update":{"step_index":2,"state":"ACTIVE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"cat a.txt"}}}}"#,
            #"{"event":"step_update","step_update":{"step_index":2,"state":"DONE","step_type":"tool","tool_name":"run_command","tool_info":{"name":"run_command","parameters":{"CommandLine":"cat a.txt"},"output":"hello"}}}"#,
            #"{"event":"step_update","step_update":{"step_index":3,"state":"ACTIVE","step_type":"tool","tool_name":"call_mcp_tool","tool_info":{"parameters":{"Arguments":{},"ServerName":"airtable","ToolName":"list_bases"}}}}"#,
            #"{"event":"step_update","step_update":{"step_index":3,"state":"ERROR","step_type":"tool","tool_name":"call_mcp_tool"}}"#,
            #"{"event":"step_update","step_update":{"step_index":4,"state":"ACTIVE","step_type":"agent_response","text_delta":"{\"findings\":[],\"summ"}}"#,
            #"{"event":"step_update","step_update":{"step_index":4,"state":"DONE","step_type":"agent_response","text_delta":"ary\":\"ok\"}"}}"#,
            #"{"event":"step_update","step_update":{"step_index":5,"state":"DONE","step_type":"finish"}}"#,
            #"{"event":"result","result":{"conversation_id":"433a23d5-3857-43f9-a2ba-80e3f5a3eda2","status":"SUCCESS","response":"{\"findings\":[],\"summary\":\"ok\"}","structured_output":{"findings":[],"summary":"ok"}}}"#,
        ]
        var reply = ReplyBuffer()
        var log: [String] = []
        var events: [AgentEvent] = []
        for line in lines {
            for event in Agent.parse(line) {
                events.append(event)
                let continues = reply.take(event)
                switch event {
                case .delta(let piece): log.appendLog(piece, continuing: continues)
                case .log(let text): log.appendLog(text, continuing: false)
                case .session, .result: break
                }
            }
        }
        #expect(events.first == .session("433a23d5-3857-43f9-a2ba-80e3f5a3eda2"))
        #expect(log == ["Let me check the file.", "→ run_command cat a.txt", "→ call_mcp_tool airtable/list_bases",
                        "✗ call_mcp_tool: refused or failed", #"{"findings":[],"summary":"ok"}"#])
        guard case .result(let r) = events.last else { Issue.record("no result"); return }
        #expect(!r.isError && r.sessionId == "433a23d5-3857-43f9-a2ba-80e3f5a3eda2")
        #expect(try JSONDecoder().decode(Verdict.self, from: try #require(r.structured)).summary == "ok")
        #expect(reply.text == r.text)
    }

    @Test func failedRunReportsItsError() {
        let line = #"{"event":"result","result":{"conversation_id":"","status":"ERROR","response":"","error":"invalid model selection (--model \"x\")"}}"#
        guard case .result(let r) = Agent.parse(line).first else { Issue.record("no result"); return }
        #expect(r.isError && r.text.hasPrefix("invalid model selection") && r.sessionId == nil)
    }

    func settings(_ args: [String]) throws -> [String: [String]] {
        let i = try #require(args.firstIndex(of: "--settings"))
        let obj = try JSONSerialization.jsonObject(with: Data(args[i + 1].utf8)) as? [String: Any]
        return try #require(obj?["permissions"] as? [String: [String]])
    }

    @Test func reviewerCommandCarriesThePromptTheSessionAndItsRules() throws {
        let args = Agent.arguments(model: "agy:gemini-4-argon-medium", permissionMode: "auto", systemPrompt: "Rules.",
                                   resume: "433a23d5-3857-43f9-a2ba-80e3f5a3eda2", schema: Agent.verdictSchema, readOnly: true,
                                   disabledMCP: ["airtable", "a.b"], disabledSkills: ["ponytail"], prompt: "Review this.")
        #expect(args.first == "agy")
        #expect(args[try #require(args.firstIndex(of: "--model")) + 1] == "gemini-4-argon-medium")
        #expect(args[try #require(args.firstIndex(of: "--conversation")) + 1] == "433a23d5-3857-43f9-a2ba-80e3f5a3eda2")
        #expect(args.contains("--json-schema") && args.contains("auto") && !args.contains("--dangerously-skip-permissions"))
        #expect(args.last == "--print=Rules.\n\nReview this.")
        #expect(try settings(args) == ["deny": ["write_file(*)", "mcp(airtable/*)", "mcp(a.b/*)"]])
        #expect(Agent.stdin(model: "agy:gemini-4-argon-medium", prompt: "p") == "")
        #expect(Agent.stdin(model: "claude-opus-5-5", prompt: "p") == "p")
    }

    /// Bypass is made of allow rules, never the skip flag: the deny rules (read-only, MCP off) must keep holding.
    @Test func bypassAllowsEverythingButWhatIsDenied() throws {
        let dev = Agent.arguments(model: "agy:claude-opus-5-5-high", permissionMode: "bypassPermissions", systemPrompt: "s",
                                  resume: nil, schema: nil, readOnly: false, disabledMCP: ["airtable"], disabledSkills: [], prompt: "p")
        #expect(!dev.contains("--dangerously-skip-permissions") && !dev.contains("--mode"))
        #expect(try settings(dev) == ["allow": ["command(*)", "read_file(*)", "mcp(*)", "write_file(*)"], "deny": ["mcp(airtable/*)"]])
        let reviewer = Agent.arguments(model: "agy:claude-opus-5-5-high", permissionMode: "bypassPermissions", systemPrompt: "s",
                                       resume: nil, schema: nil, readOnly: true, disabledMCP: [], disabledSkills: [], prompt: "p")
        #expect(!reviewer.contains("--dangerously-skip-permissions"))
        #expect(try settings(reviewer) == ["allow": ["command(*)", "read_file(*)", "mcp(*)"], "deny": ["write_file(*)"]])
        let editor = Agent.arguments(model: "agy:x", permissionMode: "acceptEdits", systemPrompt: "s", resume: nil, schema: nil,
                                     readOnly: false, disabledMCP: [], disabledSkills: [], prompt: "p")
        #expect(editor.contains("accept-edits") && !editor.contains("--settings"))
    }

    /// A refused tool leaves a SUCCESS result with no output (the e2e dev ended "done" without writing its file).
    @Test func headlessRefusalFailsTheStep() {
        let stderr = """
        warning: --mode auto is not available for this account; continuing in the default mode.
        jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied.
        """
        let message = Agent.antigravityRefusal(model: "agy:gemini-3.8-flash-low", stderr: stderr)
        #expect(message?.contains("no auto mode") == true && message?.contains("Bypass") == true)
        #expect(Agent.antigravityRefusal(model: "claude-opus-5-5", stderr: stderr) == nil)
        #expect(Agent.antigravityRefusal(model: "agy:x", stderr: "warning: --mode auto is not available for this account") == nil)
    }

    @Test func eachCLIGetsItsOwnPermissionMode() {
        var s = Settings()
        s.antigravityPermissionMode = "bypassPermissions"
        #expect(s.permissionMode(for: "agy:gemini-4-argon-high") == "bypassPermissions")
        #expect(s.permissionMode(for: "claude-opus-5-5") == "auto")
        #expect(Settings().antigravityPermissionMode == "auto")
    }

    @Test func modelPrefixRoundTrips() {
        #expect(AgentProvider.detect(from: "agy:claude-opus-5-5-high") == .antigravity)
        #expect(AgentProvider.detect(from: "claude-opus-5-5") == .claude && AgentProvider.detect(from: "gemini-2.5-pro") == .gemini)
        #expect(AgentProvider.cliModel("agy:gemini-4-argon-medium") == "gemini-4-argon-medium")
        #expect(AgentProvider.antigravity.storedModel("gemini-3.8-flash-low") == "agy:gemini-3.8-flash-low")
        #expect(AgentProvider.antigravity.storedModel("agy:x") == "agy:x")
        #expect(AgentProvider.claude.storedModel("claude-opus-5-5") == "claude-opus-5-5")
        #expect(Agent.isValidIdentifier("agy:gemini-4-argon-medium"))
    }

    @Test func geminiCLIKeepsOnlyTheServersLeftOn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("loopsmith-gemini-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"mcpServers":{"loopsmith-test-a":{},"loopsmith-test-b":{}}}"#.utf8)
            .write(to: dir.appendingPathComponent(".gemini/settings.json"))
        func allowed(_ disabled: [String]) -> [String]? {
            let args = Agent.arguments(model: "gemini-2.5-pro", permissionMode: "auto", systemPrompt: "s", resume: nil, schema: nil,
                                       readOnly: false, disabledMCP: disabled, disabledSkills: [], cwd: dir.path)
            guard let i = args.firstIndex(of: "--allowed-mcp-server-names") else { return nil }
            return Array(args[(i + 1)...].prefix { !$0.hasPrefix("--") })
        }
        #expect(allowed([]) == nil)
        let kept = try #require(allowed(["loopsmith-test-a"]))
        #expect(kept.contains("loopsmith-test-b") && !kept.contains("loopsmith-test-a"))
    }
}
