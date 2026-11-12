import SwiftUI

extension Brand {
    static func roleColor(_ role: Role) -> Color {
        switch role {
        case .analysis: cyan
        case .dev: cobalt
        case .review: indigo
        case .qa: emerald
        }
    }

    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

/// Animated mini-character avatar for each AI agent role:
/// - Nova (`.analysis`): Radar-equipped scout scanning a floating hologram.
/// - Atlas (`.dev`): Welder-visored forge bot striking code with an energy hammer & electric blue sparks.
/// - Orion (`.review`): Monocled inspector sweeping a magnifying lens over code lines.
/// - Aegis (`.qa`): Armored sentinel projecting a pulsing hexagonal shield & verification rings.
struct AgentCharacterAvatar: View {
    let role: Role
    var isWorking: Bool = false
    var size: CGFloat = 54

    private var tint: Color { Brand.roleColor(role) }

    var body: some View {
        if isWorking {
            TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { ctx, canvasSize in
                    drawCharacter(ctx: &ctx, size: canvasSize, t: t)
                }
                .frame(width: size, height: size)
            }
        } else {
            Canvas { ctx, canvasSize in
                drawCharacter(ctx: &ctx, size: canvasSize, t: 0.0)
            }
            .frame(width: size, height: size)
        }
    }

    private func drawCharacter(ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width
        let h = size.height
        let s = min(w, h) / 100.0

        let bob = isWorking ? sin(t * 7.5) * 3.2 * s : sin(t * 2.0) * 1.2 * s
        let pulse = (sin(t * (isWorking ? 6.0 : 2.0)) + 1.0) * 0.5

        // Stage base / aura
        let auraRect = CGRect(x: 6 * s, y: 6 * s, width: 88 * s, height: 88 * s)
        let auraPath = Path(roundedRect: auraRect, cornerRadius: 24 * s, style: .continuous)
        ctx.fill(
            auraPath,
            with: .linearGradient(
                Gradient(colors: [Brand.charcoal, Brand.obsidian]),
                startPoint: CGPoint(x: 50 * s, y: 0),
                endPoint: CGPoint(x: 50 * s, y: 100 * s)
            )
        )
        ctx.stroke(
            auraPath,
            with: .color(isWorking ? tint.opacity(0.45 + 0.35 * pulse) : Brand.steel.opacity(0.14)),
            lineWidth: (isWorking ? 2.0 : 1.0) * s
        )

        if isWorking {
            let glowCircle = Path(ellipseIn: CGRect(x: 16 * s, y: 16 * s, width: 68 * s, height: 68 * s))
            ctx.fill(
                glowCircle,
                with: .radialGradient(
                    Gradient(colors: [tint.opacity(0.24 + 0.12 * pulse), .clear]),
                    center: CGPoint(x: 50 * s, y: 52 * s),
                    startRadius: 2 * s,
                    endRadius: 38 * s
                )
            )
        }

        // Ground shadow
        let shadow = Path(ellipseIn: CGRect(x: 28 * s, y: 79 * s, width: 44 * s, height: 7 * s))
        ctx.fill(shadow, with: .color(.black.opacity(0.45)))

        // Character Torso (Brushed Titanium)
        let torsoRect = CGRect(x: 31 * s, y: 54 * s + bob * 0.6, width: 38 * s, height: 24 * s)
        let torsoPath = Path(roundedRect: torsoRect, cornerRadius: 9 * s, style: .continuous)
        ctx.fill(
            torsoPath,
            with: .linearGradient(
                Gradient(colors: [Brand.steel.opacity(0.9), Brand.titanium.opacity(0.65)]),
                startPoint: CGPoint(x: 50 * s, y: torsoRect.minY),
                endPoint: CGPoint(x: 50 * s, y: torsoRect.maxY)
            )
        )

        // Chest Core Reactor
        let coreRect = CGRect(x: 44 * s, y: 61 * s + bob * 0.6, width: 12 * s, height: 8 * s)
        let corePath = Path(roundedRect: coreRect, cornerRadius: 3 * s, style: .continuous)
        ctx.fill(corePath, with: .color(tint.opacity(isWorking ? (0.75 + 0.25 * pulse) : 0.45)))

        // Character Head
        let headRect = CGRect(x: 27 * s, y: 24 * s + bob, width: 46 * s, height: 31 * s)
        let headPath = Path(roundedRect: headRect, cornerRadius: 11 * s, style: .continuous)
        ctx.fill(
            headPath,
            with: .linearGradient(
                Gradient(colors: [Brand.steel, Brand.titanium]),
                startPoint: CGPoint(x: 50 * s, y: headRect.minY),
                endPoint: CGPoint(x: 50 * s, y: headRect.maxY)
            )
        )

        // Dark Visor Screen
        let visorRect = CGRect(x: 32 * s, y: 31 * s + bob, width: 36 * s, height: 16 * s)
        let visorPath = Path(roundedRect: visorRect, cornerRadius: 6 * s, style: .continuous)
        ctx.fill(visorPath, with: .color(Brand.obsidian))

        // Blinking LED Eyes inside Visor
        let blink = sin(t * 1.9) > 0.96
        let eyeHeight = (blink ? 1.5 : 6.0) * s
        let eyeY = 39 * s + bob - eyeHeight * 0.5
        let leftEye = Path(roundedRect: CGRect(x: 38 * s, y: eyeY, width: 6.5 * s, height: eyeHeight), cornerRadius: 2 * s)
        let rightEye = Path(roundedRect: CGRect(x: 55.5 * s, y: eyeY, width: 6.5 * s, height: eyeHeight), cornerRadius: 2 * s)
        ctx.fill(leftEye, with: .color(tint))
        ctx.fill(rightEye, with: .color(tint))

        // Role-specific headgear & animated tool props
        switch role {
        case .analysis:
            // Radar Antenna on head
            var antenna = Path()
            antenna.move(to: CGPoint(x: 50 * s, y: 24 * s + bob))
            antenna.addLine(to: CGPoint(x: 50 * s, y: 15 * s + bob))
            ctx.stroke(antenna, with: .color(Brand.steel), lineWidth: 2.2 * s)
            let tip = Path(ellipseIn: CGRect(x: 46.5 * s, y: 11 * s + bob, width: 7 * s, height: 7 * s))
            ctx.fill(tip, with: .color(tint))

            if isWorking {
                // Floating holographic blueprint + scan ray
                let holoY = 48 * s + sin(t * 5.0) * 3 * s
                let holoRect = CGRect(x: 68 * s, y: holoY, width: 18 * s, height: 22 * s)
                let holo = Path(roundedRect: holoRect, cornerRadius: 3 * s)
                ctx.fill(holo, with: .color(tint.opacity(0.22)))
                ctx.stroke(holo, with: .color(tint.opacity(0.85)), lineWidth: 1.4 * s)

                let scanY = holoRect.minY + CGFloat((sin(t * 8.0) + 1.0) * 0.5) * holoRect.height
                var scanLine = Path()
                scanLine.move(to: CGPoint(x: holoRect.minX - 2 * s, y: scanY))
                scanLine.addLine(to: CGPoint(x: holoRect.maxX + 2 * s, y: scanY))
                ctx.stroke(scanLine, with: .color(.white), lineWidth: 1.8 * s)
            }

        case .dev:
            // Welder Brow Shield on forehead
            let crest = Path(roundedRect: CGRect(x: 30 * s, y: 21 * s + bob, width: 40 * s, height: 6 * s), cornerRadius: 3 * s)
            ctx.fill(crest, with: .color(Brand.cobalt))

            // Animated Forge Hammer + Electric Sparks
            let swing = isWorking ? sin(t * 12.0) : -0.3
            let hammerX = 74 * s
            let hammerY = (54 + swing * 12) * s
            var handle = Path()
            handle.move(to: CGPoint(x: 66 * s, y: 64 * s + bob * 0.5))
            handle.addLine(to: CGPoint(x: hammerX, y: hammerY))
            ctx.stroke(handle, with: .color(Brand.titanium), lineWidth: 2.8 * s)

            let head = Path(roundedRect: CGRect(x: hammerX - 6 * s, y: hammerY - 5 * s, width: 13 * s, height: 8 * s), cornerRadius: 2 * s)
            ctx.fill(head, with: .color(Brand.steel))

            if isWorking && swing > 0.35 {
                // Flying electric cobalt & icy white sparks on impact
                for i in 0..<4 {
                    let angle = Double(i) * 0.9 + t * 10.0
                    let dist = (8.0 + Double(i) * 3.5) * s
                    let sx = hammerX + CGFloat(cos(angle)) * dist
                    let sy = hammerY + CGFloat(sin(angle)) * dist
                    let spark = Path(ellipseIn: CGRect(x: sx - 2 * s, y: sy - 2 * s, width: 4 * s, height: 4 * s))
                    ctx.fill(spark, with: .color(i % 2 == 0 ? .white : tint))
                }
            }

        case .review:
            // Glowing Optical Monocle over right eye
            let monocle = Path(ellipseIn: CGRect(x: 52 * s, y: 33 * s + bob, width: 14 * s, height: 14 * s))
            ctx.stroke(monocle, with: .color(tint), lineWidth: 2.2 * s)

            // Oscillating Magnifying Loupe
            let sweep = isWorking ? sin(t * 6.5) * 6.0 * s : 0
            let loupeCenter = CGPoint(x: 74 * s + sweep * 0.5, y: 58 * s + sweep * 0.3)
            let lensCircle = Path(ellipseIn: CGRect(x: loupeCenter.x - 8 * s, y: loupeCenter.y - 8 * s, width: 16 * s, height: 16 * s))
            ctx.fill(lensCircle, with: .color(tint.opacity(0.28)))
            ctx.stroke(lensCircle, with: .color(Brand.steel), lineWidth: 2.2 * s)

        case .qa:
            // Sentinel Helmet Crest
            var helm = Path()
            helm.move(to: CGPoint(x: 50 * s, y: 16 * s + bob))
            helm.addLine(to: CGPoint(x: 58 * s, y: 25 * s + bob))
            helm.addLine(to: CGPoint(x: 42 * s, y: 25 * s + bob))
            helm.closeSubpath()
            ctx.fill(helm, with: .color(tint))

            // Pulsing Energy Shield
            let shieldScale = isWorking ? (1.0 + 0.12 * sin(t * 8.0)) : 1.0
            let sw = 18 * s * shieldScale
            let sh = 22 * s * shieldScale
            let shieldRect = CGRect(x: 74 * s - sw * 0.5, y: 58 * s - sh * 0.5, width: sw, height: sh)
            let shield = Path(roundedRect: shieldRect, cornerRadius: 5 * s)
            ctx.fill(shield, with: .color(tint.opacity(isWorking ? 0.35 : 0.18)))
            ctx.stroke(shield, with: .color(tint), lineWidth: 2.0 * s)
        }
    }
}

/// Live animated stage banner shown whenever one or more agents are working on a feature.
struct ActiveAgentStageBanner: View {
    let feature: Feature

    private var activeRuns: [AgentRun] {
        let running = feature.runs.filter { $0.status == .running }
        if !running.isEmpty { return running }
        return []
    }

    private var currentRole: Role {
        activeRuns.first?.role ?? (feature.phase == .analysis ? .analysis : feature.phase == .dev || feature.phase == .fixReview || feature.phase == .fixQA ? .dev : feature.phase == .review ? .review : .qa)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            ForgeCard(padding: 16, cornerRadius: 14, tint: Brand.roleColor(currentRole)) {
                HStack(spacing: 16) {
                    // Animated Character(s) on Stage
                    HStack(spacing: -8) {
                        if activeRuns.count > 1 {
                            ForEach(activeRuns) { run in
                                AgentCharacterAvatar(role: run.role, isWorking: true, size: 56)
                            }
                        } else {
                            AgentCharacterAvatar(role: currentRole, isWorking: true, size: 60)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            PhaseBadge(
                                text: "\(currentRole.personaName.uppercased()) · \(currentRole.personaTitle.uppercased())",
                                tint: Brand.roleColor(currentRole),
                                icon: "sparkles"
                            )
                            if let run = activeRuns.first {
                                ProviderBadge(model: run.model, compact: true)
                            }
                            Spacer()
                            if let firstRun = activeRuns.first {
                                ForgeCodeChip(
                                    text: formatSeconds(firstRun.durationSeconds),
                                    icon: "timer",
                                    tint: Brand.roleColor(currentRole)
                                )
                                ForgeCodeChip(
                                    text: "~\(Brand.formatTokens(activeRuns.reduce(0) { $0 + $1.effectiveTokens })) tok",
                                    icon: "cpu",
                                    tint: Brand.cyan
                                )
                            }
                        }

                        Text(activeRuns.count > 1
                             ? "\(activeRuns.count) agents working in parallel (\(activeRuns.map(\.lens).joined(separator: " & ")))"
                             : "\(currentRole.personaName) travaille sur : \(activeRuns.first?.lens ?? feature.phase.label)")
                            .font(.headline)

                        // Live speech bubble showing latest tool call or thought
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Brand.roleColor(currentRole))
                            Text(activeRuns.compactMap(\.latestActivity).last ?? currentRole.actionVerb)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.obsidian.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Brand.roleColor(currentRole).opacity(0.25), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
    }

    private func formatSeconds(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Overview board on `ProjectHomeView`: shows the 4 animated agent characters, crowns the agent who worked the most,
/// and breaks down tokens spent, tool calls, execution time, and cost across the project.
struct ProjectAgentTelemetryCard: View {
    @Environment(AppStore.self) private var store
    let project: Project

    private var features: [Feature] { store.features(of: project) }
    private var allRuns: [AgentRun] { features.flatMap(\.runs) }

    private var totalTokens: Int { allRuns.reduce(0) { $0 + $1.effectiveTokens } }
    private var totalSeconds: Int { allRuns.reduce(0) { $0 + $1.durationSeconds } }
    private var totalTools: Int { allRuns.reduce(0) { $0 + $1.toolCallsCount } }
    private var totalCost: Double { allRuns.compactMap(\.cost).reduce(0, +) }

    struct RoleStats: Identifiable {
        let role: Role
        let model: String
        let runsCount: Int
        let isCurrentlyWorking: Bool
        let tokens: Int
        let seconds: Int
        let toolCalls: Int
        var id: Role { role }
        /// Weighted score to crown the hardest-working agent on this project.
        var workScore: Int { tokens + seconds * 25 + toolCalls * 150 + runsCount * 400 }
    }

    private var roleStats: [RoleStats] {
        Role.allCases.map { role in
            let runs = allRuns.filter { $0.role == role }
            let assignedModel: String = {
                switch role {
                case .analysis: store.settings.analysisModel
                case .dev: store.settings.devModel
                case .review: store.settings.reviewModel
                case .qa: store.settings.qaModel
                }
            }()
            return RoleStats(
                role: role,
                model: runs.last?.model ?? assignedModel,
                runsCount: runs.count,
                isCurrentlyWorking: runs.contains { $0.status == .running } || (role == .analysis && project.scanning),
                tokens: runs.reduce(0) { $0 + $1.effectiveTokens },
                seconds: runs.reduce(0) { $0 + $1.durationSeconds },
                toolCalls: runs.reduce(0) { $0 + $1.toolCallsCount }
            )
        }
    }

    private var topRole: Role? {
        guard !allRuns.isEmpty else { return nil }
        return roleStats.max(by: { $0.workScore < $1.workScore })?.role
    }

    private var maxScore: Int {
        max(roleStats.map(\.workScore).max() ?? 1, 1)
    }

    var body: some View {
        ForgeCard(padding: 18, cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 16) {
                // Header + Global Telemetry Pills
                HStack(alignment: .center, spacing: 10) {
                    ForgeSectionHeader(
                        title: "Agent Crew & Token Telemetry",
                        subtitle: "Live activity, hardest-working agent (MVP), and token consumption across \(project.name).",
                        icon: "cpu.fill",
                        tint: Brand.cobalt
                    )
                    Spacer()
                    if let mvp = topRole {
                        PhaseBadge(
                            text: "MVP · \(mvp.personaName.uppercased()) (\(mvp.shortTitle.uppercased()))",
                            tint: Brand.cobalt,
                            icon: "crown.fill"
                        )
                    }
                }

                // 4 Global Telemetry Counters
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    telemetryPill(title: "TOKENS CONSUMED", value: Brand.formatTokens(totalTokens), sub: allRuns.contains(where: \.hasExactTokens) ? "CLI reported + est." : "Estimated from logs", icon: "sparkles", tint: Brand.cobalt)
                    telemetryPill(title: "AGENT WORK TIME", value: Jira.formatDuration(totalSeconds), sub: "\(allRuns.count) total run(s)", icon: "clock.fill", tint: Brand.cyan)
                    telemetryPill(title: "TOOL INVOCATIONS", value: "\(totalTools)", sub: "Shell, Read, Edit, MCP", icon: "wrench.and.screwdriver.fill", tint: Brand.indigo)
                    telemetryPill(title: "REPORTED COST", value: totalCost > 0 ? String(format: "$%.2f", totalCost) : "CLI subscription", sub: "Across all runs", icon: "creditcard.fill", tint: Brand.emerald)
                }

                Divider().opacity(0.45)

                // 4 Animated Characters Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 12)], spacing: 12) {
                    ForEach(roleStats) { stat in
                        let isMVP = topRole == stat.role && stat.runsCount > 0
                        let roleTint = Brand.roleColor(stat.role)
                        let share = allRuns.isEmpty ? 0.0 : Double(stat.workScore) / Double(maxScore)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 10) {
                                AgentCharacterAvatar(role: stat.role, isWorking: stat.isCurrentlyWorking, size: 52)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Text(stat.role.personaName)
                                            .font(.headline)
                                        if isMVP {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Brand.cobalt)
                                                .help("Most active agent on this project")
                                        }
                                    }
                                    Text(stat.role.shortTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(roleTint)
                                    ProviderBadge(model: stat.model, showModelName: false, compact: true)
                                }
                                Spacer(minLength: 0)
                            }

                            // Status or Live Activity
                            HStack {
                                Circle()
                                    .fill(stat.isCurrentlyWorking ? roleTint : Color.secondary.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(stat.isCurrentlyWorking ? stat.role.actionVerb : (stat.runsCount == 0 ? "Standing by" : "\(stat.runsCount) run(s) · \(stat.toolCalls) tools"))
                                    .font(.caption)
                                    .foregroundStyle(stat.isCurrentlyWorking ? roleTint : .secondary)
                                    .lineLimit(1)
                                Spacer()
                            }

                            // Work-share progress bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary.opacity(0.5))
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [roleTint, roleTint.opacity(0.65)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(geo.size.width * share, stat.runsCount > 0 ? 10 : 0))
                                }
                            }
                            .frame(height: 5)

                            HStack {
                                Label("\(Brand.formatTokens(stat.tokens)) tok", systemImage: "cpu")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Jira.formatDuration(stat.seconds))
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Brand.obsidian.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(isMVP || stat.isCurrentlyWorking ? roleTint.opacity(0.45) : Brand.steel.opacity(0.10), lineWidth: 1)
                        )
                    }
                }

                // Provider Breakdown if runs exist
                if !allRuns.isEmpty {
                    HStack(spacing: 12) {
                        Text("CLI Usage:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(AgentProvider.allCases) { provider in
                            let providerRuns = allRuns.filter { $0.provider == provider }
                            if !providerRuns.isEmpty {
                                let pTokens = providerRuns.reduce(0) { $0 + $1.effectiveTokens }
                                HStack(spacing: 5) {
                                    Image(systemName: provider.icon)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Brand.providerColor(provider))
                                    Text("\(provider.shortLabel): \(providerRuns.count) run(s) · \(Brand.formatTokens(pTokens)) tok")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Brand.providerColor(provider).opacity(0.10), in: Capsule())
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func telemetryPill(title: String, value: String, sub: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Brand.obsidian.opacity(0.32), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.steel.opacity(0.08), lineWidth: 1)
        )
    }
}

/// Floating in-app notification toast with animated mini-character when an agent starts working or needs approval.
struct AgentToastOverlay: View {
    @Environment(AppStore.self) private var store
    var onSelectFeature: ((UUID) -> Void)? = nil

    var body: some View {
        if let toast = store.activeToast {
            let tint: Color = toast.isError ? Brand.crimson : (toast.role.map(Brand.roleColor) ?? Brand.cobalt)

            HStack(spacing: 12) {
                if let role = toast.role {
                    AgentCharacterAvatar(role: role, isWorking: true, size: 44)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tint.opacity(0.20))
                            .frame(width: 40, height: 40)
                        Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(tint)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(toast.title)
                            .font(.callout.weight(.bold))
                        if let provider = toast.provider {
                            Image(systemName: provider.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Brand.providerColor(provider))
                        }
                    }
                    Text(toast.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        store.activeToast = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: 380, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Brand.charcoal.opacity(0.65))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.55), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .contentShape(Rectangle())
            .onTapGesture {
                if let fID = toast.featureID {
                    onSelectFeature?(fID)
                }
                withAnimation(.spring(duration: 0.25)) {
                    store.activeToast = nil
                }
            }
            .padding(.top, 14)
            .padding(.trailing, 18)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .scale(scale: 0.92)).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
        }
    }
}

