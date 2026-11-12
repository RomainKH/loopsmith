import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var token = ""
    @State private var jiraCheck: String?
    @State private var ghStatus = "…"
    @State private var claudeStatus: (installed: Bool, detail: String)?
    @State private var geminiStatus: (installed: Bool, detail: String)?
    @State private var antigravityStatus: (installed: Bool, detail: String)?
    @State private var antigravityModels: [String] = []

    var body: some View {
        @Bindable var store = store
        TabView {
            Form {
                Section {
                    HStack(spacing: 12) {
                        LoopsmithLogoMark(size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loopsmith: Forge & Precision")
                                .font(.headline)
                            Text(Brand.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Workspace & Worktrees") {
                    LabeledContent("Worktrees folder") {
                        HStack {
                            Text(store.settings.worktreesRoot)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url { store.settings.worktreesRoot = url.path }
                            }
                        }
                    }
                    TextField("Copy into new worktrees", text: $store.settings.copyFiles, prompt: Text(".env, .env.local"))
                }

                Section("Pipeline & Worklog") {
                    Stepper("Fix rounds after review and after QA: \(store.settings.maxFixRounds)",
                            value: $store.settings.maxFixRounds, in: 0...5)
                    Stepper("Daily target: \(store.settings.dailyHours.formatted())h",
                            value: $store.settings.dailyHours, in: 1...12, step: 0.5)
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
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
            }
            .tabItem { Label("Agents & AI", systemImage: "cpu") }

            Form {
                Section("Jira Cloud") {
                    TextField("Site", text: $store.settings.jiraSite, prompt: Text("yourteam.atlassian.net"))
                    TextField("Email", text: $store.settings.jiraEmail)
                    SecureField("API token", text: $token)
                    Link("Create an API token", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                        .font(.caption)
                    TextField("My issues (JQL)", text: $store.settings.issueJQL, axis: .vertical).lineLimit(1...3)
                    HStack {
                        Button("Save and test") {
                            store.jiraToken = token
                            Keychain.set(token, for: "jira")
                            Task {
                                do { jiraCheck = "Connected as \(try await store.jira.myself().name)" } catch { jiraCheck = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        if let jiraCheck { Text(jiraCheck).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
            .tabItem { Label("Jira", systemImage: "checklist") }

            Form {
                Section("GitHub CLI (`gh`)") {
                    Text(ghStatus).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Pull requests are opened with the GitHub CLI. Log in with `gh auth login` in a terminal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 540)
        .onAppear { token = store.jiraToken }
        .task {
            async let gh = GitHub.authStatus()
            async let claude = Agent.cliStatus(.claude)
            async let gemini = Agent.cliStatus(.gemini)
            async let antigravity = Agent.cliStatus(.antigravity)
            async let models = Agent.antigravityModels()
            ghStatus = await gh
            claudeStatus = await claude
            geminiStatus = await gemini
            antigravityStatus = await antigravity
            antigravityModels = await models
        }
        .onChange(of: store.settings) { store.saveSettings() }
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
