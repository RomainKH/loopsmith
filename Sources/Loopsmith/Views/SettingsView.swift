import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView {
            Form {
                Section {
                    HStack(spacing: 12) {
                        LoopsmithLogoMark(size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loopsmith: Forge & Precision")
                                .font(.headline)
                            Text(Brand.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Workspace & Worktrees") {
                    LabeledContent("Worktrees folder") {
                        HStack {
                            Text(store.settings.worktreesRoot)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.canCreateDirectories = true
                                if panel.runModal() == .OK, let url = panel.url { store.settings.worktreesRoot = url.path }
                            }
                        }
                    }
                    TextField("Copy into new worktrees", text: $store.settings.copyFiles, prompt: Text(".env, .env.local"))
                }

                Section("Pipeline, Notifications & Worklog") {
                    Toggle("Visual & macOS notifications when agents start or wait for approval",
                           isOn: $store.settings.notificationsEnabled)
                    Stepper("Fix rounds after review and after QA: \(store.settings.maxFixRounds)",
                            value: $store.settings.maxFixRounds, in: 0...5)
                    Stepper("Daily target: \(store.settings.dailyHours.formatted())h",
                            value: $store.settings.dailyHours, in: 1...12, step: 0.5)
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form { AgentsSetupSections() }
                .tabItem { Label("Agents & AI", systemImage: "cpu") }

            Form { JiraSetupSection() }
                .tabItem { Label("Jira", systemImage: "checklist") }

            Form { GitHubSetupSection() }
                .tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 540)
        .onChange(of: store.settings) { store.saveSettings() }
    }
}
