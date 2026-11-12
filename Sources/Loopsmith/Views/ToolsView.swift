#if os(macOS)
import SwiftUI

/// Chooses the MCP servers and skills the agents may use. Everything the user's Claude Code has is on
/// unless switched off here: off means denied to the agents (`--disallowedTools`).
struct ToolsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let folder: String
    @Binding var disabledMCP: [String]
    @Binding var disabledSkills: [String]
    @State private var inventory: ToolInventory?
    @State private var error: String?
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(Brand.amber)
                Text("Agent MCP Servers & Skills")
                    .font(.headline)
                Spacer()
                TextField("Filter…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                Button {
                    Task { await load(reload: true) }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
            .padding(14)
            .background(.background.secondary)

            Divider()

            if let inventory {
                List {
                    Section("MCP servers (\(inventory.servers.filter { !disabledMCP.contains($0.name) }.count) on)") {
                        ForEach(inventory.servers.filter { matches($0.name) }, id: \.name) { server in
                            Toggle(isOn: enabled(server.name, in: $disabledMCP)) {
                                HStack {
                                    Text(server.name)
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    PhaseBadge(
                                        text: server.status.uppercased(),
                                        tint: server.status == "connected" ? Brand.emerald : .secondary
                                    )
                                }
                            }
                        }
                    }
                    Section("Skills, Claude Code agents only (\(inventory.skills.filter { !disabledSkills.contains($0) }.count) on)") {
                        ForEach(inventory.skills.filter { matches($0) }, id: \.self) { skill in
                            Toggle(skill, isOn: enabled(skill, in: $disabledSkills))
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView("Could not list the tools", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Loading MCP servers and skills…").frame(maxHeight: .infinity)
            }
        }
        .frame(width: 540, height: 560)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { await load(reload: false) }
    }

    private func matches(_ name: String) -> Bool {
        filter.isEmpty || name.localizedCaseInsensitiveContains(filter)
    }

    private func enabled(_ name: String, in disabled: Binding<[String]>) -> Binding<Bool> {
        Binding(get: { !disabled.wrappedValue.contains(name) },
                set: { on in
                    disabled.wrappedValue.removeAll { $0 == name }
                    if !on { disabled.wrappedValue.append(name) }
                })
    }

    private func load(reload: Bool) async {
        error = nil
        do { inventory = try await store.inventory(for: folder, reload: reload) } catch { self.error = error.localizedDescription }
    }
}

#endif
