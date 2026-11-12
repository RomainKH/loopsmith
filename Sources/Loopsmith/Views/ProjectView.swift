import AppKit
import SwiftUI

/// A project's brief (written by an agent, editable), its default base branch and the tools of its new features.
struct ProjectView: View {
    @Environment(AppStore.self) private var store
    let id: UUID
    @State private var showTools = false
    @State private var confirmRemove = false

    var body: some View {
        if let p = store.project(id) {
            VStack(alignment: .leading, spacing: 12) {
                Text(p.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    LabeledContent("Default base branch") {
                        TextField("main", text: binding(\.baseBranch, p)).frame(maxWidth: 200)
                    }
                    .fixedSize()
                    Spacer()
                    if let date = p.briefUpdatedAt {
                        Text("Brief written \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = p.scanError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).textSelection(.enabled)
                }
                if p.scanning {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView("An agent is reading the project…").controlSize(.small)
                        ScrollView {
                            Text(p.scanLog.suffix(200).joined(separator: "\n"))
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .defaultScrollAnchor(.bottom)
                        .frame(height: 160)
                    }
                }
                Text("Brief given to every agent of this project's features. Edit it freely: the next agents read this text.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding(get: { p.brief ?? "" }, set: { text in store.updateProject(id) { $0.brief = text }; store.save() }))
                    .font(.body.monospaced())
                    .disabled(p.scanning)
                    .overlay {
                        if (p.brief ?? "").isEmpty && !p.scanning {
                            Text("No brief yet: Write brief asks an agent to read the project.").foregroundStyle(.tertiary)
                        }
                    }
            }
            .padding(20)
            .navigationTitle(p.name)
            .toolbar {
                ToolbarItemGroup {
                    if p.scanning {
                        Button { store.stop(id) } label: { Label("Stop", systemImage: "stop.fill") }
                    } else {
                        Button { store.scanProject(id) } label: {
                            Label(p.brief == nil ? "Write brief" : "Rewrite brief", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    Button { showTools = true } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                        .help("MCP servers and skills new features of this project start with")
                    Menu {
                        Button("Open in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: p.path)) }
                        Divider()
                        Button("Remove project…", role: .destructive) { confirmRemove = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showTools) {
                ToolsView(folder: p.path, disabledMCP: binding(\.disabledMCP, p), disabledSkills: binding(\.disabledSkills, p))
            }
            .confirmationDialog("Remove “\(p.name)” from Loopsmith?", isPresented: $confirmRemove) {
                Button("Remove project", role: .destructive) { store.removeProject(id) }
            } message: {
                Text("The repository and the worktrees stay on disk; its features move to “Other projects”.")
            }
        } else {
            ContentUnavailableView("No project", systemImage: "folder")
        }
    }

    private func binding<T>(_ path: WritableKeyPath<Project, T>, _ fallback: Project) -> Binding<T> {
        Binding(get: { (store.project(id) ?? fallback)[keyPath: path] },
                set: { value in store.updateProject(id) { $0[keyPath: path] = value }; store.save() })
    }
}
