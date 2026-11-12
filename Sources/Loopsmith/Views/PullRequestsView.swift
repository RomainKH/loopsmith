import SwiftUI

/// The user's open pull requests on GitHub, every repository.
struct PullRequestsView: View {
    @Environment(\.openURL) private var openURL
    @State private var pullRequests: [PullRequest] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List(pullRequests) { pr in
            HStack {
                Text(pr.repository.nameWithOwner).foregroundStyle(.secondary).frame(width: 220, alignment: .leading)
                Text("#" + String(pr.number)).monospacedDigit().foregroundStyle(.secondary)
                Text(pr.title).lineLimit(1)
                Spacer()
                if pr.isDraft { Text("Draft").font(.caption).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
            .onTapGesture { if let url = GitHub.safeHTTPSURL(pr.url) { openURL(url) } }
            .help(pr.url)
        }
        .overlay {
            if loading && pullRequests.isEmpty {
                ProgressView()
            } else if let error {
                ContentUnavailableView("GitHub unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if pullRequests.isEmpty {
                ContentUnavailableView("No open pull request", systemImage: "arrow.triangle.pull")
            }
        }
        .navigationTitle("Pull requests")
        .toolbar { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do { pullRequests = try await GitHub.myOpenPullRequests() } catch { self.error = error.localizedDescription }
        loading = false
    }
}
