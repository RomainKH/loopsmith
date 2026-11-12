import AppKit
import SwiftUI

/// A project's home: what waits for the developer, what runs, its pull requests and today's time on it, then its
/// settings and the brief every agent of its features gets.
struct ProjectHomeView: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let navigate: (ProjectSection) -> Void
    let newFeature: () -> Void
    @State private var openPullRequests: Int?
    @State private var todaySeconds: Int?
    @State private var showTools = false
    @State private var confirmRemove = false
    @State private var showBrief = false

    private var features: [Feature] { store.features(of: project) }
    private var waiting: [Feature] { features.filter { $0.isAwaiting || ($0.phase == .ready && !$0.running) || ($0.error != nil && !$0.running) } }
    private var running: [Feature] { features.filter(\.running) }

    var body: some View {
        ZStack {
            ForgeCanvasBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if features.isEmpty { firstFeature } else { cards }
                    settingsBox
                    briefBox
                }
                .padding(26)
                .frame(maxWidth: 1020, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(project.name)
        .task(id: project.id) { await loadCounts() }
        .sheet(isPresented: $showTools) {
            ToolsView(folder: project.path, disabledMCP: binding(\.disabledMCP), disabledSkills: binding(\.disabledSkills))
        }
        .confirmationDialog("Remove “\(project.name)” from Loopsmith?", isPresented: $confirmRemove) {
            Button("Remove project", role: .destructive) { store.removeProject(project.id) }
        } message: {
            Text("The repository and the worktrees stay on disk. Its features come back if you add the same folder again.")
        }
    }

    private var header: some View {
        ForgeCard(padding: 18, cornerRadius: 14) {
            HStack(alignment: .center, spacing: 14) {
                LoopsmithLogoMark(size: 46)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                        ForgeCodeChip(text: project.baseBranch, icon: "arrow.triangle.branch", tint: Brand.amber)
                        if let keys = project.jiraKeys, !keys.trimmed.isEmpty {
                            ForgeCodeChip(text: keys, icon: "tag.fill", tint: Brand.indigo)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(project.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Button(action: newFeature) {
                    Label("New feature", systemImage: "plus")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Menu {
                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    Divider()
                    Button("Remove project…", role: .destructive) { confirmRemove = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.large)
            }
        }
    }

    private var firstFeature: some View {
        ForgeCard(padding: 20, cornerRadius: 14, tint: Brand.amber) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Brand.amber.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Brand.amber)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start your first feature")
                            .font(.title3.weight(.semibold))
                        Text("Isolated worktree · Multi-agent pipeline · Human approval at every gate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: newFeature) {
                        Label("New feature", systemImage: "plus")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Text("Describe what to build, or pick a Jira ticket. Loopsmith creates a dedicated git worktree for it, an analysis agent reads the request against the codebase, then the dev, review and QA agents work in turn while you approve each gate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ForgeCodeChip(text: "1. Analysis", icon: "magnifyingglass", tint: Brand.amber)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    ForgeCodeChip(text: "2. Development", icon: "hammer.fill", tint: Brand.indigo)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    ForgeCodeChip(text: "3. Multi-Lens Review", icon: "eye.fill", tint: Brand.claude)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    ForgeCodeChip(text: "4. QA & Pull Request", icon: "checkmark.seal.fill", tint: Brand.emerald)
                }
            }
        }
    }

    private var cards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), spacing: 14)], spacing: 14) {
            card("Waiting for you",
                 subtitle: waiting.isEmpty ? "No gate waiting" : "Awaiting your decision",
                 value: "\(waiting.count)",
                 icon: "hand.raised.fill",
                 tint: waiting.isEmpty ? .secondary : Brand.amber,
                 lines: waiting.prefix(3).map { ($0.title, $0.id) })

            card("Running",
                 subtitle: running.isEmpty ? "Idle pipeline" : "Active CLI agents",
                 value: "\(running.count)",
                 icon: "gearshape.2.fill",
                 tint: running.isEmpty ? .secondary : Brand.indigo,
                 lines: running.prefix(3).map { ($0.title, $0.id) })

            card("Open pull requests",
                 subtitle: "GitHub repository PRs",
                 value: openPullRequests.map(String.init) ?? "–",
                 icon: "arrow.triangle.pull",
                 tint: Brand.emerald,
                 lines: [],
                 action: { navigate(.pullRequests) })

            card("Today on this project",
                 subtitle: store.jira.isConfigured ? "Logged in Jira today" : "Connect Jira to track",
                 value: todaySeconds.map(Jira.formatDuration) ?? "–",
                 icon: "clock.fill",
                 tint: Brand.copper,
                 lines: [],
                 action: { navigate(.worklog) })
        }
    }

    private func card(_ title: String, subtitle: String, value: String, icon: String, tint: Color, lines: [(String, UUID)],
                      action: (() -> Void)? = nil) -> some View {
        ForgeCard(padding: 15, cornerRadius: 12, tint: tint == .secondary ? nil : tint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.16))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if action != nil {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !lines.isEmpty {
                    Divider().opacity(0.5)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(lines, id: \.1) { itemTitle, id in
                            Button {
                                navigate(.feature(id))
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(tint).frame(width: 5, height: 5)
                                    Text(itemTitle)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary.opacity(0.9))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { action?() }
        }
    }

    private var settingsBox: some View {
        ForgeCard(padding: 18, cornerRadius: 13) {
            VStack(alignment: .leading, spacing: 14) {
                ForgeSectionHeader(
                    title: "Project settings",
                    subtitle: "Branching, Jira ticket filtering, and MCP/Skill permissions for this repository.",
                    icon: "slider.horizontal.3",
                    tint: Brand.amber
                )

                Divider().opacity(0.5)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Label("Default base branch", systemImage: "arrow.triangle.branch")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("main", text: binding(\.baseBranch))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                            .frame(maxWidth: 240)
                    }
                    GridRow {
                        Label("Jira project keys", systemImage: "checklist")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("APP, WEB", text: Binding(get: { project.jiraKeys ?? "" },
                                                             set: { v in store.updateProject(project.id) { $0.jiraKeys = v }; store.save() }))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                            .frame(maxWidth: 240)
                            .help("Only these tickets are offered for new features and counted in this project's worklog")
                    }
                    GridRow {
                        Label("Agent tools & skills", systemImage: "wrench.and.screwdriver")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button {
                                showTools = true
                            } label: {
                                Label("\(project.disabledMCP.count) MCP server(s), \(project.disabledSkills.count) skill(s) off…",
                                      systemImage: "slider.horizontal.2.square")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var briefBox: some View {
        ForgeCard(padding: 18, cornerRadius: 13) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ForgeSectionHeader(
                        title: "Project brief",
                        icon: "doc.text.magnifyingglass",
                        tint: Brand.indigo
                    )

                    if project.scanning {
                        PhaseBadge(text: "SCANNING REPO", tint: Brand.amber, icon: "rays")
                    } else if project.brief != nil {
                        PhaseBadge(text: "BRIEF READY", tint: Brand.emerald, icon: "checkmark.circle.fill")
                    } else {
                        PhaseBadge(text: "NO BRIEF", tint: .secondary, icon: "doc")
                    }

                    if let date = project.briefUpdatedAt {
                        Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if project.brief != nil && !project.scanning {
                        Button(showBrief ? "Hide editor" : "Show & edit") {
                            showBrief.toggle()
                        }
                    }
                    if project.scanning {
                        Button {
                            store.stop(project.id)
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            store.scanProject(project.id)
                        } label: {
                            Label(project.brief == nil ? "Write brief" : "Rewrite brief", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text("Given to every agent of this project's features: what the project is, how to set up a worktree, the commands that gate a merge, conventions and pitfalls. Edit it freely: the next agents read this text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = project.scanError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Brand.amber)
                        .textSelection(.enabled)
                }

                if showBrief || project.brief == nil || project.scanning {
                    briefEditor
                }
            }
        }
    }

    @ViewBuilder private var briefEditor: some View {
        if project.scanning {
            ForgeTerminalBox(title: "Agent scanning repository…", statusColor: Brand.amber) {
                ScrollView {
                    Text(project.scanLog.suffix(200).joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .frame(height: 150)
            }
        }
        TextEditor(text: Binding(get: { project.brief ?? "" },
                                 set: { text in store.updateProject(project.id) { $0.brief = text }; store.save() }))
            .font(.system(size: 12.5, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(height: 380)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            )
            .disabled(project.scanning)
            .overlay {
                if (project.brief ?? "").isEmpty && !project.scanning {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("No brief yet — click “Write brief” to have an agent inspect the repository.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private func loadCounts() async {
        openPullRequests = (try? await GitHub.myPullRequests(repo: project.path))?.filter { $0.state == "OPEN" }.count
        guard store.jira.isConfigured, let logs = try? await store.jira.worklogs(on: Date()) else { return }
        todaySeconds = logs.filter { project.owns(issueKey: $0.issueKey) }.reduce(0) { $0 + $1.seconds }
    }

    private func binding<T>(_ path: WritableKeyPath<Project, T>) -> Binding<T> {
        Binding(get: { (store.project(project.id) ?? project)[keyPath: path] },
                set: { value in store.updateProject(project.id) { $0[keyPath: path] = value }; store.save() })
    }
}
