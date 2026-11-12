import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var token = ""
    @State private var jiraCheck: String?
    @State private var ghStatus = "…"

    var body: some View {
        @Bindable var store = store
        TabView {
            Form {
                LabeledContent("Worktrees folder") {
                    HStack {
                        Text(store.settings.worktreesRoot).lineLimit(1).truncationMode(.middle)
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
                Stepper("Fix rounds after review and after QA: \(store.settings.maxFixRounds)",
                        value: $store.settings.maxFixRounds, in: 0...5)
                Stepper("Daily target: \(store.settings.dailyHours.formatted())h",
                        value: $store.settings.dailyHours, in: 1...12, step: 0.5)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                TextField("Analysis and brief model", text: $store.settings.analysisModel)
                TextField("Dev model", text: $store.settings.devModel)
                TextField("Review model", text: $store.settings.reviewModel)
                TextField("QA model", text: $store.settings.qaModel)
                Picker("Permission mode", selection: $store.settings.permissionMode) {
                    Text("Auto (Claude Code classifier)").tag("auto")
                    Text("Accept edits (other commands denied)").tag("acceptEdits")
                    Text("Bypass permissions (no check at all)").tag("bypassPermissions")
                }
                Text("Agents run `claude -p` in the worktree with your own Claude Code login, settings, MCP servers, skills and plugins. The analysis, review and QA agents cannot edit files. Each project sets the MCP servers and skills its new features start with.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("Agents", systemImage: "cpu") }

            Form {
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
                    if let jiraCheck { Text(jiraCheck).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            .tabItem { Label("Jira", systemImage: "checklist") }

            Form {
                Text(ghStatus).font(.caption.monospaced()).textSelection(.enabled)
                Text("Pull requests are opened with the GitHub CLI. Log in with `gh auth login` in a terminal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 420)
        .onAppear { token = store.jiraToken }
        .task { ghStatus = await GitHub.authStatus() }
        .onChange(of: store.settings) { store.saveSettings() }
    }
}
