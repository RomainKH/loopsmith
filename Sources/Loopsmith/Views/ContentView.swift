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
            List(selection: $selection) {
                Section("Work") {
                    Label("Worklog", systemImage: "clock").tag(SidebarItem.worklog)
                    Label("Pull requests", systemImage: "arrow.triangle.pull").tag(SidebarItem.pullRequests)
                }
                ForEach(store.projects) { project in
                    Section(project.name) {
                        HStack {
                            Label("Project brief", systemImage: "doc.text.magnifyingglass")
                            if project.scanning { Spacer(); ProgressView().controlSize(.mini) }
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
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(feature.title).lineLimit(1)
            HStack(spacing: 4) {
                if feature.running {
                    ProgressView().controlSize(.mini)
                } else if feature.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text([feature.jiraKey, feature.phase.label].compactMap { $0 }.joined(separator: " · "))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
