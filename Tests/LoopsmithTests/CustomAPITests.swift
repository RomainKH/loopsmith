import Foundation
import Testing
@testable import Loopsmith

@Suite struct CustomAPITests {
    let ollama = ModelEndpoint(name: "ollama", baseURL: "http://localhost:11434")

    @Test func modelStringNamesTheEndpointAndItsModel() throws {
        #expect(AgentProvider.detect(from: "api:ollama/qwen3-coder:30b") == .custom)
        let parsed = try #require(AgentProvider.endpointModel("api:openrouter/moonshotai/kimi-k2"))
        #expect(parsed.endpoint == "openrouter" && parsed.model == "moonshotai/kimi-k2")
        #expect(AgentProvider.endpointModel("api:ollama") == nil)
        #expect(AgentProvider.endpointModel("claude-opus-5-5") == nil)
        #expect(AgentProvider.cliModel("api:ollama/qwen3-coder") == "ollama/qwen3-coder")
        #expect(AgentProvider.custom.storedModel("ollama/qwen3-coder") == "api:ollama/qwen3-coder")
        #expect(AgentProvider.custom.binary == "claude")
    }

    @Test func runsOnClaudeCodeWithTheBareModelAndAJSONInstruction() {
        let args = Agent.arguments(model: "api:ollama/qwen3-coder:30b", permissionMode: "auto", systemPrompt: "sys",
                                   resume: nil, schema: Agent.verdictSchema, readOnly: true,
                                   disabledMCP: [], disabledSkills: [])
        #expect(args.prefix(2) == ["claude", "-p"])
        #expect(args[args.firstIndex(of: "--model")! + 1] == "qwen3-coder:30b")
        // Auto mode needs a Claude model: a custom API gets acceptEdits instead of refusing every command.
        #expect(args[args.firstIndex(of: "--permission-mode")! + 1] == "acceptEdits")
        #expect(!args.contains("--json-schema"))
        #expect(args[args.firstIndex(of: "--append-system-prompt")! + 1].contains("Respond ONLY with a valid JSON object"))
        #expect(args.contains("Edit,Write,NotebookEdit"))
    }

    @Test func customAPIAgentsGetNoMCPServerUnlessTheEndpointSaysSo() throws {
        var settings = Settings()
        settings.endpoints = [ollama]
        #expect(settings.runsWithoutMCP(model: "api:ollama/x") && !settings.runsWithoutMCP(model: "claude-opus-5-5"))
        settings.endpoints[0].loadMCPServers = true
        #expect(!settings.runsWithoutMCP(model: "api:ollama/x"))
        let args = Agent.arguments(model: "api:ollama/x", permissionMode: "auto", systemPrompt: "s", resume: nil, schema: nil,
                                   readOnly: false, disabledMCP: [], disabledSkills: [], withoutMCP: true)
        #expect(args.contains("--strict-mcp-config"))
        let saved = #"{"name":"ollama","baseURL":"http://localhost:11434"}"#
        let decoded = try JSONDecoder().decode(ModelEndpoint.self, from: Data(saved.utf8))
        #expect(decoded.models.isEmpty && !decoded.loadMCPServers)
    }

    @Test func claudeModelsKeepTheStructuredOutputFlag() {
        let args = Agent.arguments(model: "claude-haiku-5-5", permissionMode: "auto", systemPrompt: "sys", resume: nil,
                                   schema: Agent.verdictSchema, readOnly: true, disabledMCP: [], disabledSkills: [])
        #expect(args.contains("--json-schema") && args.contains("auto"))
    }

    @Test func environmentPointsEveryModelAtTheEndpointAndDropsAnthropicCredentials() throws {
        let env = try Agent.environment(model: "api:ollama/qwen3-coder", endpoint: ollama, key: "")
        #expect(env["ANTHROPIC_BASE_URL"] == "http://localhost:11434")
        #expect(env["ANTHROPIC_AUTH_TOKEN"] == "loopsmith")
        for key in ["ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
                    "ANTHROPIC_DEFAULT_HAIKU_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL"] {
            #expect(env[key] == "qwen3-coder")
        }
        // Empty values are removed from the agent's environment by Shell.
        #expect(env["ANTHROPIC_API_KEY"] == "" && env["CLAUDE_CODE_OAUTH_TOKEN"] == "")
        let keyed = try Agent.environment(model: "api:ollama/qwen3-coder", endpoint: ollama, key: " sk-123 ")
        #expect(keyed["ANTHROPIC_AUTH_TOKEN"] == "sk-123")
    }

    @Test func aModelOfAnUnknownEndpointIsRefused() throws {
        var settings = Settings()
        settings.endpoints = [ollama]
        let key: (ModelEndpoint) -> String = { $0.name == "ollama" ? "k" : "" }
        #expect(throws: AppError.self) { try settings.agentEnvironment(model: "api:lmstudio/x", key: key) }
        #expect(throws: AppError.self) { try settings.agentEnvironment(model: "api:ollama", key: key) }
        #expect(try settings.agentEnvironment(model: "claude-opus-5-5", key: key).isEmpty)
        let env = try settings.agentEnvironment(model: "api:ollama/qwen3-coder", key: key)
        #expect(env["ANTHROPIC_MODEL"] == "qwen3-coder" && env["ANTHROPIC_AUTH_TOKEN"] == "k")
    }

    @Test func permissionsOfACustomAPINeverUseAutoMode() {
        var settings = Settings()
        #expect(settings.permissionMode(for: "api:ollama/x") == "acceptEdits")
        settings.customPermissionMode = "bypassPermissions"
        #expect(settings.permissionMode(for: "api:ollama/x") == "bypassPermissions")
        settings.customPermissionMode = "auto"
        #expect(settings.permissionMode(for: "api:ollama/x") == "acceptEdits")
        #expect(settings.permissionMode(for: "claude-opus-5-5") == "auto")
    }

    @Test func baseURLsAreValidatedAndNormalized() {
        #expect(ModelEndpoint.normalizedBaseURL("http://localhost:11434/") == "http://localhost:11434")
        #expect(ModelEndpoint.normalizedBaseURL("https://openrouter.ai/api/v1") == "https://openrouter.ai/api")
        #expect(ModelEndpoint.normalizedBaseURL("ftp://host") == nil)
        #expect(ModelEndpoint.normalizedBaseURL("http://user:pw@host") == nil)
        #expect(ModelEndpoint.normalizedBaseURL("localhost:11434") == nil)
        #expect(ModelEndpoint(name: "Ollama!", baseURL: "http://x").problem(among: []) != nil)
        #expect(ollama.problem(among: [ModelEndpoint(name: "ollama", baseURL: "http://y")]) != nil)
        #expect(ollama.problem(among: [ollama]) == nil)
    }

    @Test func modelListsOfEveryShapeAreRead() throws {
        let openAI = #"{"object":"list","data":[{"id":"qwen3-coder:30b","object":"model"},{"id":"gpt-oss:20b"}]}"#
        #expect(try Agent.parseModelList(Data(openAI.utf8)) == ["gpt-oss:20b", "qwen3-coder:30b"])
        let anthropic = #"{"data":[{"type":"model","id":"claude-opus-5-5"}],"has_more":false}"#
        #expect(try Agent.parseModelList(Data(anthropic.utf8)) == ["claude-opus-5-5"])
        #expect(throws: AppError.self) { try Agent.parseModelList(Data("<html>".utf8)) }
    }

    @Test func settingsWithoutEndpointsStillLoad() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"devModel":"claude-sonnet-5-5"}"#.utf8))
        #expect(settings.endpoints.isEmpty && settings.customPermissionMode == "acceptEdits")
        var withOne = Settings()
        withOne.endpoints = [ollama]
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(withOne))
        #expect(decoded.endpoints == [ollama])
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func agentGetsTheOverridesAndLosesTheRemovedVariables() async throws {
        var lines: [String] = []
        _ = try await Shell.stream(["sh", "-c", #"echo "${LOOPSMITH_T_SET}|${HOME:+home}|${LOOPSMITH_T_GONE:-gone}""#],
                                   cwd: "/", input: "",
                                   environment: ["LOOPSMITH_T_SET": "on", "HOME": "", "LOOPSMITH_T_GONE": ""],
                                   register: { _ in }) { lines.append($0) }
        #expect(lines == ["on||gone"])
    }
}

@Suite struct CLITests {
    @Test func onlyKnownCommandsLeaveTheApp() {
        #expect(CLI.handles(["run", "abc"]) && CLI.handles(["--help"]))
        #expect(!CLI.handles([]) && !CLI.handles(["-NSDocumentRevisionsDebugMode", "YES"]))
    }

    @Test func optionsAnywherePositionalsInOrder() throws {
        var args = Arguments(["Free shipping", "--repo", "/tmp/x", "--yes", "extra"])
        #expect(try args.option("--repo") == "/tmp/x")
        #expect(args.flag("--yes") && !args.flag("--no-run"))
        #expect(args.positional() == "Free shipping")
        #expect(throws: AppError.self) { try args.finish() }
        #expect(args.positional() == "extra")
        try args.finish()
        var missing = Arguments(["--prompt"])
        #expect(throws: AppError.self) { try missing.option("--prompt") }
    }
}
