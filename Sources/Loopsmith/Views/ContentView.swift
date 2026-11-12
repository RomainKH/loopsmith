#if os(macOS)
import AppKit
import SwiftUI

enum ProjectSection: Hashable {
    case overview, pullRequests, worklog, feature(UUID)
}

/// The window: the welcome steps while no project is open, else the open project.
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if let project = store.openProject {
                ProjectWorkspace(project: project).id(project.id)
            } else {
                WelcomeView()
            }
        }
        .onChange(of: store.settings) { store.saveSettings() }
    }
}

/// One project: its overview, pull requests, worklog and the features in progress or shipped.
struct ProjectWorkspace: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var selection: ProjectSection?
    @State private var showNewFeature = false
    @State private var addError: String?

    init(project: Project, selection: ProjectSection? = .overview) {
        self.project = project
        _selection = State(initialValue: selection)
    }

    private var features: [Feature] { store.features(of: project) }
    private var inProgress: [Feature] { features.filter { $0.phase != .prOpened } }
    private var shipped: [Feature] { features.filter { $0.phase == .prOpened } }
    private var waitingCount: Int { inProgress.filter { $0.isAwaiting || ($0.phase == .ready && !$0.running) }.count }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ProjectSwitcher(project: project, addError: $addError)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                List(selection: $selection) {
                    Section("Workspace") {
                        HStack {
                            Label("Overview", systemImage: "square.grid.2x2.fill")
                            Spacer()
                            if waitingCount > 0 {
                                PhaseBadge(text: "\(waitingCount)", tint: Brand.amber, icon: "hand.raised.fill")
                            }
                        }
                        .tag(ProjectSection.overview)

                        Label("Pull requests", systemImage: "arrow.triangle.pull")
                            .tag(ProjectSection.pullRequests)

                        Label("Worklog", systemImage: "clock.fill")
                            .tag(ProjectSection.worklog)
                    }

                    Section {
                        ForEach(inProgress) {
                            FeatureRow(feature: $0).tag(ProjectSection.feature($0.id))
                        }
                        Button {
                            showNewFeature = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Brand.amber)
                                Text("New feature…")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        HStack {
                            Text("Work in progress")
                            Spacer()
                            if !inProgress.isEmpty {
                                Text("\(inProgress.count)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !shipped.isEmpty {
                        Section {
                            ForEach(shipped) {
                                FeatureRow(feature: $0).tag(ProjectSection.feature($0.id))
                            }
                        } header: {
                            HStack {
                                Text("Shipped")
                                Spacer()
                                Text("\(shipped.count)")
                                    .font(.caption2.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 290)
            .toolbar {
                Button { showNewFeature = true } label: { Label("New feature", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
        } detail: {
            ZStack(alignment: .topTrailing) {
                Group {
                    switch selection {
                    case .overview, nil:
                        ProjectHomeView(project: project, navigate: { selection = $0 }, newFeature: { showNewFeature = true })
                    case .pullRequests:
                        PullRequestsView(project: project) { selection = .feature($0) }
                    case .worklog:
                        WorklogView(project: project)
                    case .feature(let id):
                        FeatureView(id: id)
                    }
                }
                AgentToastOverlay { featureID in
                    selection = .feature(featureID)
                }
            }
            .animation(.spring(duration: 0.38, bounce: 0.2), value: store.activeToast)
        }
        .sheet(isPresented: $showNewFeature) {
            NewFeatureView(project: project) { selection = .feature($0) }
        }
        .alert("Could not add the project", isPresented: Binding(get: { addError != nil }, set: { if !$0 { addError = nil } })) {
            Button("OK") {}
        } message: {
            Text(addError ?? "")
        }
    }
}

/// Top of the sidebar: the open project, and a menu to switch, add or close one.
struct ProjectSwitcher: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @Binding var addError: String?

    var body: some View {
        HStack(spacing: 10) {
            LoopsmithLogoMark(size: 32)
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    if project.scanning {
                        ProgressView().controlSize(.mini)
                    }
                }
                Text((URL(fileURLWithPath: project.path).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Menu {
                Section("Projects") {
                    ForEach(store.projects) { p in
                        Button { store.openProject(p.id) } label: {
                            if p.id == project.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                        }
                    }
                }
                Divider()
                Button("Add project…") {
                    Task {
                        do { if let id = try await store.chooseAndAddProject() { store.openProject(id) } } catch { addError = error.localizedDescription }
                    }
                }
                Button("Close project") { store.openProject(nil) }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch, add or close a project")
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.background.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

extension AppStore {
    /// Asks for a repository folder, registers it and starts its brief. Nil when the user cancels.
    func chooseAndAddProject() async throws -> UUID? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add project"
        panel.message = "Choose the folder of a git repository"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let isNew = project(at: url.path) == nil
        let id = try await addProject(path: url.path)
        if isNew { scanProject(id) }
        return id
    }
}

struct FeatureRow: View {
    let feature: Feature

    private var statusColor: Color {
        if feature.error != nil { return Brand.crimson }
        if feature.isAwaiting { return Brand.amber }
        if feature.phase == .ready || feature.phase == .prOpened { return Brand.emerald }
        if feature.running { return Brand.indigo }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(feature.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let lastRun = feature.runs.last {
                    Image(systemName: lastRun.provider.icon)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Brand.providerColor(lastRun.provider))
                        .padding(4)
                        .background(Brand.providerColor(lastRun.provider).opacity(0.14), in: Circle())
                        .help(lastRun.provider.label)
                }
            }
            HStack(spacing: 5) {
                if feature.running {
                    ProgressView().controlSize(.mini)
                } else if feature.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.crimson)
                } else if feature.isAwaiting {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.amber)
                } else if feature.phase == .ready || feature.phase == .prOpened {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.emerald)
                } else {
                    Circle().fill(statusColor.opacity(0.65)).frame(width: 6, height: 6)
                }
                if let key = feature.jiraKey {
                    Text(key)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Brand.amber.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .foregroundStyle(Brand.amber)
                }
                Text(feature.isAwaiting ? "Your approval" : feature.phase.label)
                    .font(.caption)
                    .foregroundStyle(feature.isAwaiting ? Brand.amber : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

#endif
