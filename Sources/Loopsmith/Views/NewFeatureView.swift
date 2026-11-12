import SwiftUI

struct NewFeatureView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onCreated: (UUID) -> Void

    @State private var projectID: UUID?
    @State private var base = ""
    @State private var issueKey: String?
    @State private var title = ""
    @State private var prompt = ""
    @State private var disabledMCP: [String] = []
    @State private var disabledSkills: [String] = []
    @State private var showTools = false
    @State private var busy = false
    @State private var error: String?

    private var project: Project? { projectID.flatMap(store.project) }
    private var issue: JiraIssue? { store.issues.first { $0.key == issueKey } }
    private var branch: String { "feat/" + Git.slug([issueKey, title].compactMap { $0 }.joined(separator: " ")) }

    var body: some View {
        Form {
            Section("Project") {
                HStack {
                    Picker("Project", selection: $projectID) {
                        ForEach(store.projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Add project…") {
                        Task {
                            do { if let id = try await store.chooseAndAddProject() { projectID = id } } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                TextField("Base branch", text: $base)
                LabeledContent("Branch", value: branch)
                if let project, project.scanning || project.brief == nil {
                    Text(project.scanning ? "The project brief is being written: agents that start before it is done work without it."
                                          : "This project has no brief: agents start without one. Write it from the project page.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Ticket") {
                Picker("Jira issue", selection: $issueKey) {
                    Text("None").tag(String?.none)
                    ForEach(store.issues) { Text("\($0.key) · \($0.summary)").tag(Optional($0.key)) }
                }
                .disabled(!store.jira.isConfigured)
            }
            Section("Feature") {
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
                LabeledContent("Tools") {
                    Button("\(disabledMCP.count) MCP server(s), \(disabledSkills.count) skill(s) off…") { showTools = true }
                        .disabled(project == nil)
                }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 660)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "Creating worktree…" : "Create and start", action: create)
                    .disabled(busy || project == nil || base.trimmed.isEmpty || title.trimmed.isEmpty || (prompt.trimmed.isEmpty && issue == nil))
            }
        }
        .sheet(isPresented: $showTools) {
            if let project { ToolsView(folder: project.path, disabledMCP: $disabledMCP, disabledSkills: $disabledSkills) }
        }
        .task {
            projectID = store.projects.first?.id
            await store.refreshIssues()
        }
        .onChange(of: projectID) {
            guard let project else { return }
            base = project.baseBranch
            disabledMCP = project.disabledMCP
            disabledSkills = project.disabledSkills
        }
        .onChange(of: issueKey) {
            if let issue, title.trimmed.isEmpty { title = issue.summary }
        }
    }

    private func create() {
        guard let project else { return }
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
