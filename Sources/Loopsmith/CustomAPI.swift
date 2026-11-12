import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension Agent {
    /// Variables of a Claude Code run against a custom API (https://code.claude.com/docs/en/llm-gateway-connect).
    /// The endpoint's key, or a placeholder for local servers, goes in ANTHROPIC_AUTH_TOKEN: it outranks the
    /// claude.ai login and ANTHROPIC_API_KEY, so the user's Anthropic credentials are never sent to that API.
    /// Every model alias Claude Code uses on its own (background requests, subagents) points at the endpoint's model.
    static func environment(model: String, endpoint: ModelEndpoint, key: String) throws -> [String: String] {
        guard let name = AgentProvider.endpointModel(model)?.model, isValidIdentifier(model) else {
            throw AppError("Invalid custom API model: \(model). Write it api:<endpoint>/<model>.")
        }
        guard let base = ModelEndpoint.normalizedBaseURL(endpoint.baseURL) else {
            throw AppError("Invalid base URL for \(endpoint.name): \(endpoint.baseURL)")
        }
        var env = [
            "ANTHROPIC_BASE_URL": base,
            "ANTHROPIC_AUTH_TOKEN": key.trimmed.nonEmpty ?? "loopsmith",
            "ANTHROPIC_MODEL": name,
            "ANTHROPIC_DEFAULT_OPUS_MODEL": name,
            "ANTHROPIC_DEFAULT_SONNET_MODEL": name,
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": name,
            "CLAUDE_CODE_SUBAGENT_MODEL": name,
            "CLAUDE_CODE_SUBAGENT_MODEL_FORCE": "1",
            "CLAUDE_CODE_AUTO_MODE_MODEL": name,
            // No session title request, no pre-release request fields a compatible API may reject, no telemetry.
            "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
            "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        ]
        // An empty value removes the variable from the agent's environment.
        for inherited in ["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_SMALL_FAST_MODEL",
                          "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] {
            env[inherited] = ""
        }
        return env
    }

    /// `GET <base>/v1/models`, which Anthropic, Ollama, LM Studio, LiteLLM and OpenRouter all answer: proves the API is
    /// reachable with this key and lists its models for the menus.
    static func endpointModels(_ endpoint: ModelEndpoint, key: String) async throws -> [String] {
        guard let base = ModelEndpoint.normalizedBaseURL(endpoint.baseURL), let url = URL(string: base + "/v1/models") else {
            throw AppError("Invalid base URL: \(endpoint.baseURL)")
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let key = key.trimmed.nonEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AppError("Could not reach \(base): \(error.localizedDescription) Is the server running?")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(decoding: data.prefix(300), as: UTF8.self).trimmed
            throw AppError("\(base)/v1/models answered HTTP \(status)\(body.isEmpty ? "" : ": \(body)")")
        }
        return try parseModelList(data)
    }

    /// `{"data": [{"id": "qwen3-coder"}, …]}` (OpenAI and Anthropic shape) → the ids that can go in a model string.
    static func parseModelList(_ data: Data) throws -> [String] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = obj["data"] as? [[String: Any]] else {
            throw AppError("The API answered, but not with a model list: is it the base URL of an Anthropic-compatible API?")
        }
        let ids = items.compactMap { $0["id"] as? String }.filter { isValidIdentifier($0) }
        return Array(Set(ids)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
