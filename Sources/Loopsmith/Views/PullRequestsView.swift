import SwiftUI

/// The user's pull requests on the project's repository, open first. A pull request opened from a feature
/// leads back to it.
struct PullRequestsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let project: Project
    let openFeature: (UUID) -> Void
    @State private var pullRequests: [PullRequest] = []
    @State private var loading = false
    @State private var error: String?

    private let groups = [("OPEN", "Open", Brand.emerald), ("MERGED", "Merged", Brand.indigo), ("CLOSED", "Closed", Color.secondary)]

    var body: some View {
        ZStack {
            ForgeCanvasBackground(accent: Brand.emerald)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForgeCard(padding: 18, cornerRadius: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Brand.emerald.opacity(0.16))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "arrow.triangle.pull")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Brand.emerald)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pull Requests")
                                    .font(.title2.weight(.bold))
                                Text("Your pull requests on \(project.name) via GitHub CLI (`gh`).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            PhaseBadge(text: "\(pullRequests.filter { $0.state == "OPEN" }.count) OPEN", tint: Brand.emerald)
                            Button {
                                Task { await load() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }

                    ForEach(groups, id: \.0) { state, title, groupTint in
                        let items = pullRequests.filter { $0.state == state }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    ForgeSectionHeader(title: title, icon: "circle.fill", tint: groupTint)
                                    PhaseBadge(text: "\(items.count)", tint: groupTint)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)

                                ForEach(items) { pr in
                                    row(pr)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 1020, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if loading && pullRequests.isEmpty {
                    ProgressView("Loading pull requests…")
                } else if let error {
                    ContentUnavailableView("GitHub unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if pullRequests.isEmpty {
                    ContentUnavailableView("No pull request yet", systemImage: "arrow.triangle.pull",
                                           description: Text("Your pull requests on this repository show here, the ones opened from a feature too."))
                }
            }
        }
        .navigationTitle("Pull requests")
        .toolbar { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        .task(id: project.id) { await load() }
    }

    private func row(_ pr: PullRequest) -> some View {
        let feature = store.features(of: project).first { $0.branch == pr.headRefName }
        return ForgeCard(padding: 14, cornerRadius: 11) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint(pr).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon(pr))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint(pr))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pr.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if pr.isDraft {
                            PhaseBadge(text: "DRAFT", tint: .secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForgeCodeChip(text: "#\(pr.number)", tint: tint(pr))
                        ForgeCodeChip(text: pr.headRefName, icon: "arrow.triangle.branch", tint: Brand.amber)
                        Text(pr.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let feature {
                    Button {
                        openFeature(feature.id)
                    } label: {
                        Label("Feature", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .help("Open the Loopsmith feature behind this pull request")
                }

                Button {
                    if let url = GitHub.safeHTTPSURL(pr.url) { openURL(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(pr.url)
            }
            .contentShape(Rectangle())
            .onTapGesture { if let url = GitHub.safeHTTPSURL(pr.url) { openURL(url) } }
        }
    }

    private func icon(_ pr: PullRequest) -> String {
        switch pr.state {
        case "MERGED": "arrow.triangle.merge"
        case "CLOSED": "xmark.circle"
        default: pr.isDraft ? "circle.dashed" : "arrow.triangle.pull"
        }
    }

    private func tint(_ pr: PullRequest) -> Color {
        switch pr.state {
        case "MERGED": Brand.indigo
        case "CLOSED": .secondary
        default: Brand.emerald
        }
    }

    private func load() async {
        loading = true
        error = nil
        do { pullRequests = try await GitHub.myPullRequests(repo: project.path) } catch { self.error = error.localizedDescription }
        loading = false
    }
}
