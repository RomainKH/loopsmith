#if os(macOS)
import AppKit
import SwiftUI

struct FeatureView: View {
    @Environment(AppStore.self) private var store
    let id: UUID
    @State private var showPullRequest = false
    @State private var showLogWork = false
    @State private var showTools = false
    @State private var showDiff = false
    @State private var confirmRemove = false
    @State private var actionError: String?

    var body: some View {
        if let f = store.feature(id) {
            ZStack {
                ForgeCanvasBackground(accent: f.phase == .ready || f.phase == .prOpened ? Brand.emerald : Brand.amber)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(f)
                        PhaseStrip(feature: f)

                        if f.running {
                            ActiveAgentStageBanner(feature: f)
                        }

                        if let message = f.error ?? actionError {
                            ForgeCard(padding: 14, cornerRadius: 11, tint: Brand.crimson) {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Brand.crimson)
                                    Text(message)
                                        .font(.callout)
                                        .foregroundStyle(Brand.crimson)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if !f.running && (f.isAwaiting || f.phase == .ready) {
                            GatePanel(feature: f, showDiff: { showDiff = true }, createPullRequest: { showPullRequest = true })
                        }

                        if let url = f.prURL.flatMap(GitHub.safeHTTPSURL) {
                            ForgeCard(padding: 14, cornerRadius: 11, tint: Brand.emerald) {
                                HStack {
                                    Image(systemName: "arrow.triangle.pull")
                                        .foregroundStyle(Brand.emerald)
                                    Text("Pull Request opened:")
                                        .font(.callout.weight(.semibold))
                                    Link(url.absoluteString, destination: url)
                                        .font(.callout.monospaced())
                                    Spacer()
                                }
                            }
                        }

                        if !f.unresolved.isEmpty {
                            ForgeCard(padding: 16, cornerRadius: 12, tint: Brand.amber) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForgeSectionHeader(
                                        title: "Open points (fix rounds used up)",
                                        subtitle: "Listed automatically in the Pull Request description.",
                                        icon: "exclamationmark.bubble.fill",
                                        tint: Brand.amber
                                    )
                                    FindingsList(findings: f.unresolved)
                                }
                            }
                        }

                        if let analysis = f.analysis {
                            AnalysisView(analysis: analysis)
                        }

                        if !f.runs.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForgeSectionHeader(
                                    title: "Agent Runs (\(f.runs.count))",
                                    subtitle: "Execution logs, lens reviews, and QA verification.",
                                    icon: "terminal.fill",
                                    tint: Brand.indigo
                                )
                                .padding(.horizontal, 4)

                                ForEach(f.runs.reversed()) {
                                    RunView(run: $0)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1020, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(f.title)
            .toolbar { toolbar(f) }
            .sheet(isPresented: $showPullRequest) { PullRequestSheet(feature: f) }
            .sheet(isPresented: $showDiff) { DiffSheet(feature: f) }
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
        ForgeCard(padding: 18, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    if let key = f.jiraKey {
                        if let url = store.jira.browseURL(key) {
                            Link(destination: url) {
                                PhaseBadge(text: key, tint: Brand.amber, icon: "arrow.up.right.square")
                            }
                            .buttonStyle(.plain)
                        } else {
                            PhaseBadge(text: key, tint: Brand.amber, icon: "tag.fill")
                        }
                    }

                    Text(f.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))

                    Spacer()

                    PhaseBadge(
                        text: f.isAwaiting ? "AWAITING APPROVAL" : f.phase.label.uppercased(),
                        tint: f.error != nil ? Brand.crimson : f.isAwaiting ? Brand.amber : (f.phase == .ready || f.phase == .prOpened) ? Brand.emerald : Brand.indigo,
                        icon: f.running ? "bolt.fill" : f.isAwaiting ? "hand.raised.fill" : "circle.fill"
                    )
                }

                HStack(spacing: 8) {
                    ForgeCodeChip(text: f.branch, icon: "arrow.triangle.branch", tint: Brand.amber)
                    Image(systemName: "arrow.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    ForgeCodeChip(text: f.baseBranch, icon: "point.topleft.down.curvedto.point.bottomright.up", tint: .secondary)

                    Spacer()

                    Button { showDiff = true } label: {
                        Label("Diff", systemImage: "doc.text.magnifyingglass")
                            .font(.caption.weight(.medium))
                    }
                    .controlSize(.small)

                    Button { open(f.worktreePath, with: "com.microsoft.VSCode") } label: {
                        Label("VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.caption.weight(.medium))
                    }
                    .controlSize(.small)

                    Button { open(f.worktreePath, with: "com.apple.Terminal") } label: {
                        Label("Terminal", systemImage: "terminal")
                            .font(.caption.weight(.medium))
                    }
                    .controlSize(.small)
                }

                if !f.prompt.trimmed.isEmpty {
                    Text(f.prompt)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.86))
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.quaternary.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
                        )
                }

                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(f.worktreePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ f: Feature) -> some ToolbarContent {
        ToolbarItemGroup {
            if f.running {
                Button { store.stop(id) } label: { Label("Stop", systemImage: "stop.fill") }
            } else if f.phase != .ready && f.phase != .prOpened && !f.isAwaiting {
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
                Button("Show diff") { showDiff = true }
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
        let steps: [(title: String, role: Role?, icon: String, sub: String)] = [
            ("Analysis · Nova", .analysis, "magnifyingglass", feature.analysis.map { $0.feasibility.capitalized } ?? "Spec & risks"),
            ("Dev · Atlas", .dev, "hammer.fill", "Implementation"),
            ("Review · Orion", .review, "eye.fill", feature.reviewFixes > 0 ? "\(feature.reviewFixes) fix round(s)" : "2 lenses"),
            ("QA · Aegis", .qa, "checkmark.shield.fill", feature.qaFixes > 0 ? "\(feature.qaFixes) fix round(s)" : "Build & tests"),
            ("Pull Request", nil, "arrow.triangle.pull", feature.phase == .prOpened ? "Opened" : "Ship")
        ]

        ForgeCard(padding: 16, cornerRadius: 13) {
            HStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { i in
                    let done = i < feature.phase.step
                    let current = i == feature.phase.step
                    let stepTint: Color = done ? Brand.emerald : current ? (steps[i].role.map(Brand.roleColor) ?? Brand.cobalt) : .secondary

                    VStack(spacing: 6) {
                        if let role = steps[i].role {
                            ZStack(alignment: .bottomTrailing) {
                                AgentCharacterAvatar(role: role, isWorking: false, size: 44)
                                    .opacity(done || current ? 1.0 : 0.55)
                                if done {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Brand.emerald)
                                        .background(Circle().fill(Brand.obsidian))
                                }
                            }
                        } else {
                            ZStack {
                                Circle()
                                    .fill(done ? Brand.emerald.opacity(0.18) : current ? Brand.cobalt.opacity(0.20) : Color.secondary.opacity(0.10))
                                    .frame(width: 44, height: 44)
                                Image(systemName: done ? "checkmark" : steps[i].icon)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(stepTint)
                            }
                        }

                        Text(steps[i].title)
                            .font(.system(size: 12, weight: current ? .bold : .semibold))
                            .foregroundStyle(current || done ? .primary : .secondary)

                        Text(current ? feature.phase.label : steps[i].sub)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(current ? stepTint : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    if i < steps.count - 1 {
                        Capsule()
                            .fill(done ? Brand.emerald.opacity(0.65) : Color.primary.opacity(0.10))
                            .frame(height: 2.5)
                            .frame(maxWidth: 56)
                            .padding(.bottom, 24)
                    }
                }
            }
        }
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
        ForgeCard(padding: 14, cornerRadius: 12, tint: run.status == .running ? Brand.indigo : nil) {
            DisclosureGroup(isExpanded: $expanded) {
                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().opacity(0.5)

                        if let error = run.error {
                            Label(error, systemImage: "xmark.octagon.fill")
                                .foregroundStyle(Brand.crimson)
                                .textSelection(.enabled)
                        }
                        if let summary = run.summary, run.role == .dev || run.findings != nil {
                            Text((try? AttributedString(markdown: summary, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(summary))
                                .font(.callout)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if let findings = run.findings {
                            if findings.isEmpty {
                                Label("No blocking or major finding reported.", systemImage: "checkmark.seal.fill")
                                    .font(.callout)
                                    .foregroundStyle(Brand.emerald)
                            } else {
                                FindingsList(findings: findings)
                            }
                        }

                        ForgeTerminalBox(
                            title: "\(run.provider.label) · \(AgentProvider.cliModel(run.model))",
                            trailingText: "\(run.log.count) lines",
                            statusColor: color
                        ) {
                            ScrollView {
                                Text(run.log.suffix(120).joined(separator: "\n"))
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .defaultScrollAnchor(.bottom)
                            .frame(height: 200)
                        }
                    }
                    .padding(.top, 8)
                }
            } label: {
                HStack(spacing: 10) {
                    AgentCharacterAvatar(role: run.role, isWorking: false, size: 38)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.headline)
                            Text("· \(run.role.personaName)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.roleColor(run.role))
                        }
                        if let latest = run.latestActivity, run.status == .running {
                            Text(latest)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    ProviderBadge(model: run.model, compact: true)

                    Spacer()

                    if run.status == .running {
                        ProgressView().controlSize(.small)
                    }
                    ForgeCodeChip(
                        text: "\(run.hasExactTokens ? "" : "~")\(Brand.formatTokens(run.effectiveTokens)) tok",
                        icon: "cpu",
                        tint: Brand.cyan
                    )
                    if run.toolCallsCount > 0 {
                        ForgeCodeChip(text: "\(run.toolCallsCount) tools", icon: "wrench.and.screwdriver", tint: Brand.indigo)
                    }
                    if let cost = run.cost {
                        ForgeCodeChip(text: String(format: "$%.2f", cost), tint: .secondary)
                    }
                    ForgeCodeChip(text: duration, icon: "clock", tint: .secondary)
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
        case .running: "bolt.horizontal.circle.fill"
        case .done: (run.findings?.contains(where: \.isBlocking) ?? false) ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .stopped: "stop.circle.fill"
        }
    }

    private var color: Color {
        switch run.status {
        case .running: Brand.indigo
        case .done: (run.findings?.contains(where: \.isBlocking) ?? false) ? Brand.amber : Brand.emerald
        case .failed: Brand.crimson
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
        ForgeCard(padding: 16, cornerRadius: 13) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().opacity(0.5)

                    Text(analysis.summary)
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    section("Approach", icon: "compass.drawing", [analysis.approach])
                    section("Files and modules", icon: "doc.on.doc", analysis.impacted)
                    section("Problems to handle", icon: "exclamationmark.shield", analysis.risks)
                    section("Assumptions", icon: "questionmark.circle", analysis.assumptions)
                    section("Acceptance criteria", icon: "checkmark.seal", analysis.acceptanceCriteria)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tint.opacity(0.16))
                            .frame(width: 28, height: 28)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text("Architecture & Feasibility Analysis")
                        .font(.headline)
                    PhaseBadge(text: analysis.feasibility.uppercased(), tint: tint)
                    Spacer()
                }
            }
        }
    }

    private var tint: Color {
        switch analysis.feasibility {
        case "feasible": Brand.emerald
        case "risky": Brand.amber
        default: Brand.crimson
        }
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(items.count > 1 ? "• \(item)" : item)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 4)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct FindingsList: View {
    let findings: [Finding]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        PhaseBadge(text: finding.severity.uppercased(), tint: tint(finding))
                        Text(finding.title)
                            .font(.callout.weight(.semibold))
                        if !finding.location.isEmpty {
                            ForgeCodeChip(text: finding.location, icon: "mappin.and.ellipse", tint: .secondary)
                        }
                    }
                    Text(finding.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tint(finding).opacity(0.22), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ finding: Finding) -> Color {
        switch finding.severity {
        case "blocker": Brand.crimson
        case "major": Brand.amber
        default: .secondary
        }
    }
}

/// The developer's validation between two steps: approve, with an optional note for the next agents, or send the work back.
struct GatePanel: View {
    @Environment(AppStore.self) private var store
    let feature: Feature
    let showDiff: () -> Void
    let createPullRequest: () -> Void
    @State private var note = ""
    @State private var dropped: Set<Int> = []

    private var isFix: Bool { feature.phase == .fixReview || feature.phase == .fixQA }
    private var devRan: Bool { feature.runs.contains { $0.role == .dev && $0.status == .done } }
    private var gateTint: Color { feature.phase == .ready ? Brand.emerald : Brand.amber }

    var body: some View {
        ForgeCard(padding: 18, cornerRadius: 13, tint: gateTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(gateTint.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: feature.phase == .ready ? "checkmark.seal.fill" : "hand.raised.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(gateTint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if isFix {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(feature.pending.enumerated()), id: \.offset) { i, finding in
                            Toggle(isOn: Binding(get: { !dropped.contains(i) }, set: { if $0 { dropped.remove(i) } else { dropped.insert(i) } })) {
                                FindingsList(findings: [finding])
                            }
                        }
                    }
                }

                TextField(feature.phase == .ready ? "What should the dev agent change?" : "Note for the next step (optional)",
                          text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    primaryButton
                    secondaryButton
                    Spacer()
                    if devRan {
                        Button(action: showDiff) {
                            Label("Inspect diff", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: feature.phase) { note = ""; dropped = [] }
    }

    @ViewBuilder private var primaryButton: some View {
        switch feature.phase {
        case .ready:
            Button(action: createPullRequest) {
                Label("Create PR…", systemImage: "arrow.triangle.pull")
            }
            .buttonStyle(.borderedProminent)
        case .fixReview, .fixQA:
            let kept = feature.pending.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
            Button(kept.isEmpty ? "Drop all and continue" : "Send \(kept.count) to dev") {
                act { $0.approve(note: note, keeping: kept) }
            }
            .buttonStyle(.borderedProminent)
        default:
            Button {
                act { $0.approve(note: note) }
            } label: {
                Label("Approve & start \(feature.phase == .qa ? "QA" : feature.phase.label.lowercased())", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var secondaryButton: some View {
        switch feature.phase {
        case .fixReview, .fixQA:
            Button(feature.phase == .fixReview ? "Skip fixes, go to QA" : "Skip fixes, ready for PR") { act { $0.skipFixes() } }
        case .dev where !devRan:
            Button("Redo analysis") { act { $0.redoAnalysis(note) } }
                .disabled(note.trimmed.isEmpty)
                .help("Write in the note what the analysis missed")
        default:
            Button("Ask dev for changes") { act { $0.requestChanges(note) } }
                .disabled(note.trimmed.isEmpty)
                .help("Write the changes in the note")
        }
    }

    private var title: String {
        switch feature.phase {
        case .dev: devRan ? "Your approval" : "Analysis done: your call"
        case .review: "Development done: check the change"
        case .fixReview: "Review done: \(feature.pending.count) finding(s) for dev"
        case .qa: feature.qaFixes > 0 ? "QA fixes done: check the change" : "Review passed: check the change"
        case .fixQA: "QA done: \(feature.pending.count) problem(s) for dev"
        case .ready: "QA passed: ready for the pull request"
        default: "Your approval"
        }
    }

    private var explanation: String {
        switch feature.phase {
        case .dev where !devRan: "Approve to start development: the dev agent gets the analysis and your note. Redo analysis sends your note back to the analyst."
        case .fixReview, .fixQA: "Untick what is not a real problem. The ticked findings and your note go to the dev agent; skipped ones stay as open points in the PR."
        case .ready: "Open the pull request, or send the dev agent back with a request: review and QA run again after it."
        default: "Look at the diff, then approve the next step (your note goes to its agents) or ask the dev agent for changes."
        }
    }

    private func act(_ change: (inout Feature) -> Void) {
        store.update(feature.id, change)
        store.save()
        store.start(feature.id)
    }
}

/// What the agents changed in the worktree, tracked and new files.
struct DiffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let feature: Feature
    @State private var lines: [String]?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Brand.amber)
                Text("Worktree Diff")
                    .font(.headline)
                ForgeCodeChip(text: feature.branch, icon: "arrow.triangle.branch", tint: Brand.amber)
                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForgeCodeChip(text: String(feature.baseCommit.prefix(8)), icon: "number", tint: .secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(.background.secondary)

            Divider()

            Group {
                if let lines {
                    if lines.allSatisfy(\.isEmpty) {
                        ContentUnavailableView("No change yet", systemImage: "doc")
                    } else {
                        ScrollView([.vertical, .horizontal]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(lines.indices, id: \.self) { i in
                                    Text(lines[i].isEmpty ? " " : lines[i])
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundStyle(color(lines[i]))
                                        .fixedSize()
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 1)
                                }
                            }
                            .textSelection(.enabled)
                            .padding(.vertical, 10)
                        }
                        .background(Brand.obsidian)
                        .environment(\.colorScheme, .dark)
                    }
                } else {
                    ProgressView("Computing git diff…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 920, height: 660)
        .task { lines = await Git.diff(worktree: feature.worktreePath, base: feature.baseCommit).components(separatedBy: "\n") }
    }

    private func color(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") { return Brand.steel }
        if line.hasPrefix("+") { return Brand.emerald }
        if line.hasPrefix("-") { return Brand.crimson }
        if line.hasPrefix("@@") { return Brand.indigo }
        return Brand.steel.opacity(0.65)
    }
}

#endif
