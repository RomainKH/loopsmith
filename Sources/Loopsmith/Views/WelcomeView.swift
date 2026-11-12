#if os(macOS)
import SwiftUI

/// The window while no project is open. The first time, it goes through the setup: the project folder, the AI
/// agents, Jira (optional) and GitHub; afterwards, choosing a folder opens it at once.
struct WelcomeView: View {
    @Environment(AppStore.self) private var store

    enum Step: Int, CaseIterable {
        case project, agents, jira, github
        var title: String { ["Project", "AI agents", "Jira (optional)", "GitHub"][rawValue] }
        var icon: String { ["folder.fill", "cpu.fill", "checklist", "arrow.triangle.pull"][rawValue] }
    }

    @State private var step = Step.project
    @State private var chosen: UUID?
    @State private var error: String?

    var body: some View {
        ZStack {
            ForgeCanvasBackground()

            VStack(spacing: 0) {
                heroHeader
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                if !store.settings.onboarded {
                    stepIndicator
                        .padding(.bottom, 16)
                }

                Group {
                    switch step {
                    case .project:
                        projectStep
                    case .agents:
                        setupStep("Connect your AI agents",
                                  "Each step of a feature runs one of your own CLIs. Pick the model of each role: Claude Code, Antigravity or Gemini.",
                                  icon: "cpu.fill") {
                            AgentsSetupSections()
                        }
                    case .jira:
                        setupStep("Connect Jira",
                                  "Optional: start features from your tickets and log your time. You can skip it and connect later in Settings.",
                                  icon: "checklist") {
                            JiraSetupSection()
                        }
                    case .github:
                        setupStep("GitHub",
                                  "Pull requests are listed and opened with your GitHub CLI login.",
                                  icon: "arrow.triangle.pull") {
                            GitHubSetupSection()
                        }
                    }
                }
                .frame(maxWidth: 740, maxHeight: .infinity, alignment: .top)

                if step != .project {
                    footer
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Brand.amber.opacity(0.18), Brand.steel.opacity(0.06), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 68
                        )
                    )
                    .frame(width: 120, height: 120)

                LoopsmithLogoMark(size: 68)
            }

            PhaseBadge(text: "FORGE & PRECISION", tint: Brand.amber, icon: "hammer.fill")

            Text("Welcome to Loopsmith")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(Brand.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(Step.allCases, id: \.self) { s in
                stepNode(for: s)
                if s != Step.allCases.last {
                    Rectangle()
                        .fill(s.rawValue < step.rawValue ? Brand.emerald.opacity(0.5) : Color.primary.opacity(0.10))
                        .frame(width: 24, height: 1.5)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.background.secondary.opacity(0.75), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
    }

    private func stepNode(for s: Step) -> some View {
        let isDone = s.rawValue < step.rawValue
        let isCurrent = s == step
        let circleFill: Color = isDone ? Brand.emerald.opacity(0.18) : (isCurrent ? Brand.amber.opacity(0.20) : Color.secondary.opacity(0.12))
        let labelColor: Color = isCurrent ? Color.primary : (isDone ? Color.primary.opacity(0.8) : Color.secondary)

        return HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(circleFill)
                    .frame(width: 24, height: 24)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Brand.emerald)
                } else {
                    Image(systemName: s.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isCurrent ? Brand.amber : Color.secondary)
                }
            }
            Text(s.title)
                .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isCurrent ? Brand.amber.opacity(0.10) : Color.clear)
        )
        .overlay(
            Capsule()
                .strokeBorder(isCurrent ? Brand.amber.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private var projectStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForgeCard(padding: 20, cornerRadius: 14, tint: Brand.amber) {
                    VStack(spacing: 14) {
                        Text(store.settings.onboarded ? "Open a repository workspace" : "Choose the project you work on")
                            .font(.title3.weight(.semibold))

                        Text("A project is a git repository on your Mac. Each feature gets its own isolated git worktree, and an agent writes a brief of the repository for the pipeline.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)

                        HStack(spacing: 8) {
                            ForgeCodeChip(text: "Isolated Git Worktrees", icon: "arrow.triangle.branch", tint: Brand.amber)
                            ForgeCodeChip(text: "Analysis → Dev → Review → QA", icon: "sparkles", tint: Brand.indigo)
                            ForgeCodeChip(text: "Human Approval Gates", icon: "hand.raised.fill", tint: Brand.emerald)
                        }

                        Button(action: choose) {
                            Label("Choose a project folder…", systemImage: "folder.badge.plus")
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 2)

                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(Brand.crimson)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !store.projects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ForgeSectionHeader(title: "Recent projects", icon: "clock.arrow.circlepath", tint: Brand.amber)
                            Spacer()
                            Text("\(store.projects.count) repo(s)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(store.projects) { p in
                            let count = store.features(of: p).count
                            let runningCount = store.features(of: p).filter(\.running).count
                            Button { picked(p.id) } label: {
                                ForgeCard(padding: 12, cornerRadius: 10) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Brand.amber.opacity(0.14))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "shippingbox.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Brand.amber)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 8) {
                                                Text(p.name)
                                                    .font(.headline)
                                                ForgeCodeChip(text: p.baseBranch, icon: "arrow.triangle.branch", tint: .secondary)
                                            }
                                            Text((p.path as NSString).abbreviatingWithTildeInPath)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        Spacer()
                                        if runningCount > 0 {
                                            PhaseBadge(text: "\(runningCount) RUNNING", tint: Brand.indigo, icon: "bolt.fill")
                                        }
                                        PhaseBadge(text: "\(count) feature\(count == 1 ? "" : "s")", tint: .secondary)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 620)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func setupStep<Content: View>(_ title: String, _ subtitle: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.amber)
                Text(title)
                    .font(.title2.weight(.semibold))
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Form { content() }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                step = Step(rawValue: step.rawValue - 1) ?? .project
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            Spacer()
            if step == .jira {
                Button("Skip for now") { next() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            Button {
                next()
            } label: {
                HStack(spacing: 6) {
                    Text(step == .github ? "Open Project Workspace" : "Continue")
                    Image(systemName: step == .github ? "arrow.right.circle.fill" : "chevron.right")
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: 740)
        .background(.background.secondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        .padding(.bottom, 16)
    }

    private func choose() {
        error = nil
        Task {
            do { if let id = try await store.chooseAndAddProject() { picked(id) } } catch { self.error = error.localizedDescription }
        }
    }

    private func picked(_ id: UUID) {
        chosen = id
        if store.settings.onboarded { store.openProject(id) } else { step = .agents }
    }

    private func next() {
        guard step == .github else {
            step = Step(rawValue: step.rawValue + 1) ?? .github
            return
        }
        store.settings.onboarded = true
        store.openProject(chosen)
    }
}

#endif
