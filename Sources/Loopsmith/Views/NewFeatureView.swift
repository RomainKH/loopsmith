#if os(macOS)
import SwiftUI

/// Starts a feature in the open project: its own worktree and branch, then the pipeline.
struct NewFeatureView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let onCreated: (UUID) -> Void

    @State private var base = ""
    @State private var issueKey: String?
    @State private var title = ""
    @State private var prompt = ""
    @State private var disabledMCP: [String] = []
    @State private var disabledSkills: [String] = []
    @State private var showTools = false
    @State private var busy = false
    @State private var error: String?

    private var issues: [JiraIssue] { store.issues.filter { project.owns(issueKey: $0.key) } }
    private var issue: JiraIssue? { issues.first { $0.key == issueKey } }
    private var branch: String { "feat/" + Git.slug([issueKey, title].compactMap { $0 }.joined(separator: " ")) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LoopsmithLogoMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Feature in \(project.name)")
                        .font(.headline)
                    HStack(spacing: 6) {
                        ForgeCodeChip(text: branch, icon: "arrow.triangle.branch", tint: Brand.amber)
                        Image(systemName: "arrow.left")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        ForgeCodeChip(text: base.isEmpty ? project.baseBranch : base, tint: .secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.background.secondary)

            Divider()

            Form {
                Section("Worktree & Branch") {
                    LabeledContent("Project", value: project.name)
                    TextField("Base branch", text: $base)
                        .font(.callout.monospaced())
                    LabeledContent("New branch") {
                        ForgeCodeChip(text: branch, icon: "arrow.triangle.branch", tint: Brand.amber)
                    }
                    if project.scanning || project.brief == nil {
                        Label(
                            project.scanning ? "The project brief is being written: agents that start before it is done work without it."
                                             : "This project has no brief: agents start without one. Write it from Overview.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Jira Ticket") {
                    Picker("Jira issue", selection: $issueKey) {
                        Text("None").tag(String?.none)
                        ForEach(issues) { Text("\($0.key) · \($0.summary)").tag(Optional($0.key)) }
                    }
                    .disabled(!store.jira.isConfigured)
                    if !store.jira.isConfigured {
                        Text("Connect Jira in Settings to start from a ticket.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Feature Specification") {
                    TextField("Title", text: $title)
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 150)
                        .overlay(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("What should be built? The Jira ticket, when picked, is added to this prompt. An analysis agent reads it against the code before development starts.")
                                    .foregroundStyle(.tertiary).padding(.top, 1).padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                    LabeledContent("Tools & Skills") {
                        Button("\(disabledMCP.count) MCP server(s), \(disabledSkills.count) skill(s) off…") { showTools = true }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.crimson)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 620, height: 660)
        .navigationTitle("New feature in \(project.name)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "Creating worktree…" : "Create and start", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || base.trimmed.isEmpty || title.trimmed.isEmpty || (prompt.trimmed.isEmpty && issue == nil))
            }
        }
        .sheet(isPresented: $showTools) {
            ToolsView(folder: project.path, disabledMCP: $disabledMCP, disabledSkills: $disabledSkills)
        }
        .task {
            base = project.baseBranch
            disabledMCP = project.disabledMCP
            disabledSkills = project.disabledSkills
            await store.refreshIssues()
        }
        .onChange(of: issueKey) {
            if let issue, title.trimmed.isEmpty { title = issue.summary }
        }
    }

    private func create() {
        busy = true
        error = nil
        Task {
            do {
                let id = try await store.createFeature(title: title.trimmed, prompt: prompt.trimmed, repo: project.path, base: base.trimmed,
                                                       issue: issue, disabledMCP: disabledMCP, disabledSkills: disabledSkills)
                store.start(id)
                onCreated(id)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}

#endif
