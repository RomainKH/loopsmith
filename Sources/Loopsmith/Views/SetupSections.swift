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
            }
        }

        Section("Role Models") {
            RoleModelRow(role: .analysis, model: $store.settings.analysisModel, antigravityModels: antigravityModels)
            RoleModelRow(role: .dev, model: $store.settings.devModel, antigravityModels: antigravityModels)
            RoleModelRow(role: .review, model: $store.settings.reviewModel, antigravityModels: antigravityModels)
            RoleModelRow(role: .qa, model: $store.settings.qaModel, antigravityModels: antigravityModels)
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
            async let claude = Agent.cliStatus(.claude)
            async let gemini = Agent.cliStatus(.gemini)
            async let antigravity = Agent.cliStatus(.antigravity)
            async let models = Agent.antigravityModels()
            claudeStatus = await claude
            geminiStatus = await gemini
            antigravityStatus = await antigravity
            antigravityModels = await models
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

    private var currentProvider: AgentProvider { AgentProvider.detect(from: model) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Picker("", selection: Binding(
                    get: { currentProvider },
                    set: { newProvider in
                        if newProvider != currentProvider {
                            model = newProvider.defaultModel
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
