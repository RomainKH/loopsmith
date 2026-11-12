#if os(macOS)
import AppKit
import SwiftUI

/// Settings shared by the welcome steps and the Settings window: drop them inside a `Form`.

/// AI agent CLIs: which are installed, the model of each role, and how much they may do on their own.
struct AgentsSetupSections: View {
    @Environment(AppStore.self) private var store
    @State private var claudeStatus: (installed: Bool, detail: String)?
    @State private var geminiStatus: (installed: Bool, detail: String)?
    @State private var antigravityStatus: (installed: Bool, detail: String)?
    @State private var antigravityModels: [String] = []

    var body: some View {
        @Bindable var store = store
        Section("CLI Connectors") {
            ConnectorStatusRow(provider: .claude, status: claudeStatus)
            ConnectorStatusRow(provider: .antigravity, status: antigravityStatus)
            ConnectorStatusRow(provider: .gemini, status: geminiStatus)
            Text("Only the installation is checked: an agent run tells whether the CLI is logged in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        EndpointsSetupSection()

        Section("Quick Pipeline Presets") {
            HStack(spacing: 8) {
                Button {
                    store.settings.analysisModel = "claude-opus-5-5"
                    store.settings.devModel = "claude-opus-5-5"
                    store.settings.reviewModel = "claude-opus-5-5"
                    store.settings.qaModel = "claude-opus-5-5"
                } label: {
                    Label("All Claude", systemImage: AgentProvider.claude.icon)
                }

                Button {
                    store.settings.analysisModel = "agy:gemini-4-argon-high"
                    store.settings.devModel = "agy:gemini-4-argon-high"
                    store.settings.reviewModel = "agy:gemini-4-argon-medium"
                    store.settings.qaModel = "agy:gemini-3.8-flash-medium"
                } label: {
                    Label("All Antigravity", systemImage: AgentProvider.antigravity.icon)
                }

                Button {
                    store.settings.analysisModel = "agy:gemini-4-argon-high"
                    store.settings.devModel = "claude-opus-5-5"
                    store.settings.reviewModel = "agy:gemini-4-argon-high"
                    store.settings.qaModel = "claude-sonnet-5-5"
                } label: {
                    Label("Hybrid (Antigravity + Claude)", systemImage: "hammer.fill")
                }

                if let e = store.settings.endpoints.first(where: { !$0.models.isEmpty }), let m = e.models.first {
                    Button {
                        let model = "\(AgentProvider.customPrefix)\(e.name)/\(m)"
                        store.settings.analysisModel = model
                        store.settings.devModel = model
                        store.settings.reviewModel = model
                        store.settings.qaModel = model
                    } label: {
                        Label("All \(e.name)", systemImage: AgentProvider.custom.icon)
                    }
                    .help("Every role on \(e.name)/\(m)")
                }
            }
        }

        Section("Role Models") {
            RoleModelRow(role: .analysis, model: $store.settings.analysisModel, antigravityModels: antigravityModels,
                         endpoints: store.settings.endpoints)
            RoleModelRow(role: .dev, model: $store.settings.devModel, antigravityModels: antigravityModels,
                         endpoints: store.settings.endpoints)
            RoleModelRow(role: .review, model: $store.settings.reviewModel, antigravityModels: antigravityModels,
                         endpoints: store.settings.endpoints)
            RoleModelRow(role: .qa, model: $store.settings.qaModel, antigravityModels: antigravityModels,
                         endpoints: store.settings.endpoints)
        }

        Section("Execution & Approvals") {
            Toggle("Wait for my approval after each step", isOn: $store.settings.approveEachStep)
            Picker("Permission mode", selection: $store.settings.permissionMode) {
                Text("Auto").tag("auto")
                Text("Accept edits (no shell commands)").tag("acceptEdits")
                Text("Bypass permissions (no check)").tag("bypassPermissions")
            }
            Picker("Antigravity permissions", selection: $store.settings.antigravityPermissionMode) {
                Text("Auto").tag("auto")
                Text("Accept edits (no shell commands)").tag("acceptEdits")
                Text("Bypass (no check)").tag("bypassPermissions")
            }
            Text("Auto: Claude Code's classifier checks each action; Antigravity uses its own auto mode, which some accounts do not have: headless agy then refuses whatever your agy rules do not allow, and the step fails. Bypass lets Antigravity run every command, while still keeping the analysis, review and QA agents from writing files and the agents of a feature from the MCP servers switched off. Gemini CLI has no classifier: it runs every tool. Analysis, review and QA agents cannot use the file editing tools (a shell command still could).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            if let c = store.cliStatuses[.claude] { claudeStatus = c }
            if let g = store.cliStatuses[.gemini] { geminiStatus = g }
            if let a = store.cliStatuses[.antigravity] { antigravityStatus = a }
            if let m = store.cachedAntigravityModels { antigravityModels = m }

            if store.cliStatuses.isEmpty {
                async let claude = Agent.cliStatus(.claude)
                async let gemini = Agent.cliStatus(.gemini)
                async let antigravity = Agent.cliStatus(.antigravity)
                async let models = Agent.antigravityModels()
                let (c, g, a, m) = await (claude, gemini, antigravity, models)
                claudeStatus = c
                geminiStatus = g
                antigravityStatus = a
                antigravityModels = m
                store.cliStatuses[.claude] = c
                store.cliStatuses[.gemini] = g
                store.cliStatuses[.antigravity] = a
                store.cachedAntigravityModels = m
            }
        }
    }
}

/// APIs that speak Anthropic's Messages API, which Claude Code agents run on instead of Anthropic:
/// local servers (Ollama, LM Studio, llama.cpp, vLLM) and gateways (LiteLLM, OpenRouter, a company proxy).
struct EndpointsSetupSection: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var draftName = ""
    @State private var draftURL = ""
    @State private var draftKey = ""
    @State private var draftError: String?
    @State private var results: [UUID: (ok: Bool, message: String)] = [:]
    @State private var testing: Set<UUID> = []

    var body: some View {
        @Bindable var store = store
        Section {
            ForEach($store.settings.endpoints) { $e in
                HStack(spacing: 10) {
                    Image(systemName: AgentProvider.custom.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Brand.providerColor(.custom))
                        .frame(width: 24, height: 24)
                        .background(Brand.providerColor(.custom).opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.name).font(.callout.weight(.semibold))
                        Text(e.baseURL).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        if let r = results[e.id] {
                            Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.caption)
                                .foregroundStyle(r.ok ? Brand.emerald : Brand.crimson)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !e.models.isEmpty {
                            Text("\(e.models.count) model(s): \(e.models.prefix(3).joined(separator: ", "))\(e.models.count > 3 ? "…" : "")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Toggle("MCP", isOn: $e.loadMCPServers)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help("Give these agents your MCP servers. Off by default: their tool definitions can take more context than a local model has.")
                    if testing.contains(e.id) { ProgressView().controlSize(.small) }
                    Button("Test") { test(e) }
                        .disabled(testing.contains(e.id))
                    Button(role: .destructive) { remove(e) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove \(e.name) and its key")
                }
            }

            if adding {
                TextField("Name", text: $draftName, prompt: Text("ollama"))
                TextField("Base URL", text: $draftURL, prompt: Text("http://localhost:11434"))
                SecureField("API key", text: $draftKey, prompt: Text("empty for a local server"))
                if let draftError {
                    Text(draftError).font(.caption).foregroundStyle(Brand.crimson)
                }
                HStack {
                    Button("Save and test", action: saveDraft)
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { adding = false }
                }
            } else {
                Menu {
                    ForEach(ModelEndpoint.presets, id: \.name) { p in
                        Button("\(p.label) (\(p.url))") { startDraft(name: p.name, url: p.url) }
                            .disabled(store.settings.endpoint(named: p.name) != nil)
                    }
                    Divider()
                    Button("Another API…") { startDraft(name: "", url: "") }
                } label: {
                    Label("Add a custom API", systemImage: "plus")
                }
                .fixedSize()
            }

            Picker("Permissions on custom APIs", selection: $store.settings.customPermissionMode) {
                Text("Accept edits (no shell commands)").tag("acceptEdits")
                Text("Bypass (runs every command)").tag("bypassPermissions")
            }
            Text("Agents run on Claude Code pointed at the API, with its tools, MCP servers and skills: pick Custom API for a role, then a model. The API must speak Anthropic's Messages API (Ollama, LM Studio, llama.cpp, vLLM, LiteLLM, OpenRouter do; put LiteLLM in front of an OpenAI-only one). Your Anthropic login and API key are never sent to it. MCP servers are off unless you switch them on: their tools can fill a local model's context. Claude Code's auto mode needs a Claude model, so these agents either cannot run commands (accept edits: QA cannot run the tests) or run every command (bypass). The key stays in the keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Custom APIs & Local Models")
        }
    }

    private func startDraft(name: String, url: String) {
        draftName = name
        draftURL = url
        draftKey = ""
        draftError = nil
        adding = true
    }

    private func saveDraft() {
        let e = ModelEndpoint(name: draftName.trimmed.lowercased(),
                              baseURL: ModelEndpoint.normalizedBaseURL(draftURL) ?? draftURL.trimmed)
        if let problem = e.problem(among: store.settings.endpoints) {
            draftError = problem
            return
        }
        Keychain.set(draftKey.trimmed, for: e.keychainAccount)
        store.settings.endpoints.append(e)
        adding = false
        test(e)
    }

    private func remove(_ e: ModelEndpoint) {
        Keychain.set("", for: e.keychainAccount)
        store.settings.endpoints.removeAll { $0.id == e.id }
        results[e.id] = nil
    }

    private func test(_ e: ModelEndpoint) {
        testing.insert(e.id)
        results[e.id] = nil
        Task {
            do {
                let models = try await Agent.endpointModels(e, key: Keychain.get(e.keychainAccount))
                if let i = store.settings.endpoints.firstIndex(where: { $0.id == e.id }) {
                    store.settings.endpoints[i].models = models
                }
                results[e.id] = (true, models.isEmpty ? "Reachable, but it lists no model"
                    : "Reachable · \(models.count) model(s): \(models.prefix(3).joined(separator: ", "))\(models.count > 3 ? "…" : "")")
            } catch {
                results[e.id] = (false, error.localizedDescription)
            }
            testing.remove(e.id)
        }
    }
}

/// Jira Cloud connection, tested as soon as a token is saved.
struct JiraSetupSection: View {
    @Environment(AppStore.self) private var store
    @State private var token = ""
    @State private var check: (ok: Bool, message: String)?
    @State private var testing = false

    var body: some View {
        @Bindable var store = store
        Section("Jira Cloud") {
            TextField("Site", text: $store.settings.jiraSite, prompt: Text("yourteam.atlassian.net"))
            TextField("Email", text: $store.settings.jiraEmail)
            SecureField("API token", text: $token)
            Link("Create an API token", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
            TextField("My issues (JQL)", text: $store.settings.issueJQL, axis: .vertical).lineLimit(1...3)
            HStack {
                Button("Save and test") { test(saving: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(testing)
                if testing {
                    ProgressView().controlSize(.small)
                    Text("Testing…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let check {
                Label(check.message, systemImage: check.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(check.ok ? Brand.emerald : Brand.crimson)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            token = store.jiraToken
            // Tells at once whether the saved connection works, or what it is missing.
            if !store.jiraToken.isEmpty { test(saving: false) }
        }
    }

    private func test(saving: Bool) {
        if saving {
            store.jiraToken = token
            Keychain.set(token, for: "jira")
        }
        if let missing = store.jira.missingSetting {
            check = (false, missing)
            return
        }
        testing = true
        check = nil
        Task {
            do {
                let me = try await store.jira.myself()
                check = (true, "Connected as \(me.name)")
                await store.refreshIssues()
            } catch {
                check = (false, error.localizedDescription)
            }
            testing = false
        }
    }
}

/// The GitHub CLI, which lists and opens the pull requests.
struct GitHubSetupSection: View {
    @State private var status = "…"

    var body: some View {
        Section("GitHub CLI (`gh`)") {
            Text(status).font(.caption.monospaced()).textSelection(.enabled)
            Text("Pull requests are listed and opened with the GitHub CLI. Log in with `gh auth login` in a terminal.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { status = await GitHub.authStatus() }
    }
}

private struct ConnectorStatusRow: View {
    let provider: AgentProvider
    let status: (installed: Bool, detail: String)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: provider.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.providerColor(provider))
                .frame(width: 24, height: 24)
                .background(Brand.providerColor(provider).opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.label).font(.callout.weight(.semibold))
                Text(status?.detail ?? "Checking `\(provider.binary)`…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let status {
                PhaseBadge(
                    text: status.installed ? "INSTALLED" : "MISSING",
                    tint: status.installed ? Brand.emerald : .secondary,
                    icon: status.installed ? "checkmark.circle.fill" : "minus.circle"
                )
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct RoleModelRow: View {
    let role: Role
    @Binding var model: String
    let antigravityModels: [String]
    let endpoints: [ModelEndpoint]

    /// Picking "Custom API" starts from the first model of the first endpoint.
    private func firstModel(of provider: AgentProvider) -> String {
        guard provider == .custom, let e = endpoints.first else { return provider.defaultModel }
        return "\(AgentProvider.customPrefix)\(e.name)/\(e.models.first ?? "model")"
    }

    private var currentProvider: AgentProvider { AgentProvider.detect(from: model) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { currentProvider },
                    set: { newProvider in
                        if newProvider != currentProvider {
                            model = firstModel(of: newProvider)
                        }
                    }
                )) {
                    ForEach(AgentProvider.allCases) { p in
                        Label(p.shortLabel, systemImage: p.icon).tag(p)
                    }
                }
                .labelsHidden()
                .frame(width: 105)

                // The field shows the CLI's own model name; Antigravity's prefix is added back on input.
                TextField("Model ID", text: Binding(get: { AgentProvider.cliModel(model) },
                                                    set: { model = currentProvider.storedModel($0) }))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .font(.callout.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 165)

                Menu {
                    Section("Claude Code") {
                        ForEach(AgentProvider.claude.presetModels, id: \.self) { m in
                            Button(m) { model = m }
                        }
                    }
                    Section("Antigravity CLI") {
                        ForEach(antigravityModels.isEmpty ? AgentProvider.antigravity.presetModels : antigravityModels, id: \.self) { m in
                            Button(AgentProvider.cliModel(m)) { model = m }
                        }
                    }
                    Section("Gemini CLI") {
                        ForEach(AgentProvider.gemini.presetModels, id: \.self) { m in
                            Button(m) { model = m }
                        }
                    }
                    ForEach(endpoints) { e in
                        Section("Custom API · \(e.name)") {
                            ForEach(e.models, id: \.self) { m in
                                Button(m) { model = "\(AgentProvider.customPrefix)\(e.name)/\(m)" }
                            }
                            if e.models.isEmpty { Text("Test the endpoint to list its models") }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Choose a preset model")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: role.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(role.title)
            }
        }
    }
}

#endif
