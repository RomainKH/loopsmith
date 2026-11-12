import SwiftUI

/// Last step: commit the worktree, push the branch and open the pull request with `gh`.
struct PullRequestSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let feature: Feature
    @State private var title = ""
    @State private var description = ""
    @State private var draft = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            LabeledContent("Branch", value: "\(feature.branch) → \(feature.baseBranch)")
            TextField("Title", text: $title)
            Toggle("Draft", isOn: $draft)
            Section("Description") {
                TextEditor(text: $description).font(.body.monospaced()).frame(minHeight: 260)
            }
            if !feature.unresolved.isEmpty {
                Text("\(feature.unresolved.count) open point(s) left by the pipeline are listed in the description.")
                    .foregroundStyle(.orange)
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 580)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "Pushing…" : "Commit, push and open PR", action: submit)
                    .disabled(busy || title.trimmed.isEmpty)
            }
        }
        .onAppear {
            title = [feature.jiraKey, feature.title].compactMap { $0 }.joined(separator: " ")
            description = store.pullRequestBody(feature)
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                try await store.openPullRequest(feature.id, title: title.trimmed, body: description, draft: draft)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}
