import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case worklog, pullRequests, project(UUID), feature(UUID)
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: SidebarItem? = .worklog
    @State private var showNewFeature = false
    @State private var addError: String?

    private var otherFeatures: [Feature] { store.features.filter { store.project(at: $0.repoPath) == nil } }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SidebarBrandHeader(settings: store.settings)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                List(selection: $selection) {
                    Section("Workspace") {
                        Label("Worklog", systemImage: "clock")
                            .tag(SidebarItem.worklog)

                        Label("Pull requests", systemImage: "arrow.triangle.pull")
                            .tag(SidebarItem.pullRequests)
                    }
                    ForEach(store.projects) { project in
                        Section(project.name) {
                            HStack(spacing: 6) {
                                Label("Project brief", systemImage: "doc.text.magnifyingglass")
                                Spacer()
                                if project.scanning {
                                    ProgressView().controlSize(.mini)
                                } else if project.brief != nil {
                                    Circle().fill(Brand.emerald.opacity(0.8)).frame(width: 6, height: 6)
                                        .help("Project brief ready")
                                }
                            }
                            .tag(SidebarItem.project(project.id))

                            ForEach(store.features.filter { $0.repoPath == project.path }) { feature in
                                FeatureRow(feature: feature).tag(SidebarItem.feature(feature.id))
                            }
                        }
                    }
                    if !otherFeatures.isEmpty {
                        Section("Other projects") {
                            ForEach(otherFeatures) { FeatureRow(feature: $0).tag(SidebarItem.feature($0.id)) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 245, ideal: 280)
            .toolbar {
                Button(action: addProject) { Label("Add project", systemImage: "folder.badge.plus") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button { showNewFeature = true } label: { Label("New feature", systemImage: "plus") }
                    .keyboardShortcut("n")
                    .disabled(store.projects.isEmpty)
            }
        } detail: {
            switch selection {
            case .worklog, nil: WorklogView()
            case .pullRequests: PullRequestsView()
            case .project(let id): ProjectView(id: id)
            case .feature(let id): FeatureView(id: id)
            }
        }
        .sheet(isPresented: $showNewFeature) {
            NewFeatureView { selection = .feature($0) }
        }
        .alert("Could not add the project", isPresented: Binding(get: { addError != nil }, set: { if !$0 { addError = nil } })) {
            Button("OK") {}
        } message: {
            Text(addError ?? "")
        }
    }

    private func addProject() {
        Task {
            do {
                if let id = try await store.chooseAndAddProject() { selection = .project(id) }
            } catch {
                addError = error.localizedDescription
            }
        }
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
        if feature.running { return Brand.amber }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(feature.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let lastRun = feature.runs.last {
                    Image(systemName: lastRun.provider.icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.providerColor(lastRun.provider))
                        .help(lastRun.provider.label)
                }
            }
            HStack(spacing: 5) {
                if feature.running {
                    ProgressView().controlSize(.mini)
                } else if feature.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.crimson)
                } else if feature.isAwaiting {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Brand.amber)
                } else if feature.phase == .ready || feature.phase == .prOpened {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.emerald)
                } else {
                    Circle().fill(statusColor.opacity(0.6)).frame(width: 6, height: 6)
                }
                if let key = feature.jiraKey {
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Brand.amber)
                    Text("·").foregroundStyle(.tertiary)
                }
                Text(feature.isAwaiting ? "Your approval" : feature.phase.label)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
