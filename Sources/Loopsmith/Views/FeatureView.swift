import AppKit
import SwiftUI

struct FeatureView: View {
    @Environment(AppStore.self) private var store
    let id: UUID
    @State private var showPullRequest = false
    @State private var showLogWork = false
    @State private var showTools = false
    @State private var confirmRemove = false
    @State private var actionError: String?

    var body: some View {
        if let f = store.feature(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(f)
                    PhaseStrip(feature: f)
                    if let message = f.error ?? actionError {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let url = f.prURL.flatMap(URL.init(string:)) {
                        Link(destination: url) { Label(url.absoluteString, systemImage: "arrow.triangle.pull") }
                    }
                    if !f.unresolved.isEmpty {
                        GroupBox("Open points (fix rounds used up)") { FindingsList(findings: f.unresolved) }
                    }
                    if let analysis = f.analysis { AnalysisView(analysis: analysis) }
                    ForEach(f.runs.reversed()) { RunView(run: $0) }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(f.title)
            .toolbar { toolbar(f) }
            .sheet(isPresented: $showPullRequest) { PullRequestSheet(feature: f) }
            .sheet(isPresented: $showLogWork) { LogWorkSheet(issueKey: f.jiraKey ?? "", comment: f.title, start: nil) {} }
            .sheet(isPresented: $showTools) {
                ToolsView(folder: f.worktreePath,
                          disabledMCP: Binding(get: { f.disabledMCP }, set: { v in store.update(id) { $0.disabledMCP = v }; store.save() }),
                          disabledSkills: Binding(get: { f.disabledSkills }, set: { v in store.update(id) { $0.disabledSkills = v }; store.save() }))
            }
            .confirmationDialog("Remove “\(f.title)”?", isPresented: $confirmRemove) {
                Button("Remove feature and worktree", role: .destructive) { remove(deleteWorktree: true) }
                Button("Remove from the list only") { remove(deleteWorktree: false) }
            } message: {
                Text("Git refuses to remove a worktree with uncommitted changes. The branch \(f.branch) is kept either way.")
            }
        } else {
            ContentUnavailableView("No feature", systemImage: "square.dashed")
        }
    }

    private func header(_ f: Feature) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let key = f.jiraKey, let url = store.jira.browseURL(key) {
                    Link(key, destination: url).font(.headline)
                }
                Text(f.branch).font(.callout.monospaced()).foregroundStyle(.secondary)
                Text("from \(f.baseBranch)").font(.callout).foregroundStyle(.secondary)
            }
            Text(f.prompt).textSelection(.enabled).foregroundStyle(.secondary).lineLimit(6)
            Text(f.worktreePath).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ f: Feature) -> some ToolbarContent {
        ToolbarItemGroup {
            if f.running {
                Button { store.stop(id) } label: { Label("Stop", systemImage: "stop.fill") }
            } else if f.phase != .ready && f.phase != .prOpened {
                Button { store.start(id) } label: { Label(f.runs.isEmpty ? "Start" : "Continue", systemImage: "play.fill") }
            }
            Button { showPullRequest = true } label: { Label("Create PR", systemImage: "arrow.triangle.pull") }
                .disabled(f.running || f.phase != .ready)
            Button { showLogWork = true } label: { Label("Log work", systemImage: "clock.badge.checkmark") }
                .disabled(!store.jira.isConfigured)
            Button { showTools = true } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .disabled(f.running)
                .help("MCP servers and skills the agents may use")
            Menu {
                Button("Open in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: f.worktreePath)) }
                Button("Open in VS Code") { open(f.worktreePath, with: "com.microsoft.VSCode") }
                Button("Open in Terminal") { open(f.worktreePath, with: "com.apple.Terminal") }
                Divider()
                Button("Remove…", role: .destructive) { confirmRemove = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private func open(_ path: String, with bundleID: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            actionError = "\(bundleID) is not installed."
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private func remove(deleteWorktree: Bool) {
        Task {
            do { try await store.remove(id, deleteWorktree: deleteWorktree) } catch { actionError = error.localizedDescription }
        }
    }
}

struct PhaseStrip: View {
    let feature: Feature

    var body: some View {
        let steps = [("Analysis", feature.analysis.map { $0.feasibility.capitalized } ?? ""),
                     ("Dev", ""),
                     ("Review", feature.reviewFixes > 0 ? "\(feature.reviewFixes) fix round(s)" : ""),
                     ("QA", feature.qaFixes > 0 ? "\(feature.qaFixes) fix round(s)" : ""),
                     ("PR", "")]
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { i in
                let done = i < feature.phase.step
                let current = i == feature.phase.step
                VStack(spacing: 4) {
                    Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.inset.filled" : "circle")
                        .font(.title2)
                        .foregroundStyle(done ? Color.green : current ? Color.accentColor : Color.secondary)
                    Text(steps[i].0).font(.callout.weight(current ? .semibold : .regular))
                    Text(current ? feature.phase.label : steps[i].1).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                if i < steps.count - 1 {
                    Rectangle().fill(done ? Color.green : Color.secondary.opacity(0.3)).frame(height: 2).frame(maxWidth: 60)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct RunView: View {
    let run: AgentRun
    @State private var expanded: Bool

    init(run: AgentRun) {
        self.run = run
        _expanded = State(initialValue: run.status == .running)
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if let error = run.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    if let summary = run.summary, run.role == .dev || run.findings != nil {
                        Text((try? AttributedString(markdown: summary, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(summary))
                            .textSelection(.enabled)
                    }
                    if let findings = run.findings {
                        if findings.isEmpty { Text("No finding.").foregroundStyle(.secondary) } else { FindingsList(findings: findings) }
                    }
                    ScrollView {
                        Text(run.log.suffix(400).joined(separator: "\n"))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 220)
                    .padding(6)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 6)
            } label: {
                HStack {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(title).font(.headline)
                    Text(run.model).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if run.status == .running { ProgressView().controlSize(.small) }
                    if let cost = run.cost { Text(String(format: "$%.2f", cost)).font(.caption).foregroundStyle(.secondary) }
                    Text(duration).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var title: String {
        switch run.role {
        case .analysis: "Analysis · \(run.lens)"
        case .dev: "Dev · \(run.lens)"
        case .review: "Review · \(run.lens)"
        case .qa: "QA · \(run.lens)"
        }
    }

    private var icon: String {
        switch run.status {
        case .running: "circle.dotted"
        case .done: (run.findings?.contains(where: \.isBlocking) ?? false) ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .stopped: "stop.circle.fill"
        }
    }

    private var color: Color {
        switch run.status {
        case .running: .accentColor
        case .done: (run.findings?.contains(where: \.isBlocking) ?? false) ? .orange : .green
        case .failed: .red
        case .stopped: .secondary
        }
    }

    private var duration: String {
        let seconds = Int((run.endedAt ?? Date()).timeIntervalSince(run.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AnalysisView: View {
    let analysis: Analysis
    @State private var expanded = true

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(analysis.summary).textSelection(.enabled)
                    section("Approach", [analysis.approach])
                    section("Files and modules", analysis.impacted)
                    section("Problems to handle", analysis.risks)
                    section("Assumptions", analysis.assumptions)
                    section("Acceptance criteria", analysis.acceptanceCriteria)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Analysis").font(.headline)
                    Text(analysis.feasibility.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(tint.opacity(0.2), in: Capsule())
                        .foregroundStyle(tint)
                }
            }
        }
    }

    private var tint: Color {
        switch analysis.feasibility {
        case "feasible": .green
        case "risky": .orange
        default: .red
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(items.count > 1 ? "• \(item)" : item).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}

struct FindingsList: View {
    let findings: [Finding]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(finding.severity.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(tint(finding).opacity(0.2), in: Capsule())
                            .foregroundStyle(tint(finding))
                        Text(finding.title).font(.callout.weight(.medium))
                        if !finding.location.isEmpty {
                            Text(finding.location).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Text(finding.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ finding: Finding) -> Color {
        switch finding.severity {
        case "blocker": .red
        case "major": .orange
        default: .secondary
        }
    }
}
