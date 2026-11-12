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
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Brand.emerald.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Brand.emerald)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Pull Request")
                        .font(.headline)
                    HStack(spacing: 6) {
                        ForgeCodeChip(text: feature.branch, icon: "arrow.triangle.branch", tint: Brand.amber)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                        ForgeCodeChip(text: feature.baseBranch, tint: Brand.emerald)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.background.secondary)

            Divider()

            Form {
                TextField("Title", text: $title)
                Toggle("Create as Draft PR", isOn: $draft)
                Section("Description (Markdown)") {
                    TextEditor(text: $description)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 260)
                }
                if !feature.unresolved.isEmpty {
                    Label("\(feature.unresolved.count) open point(s) left by the pipeline are listed in the description.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.amber)
                }
                if let error {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Brand.crimson)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 660, height: 610)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "Pushing…" : "Commit, push and open PR", action: submit)
                    .buttonStyle(.borderedProminent)
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
